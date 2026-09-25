#!/bin/bash
set -euo pipefail

cd /app
echo "Applying RPG interaction layer..."

cat > src/gui/screen/game/worldInteraction/RpgInteraction.ts <<'TS'
import { MapTileIntersectHelper } from '@/engine/util/MapTileIntersectHelper';
import { MoveOrder } from '@/game/order/MoveOrder';
import { AttackOrder } from '@/game/order/AttackOrder';

export class RpgInteraction {
  private disposeClick?: () => void;
  private hero?: any;
  private badge?: HTMLDivElement;

  constructor(
    private game: any,
    private localPlayer: any,
    private worldScene: any,
    private pointer: any
  ) {}

  init(): void {
    this.hero = this.findHero();
    if (!this.hero) {
      console.warn('[RPG] No controllable hero found.');
      this.showBadge('RPG MODE · No controllable unit');
      return;
    }

    console.log('[RPG] Hero selected:', this.hero.name, this.hero.id);
    this.showBadge('RPG MODE · ' + (this.hero.name || 'Hero'));

    const helper = new MapTileIntersectHelper(this.game.map, this.worldScene);
    const pointerEvents = this.pointer?.pointerEvents;
    const sceneObject = this.worldScene?.get3DObject?.() ?? this.worldScene?.scene;

    if (!pointerEvents || !sceneObject) {
      console.warn('[RPG] Pointer events or world scene unavailable.');
      return;
    }

    this.disposeClick = pointerEvents.addEventListener(sceneObject, 'click', (event: any) => {
      if (event.button !== 0) return;

      const tile = helper.getTileAtScreenPoint(event.pointer);
      if (!tile || !this.hero || this.hero.isDestroyed || this.hero.isDisposed) return;

      const objects = this.game.map.getObjectsOnTile?.(tile) ?? [];
      const enemy = objects.find((obj: any) =>
        obj &&
        obj !== this.hero &&
        obj.isTechno?.() &&
        obj.healthTrait &&
        !obj.isDestroyed &&
        !this.game.areFriendly(obj, this.hero)
      );

      if (enemy && this.hero.attackTrait) {
        const target = this.game.createTarget(enemy, tile);
        const order = new AttackOrder(this.game);
        order.set(this.hero, target);
        if (order.isValid() && order.isAllowed()) {
          this.hero.unitOrderTrait.addOrder(order, false);
          console.log('[RPG] Attack:', enemy.name ?? enemy.id);
          event.stopPropagation?.();
          return;
        }
      }

      const target = this.game.createTarget(undefined, tile);
      const order = new MoveOrder(this.game, this.game.map, this.game.unitSelection, false);
      order.set(this.hero, target);

      if (order.isValid() && order.isAllowed()) {
        this.hero.unitOrderTrait.addOrder(order, false);
        console.log('[RPG] Move:', tile.rx, tile.ry);
        event.stopPropagation?.();
      }
    });
  }

  dispose(): void {
    this.disposeClick?.();
    this.disposeClick = undefined;
    this.badge?.remove();
    this.badge = undefined;
  }

  private findHero(): any | undefined {
    const objects = this.localPlayer?.getOwnedObjects?.() ?? [];
    return (
      objects.find((obj: any) => obj.isInfantry?.() && obj.unitOrderTrait && !obj.isDestroyed) ??
      objects.find((obj: any) => obj.isUnit?.() && obj.unitOrderTrait && !obj.isDestroyed)
    );
  }

  private showBadge(text: string): void {
    const badge = document.createElement('div');
    badge.textContent = text;
    badge.style.position = 'fixed';
    badge.style.left = '12px';
    badge.style.top = '12px';
    badge.style.zIndex = '99999';
    badge.style.padding = '7px 10px';
    badge.style.background = 'rgba(0,0,0,.78)';
    badge.style.border = '1px solid #8ca66c';
    badge.style.color = '#d8f2bc';
    badge.style.fontFamily = 'Arial, sans-serif';
    badge.style.fontSize = '12px';
    badge.style.pointerEvents = 'none';
    document.body.appendChild(badge);
    this.badge = badge;
  }
}
TS

node <<'NODE'
const fs = require('fs');

// Wire RPG mode into CombatantUi without affecting normal RTS mode.
{
  const file = 'src/gui/screen/game/CombatantUi.tsx';
  let src = fs.readFileSync(file, 'utf8');

  if (!src.includes("import { RpgInteraction }")) {
    src = src.replace(
      "import { KeyCommandType } from '@/gui/screen/game/worldInteraction/keyboard/KeyCommandType';",
      "import { KeyCommandType } from '@/gui/screen/game/worldInteraction/keyboard/KeyCommandType';\nimport { RpgInteraction } from '@/gui/screen/game/worldInteraction/RpgInteraction';"
    );
  }

  if (!src.includes("private rpgInteraction?: RpgInteraction;")) {
    src = src.replace(
      "  public worldInteraction?: any;",
      "  public worldInteraction?: any;\n  private rpgInteraction?: RpgInteraction;"
    );
  }

  const marker = "    this.worldInteraction.init();";
  if (src.includes(marker) && !src.includes("new RpgInteraction(")) {
    src = src.replace(
      marker,
      marker + `\n\n    const rpgMode = new URLSearchParams(window.location.search).get('rpg') === '1';\n    if (rpgMode) {\n      this.rpgInteraction = new RpgInteraction(this.game, this.localPlayer, this.worldScene, this.pointer);\n      this.rpgInteraction.init();\n      this.disposables.add(this.rpgInteraction);\n    }`
    );
  }

  fs.writeFileSync(file, src);
}

// In RPG mode never allow a multi-unit selection action to select more than one unit.
{
  const file = 'src/game/action/SelectUnitsAction.ts';
  let src = fs.readFileSync(file, 'utf8');
  const oldLine = "    this._unitIds = value.slice(0, ORDER_UNIT_LIMIT);";
  const newLines = "    const rpgMode = typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('rpg') === '1';\n    this._unitIds = value.slice(0, rpgMode ? 1 : ORDER_UNIT_LIMIT);";
  if (src.includes(oldLine)) src = src.replace(oldLine, newLines);
  fs.writeFileSync(file, src);
}

// Improve fatal game-init diagnostics and avoid misleading replay-save errors.
{
  const file = 'src/gui/screen/game/GameScreen.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    `    let errorMessage = this.strings.get('TS:GameInitError');

    const message = typeof error === 'string' ? error : error.message;
    if (message?.match(/memory|allocation/i)) {
      errorMessage = this.strings.get('TS:GameInitOom');
    } else if (!gameOpts.mapOfficial) {
      errorMessage += '\\n\\n' + this.strings.get('TS:CustomMapCrash');
    }

    this.handleError(error, errorMessage);`,
    `    let errorMessage = this.strings.get('TS:GameInitError');

    const message = typeof error === 'string' ? error : (error?.message || String(error));
    console.error('[GameInit] Fatal initialization error:', error);

    if (message?.match(/memory|allocation/i)) {
      errorMessage = this.strings.get('TS:GameInitOom');
    } else if (!gameOpts.mapOfficial) {
      errorMessage += '\\n\\n' + this.strings.get('TS:CustomMapCrash');
    }

    errorMessage += '\\n\\nTechnical details:\\n' + message;
    this.handleError(error, errorMessage);`
  );

  // If onGameStart itself throws, show the actual runtime error too.
  src = src.replace(
    `          const errorMessage = error.message?.match(/memory|allocation/i)
            ? this.strings.get('TS:GameInitOom')
            : this.strings.get('TS:GameInitError') +
              (game.gameOpts.mapOfficial ? '' : '\\n\\n' + this.strings.get('TS:CustomMapCrash'));
          this.handleGameError(error, errorMessage, game);`,
    `          const runtimeMessage = error instanceof Error ? error.message : String(error);
          console.error('[GameStart] Fatal startup error:', error);
          const errorMessage = (runtimeMessage?.match(/memory|allocation/i)
            ? this.strings.get('TS:GameInitOom')
            : this.strings.get('TS:GameInitError') +
              (game.gameOpts.mapOfficial ? '' : '\\n\\n' + this.strings.get('TS:CustomMapCrash')))
            + '\\n\\nTechnical details:\\n' + runtimeMessage;
          // Do not attempt to save a replay for a game that never initialized.
          this.handleError(error, errorMessage);`
  );

  fs.writeFileSync(file, src);
}

NODE
