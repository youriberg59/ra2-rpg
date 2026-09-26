#!/bin/bash
set -euo pipefail

cd /app
echo "Applying RPG interaction layer..."

cat > src/gui/screen/game/worldInteraction/RpgInteraction.ts <<'TS'
import { MapTileIntersectHelper } from '@/engine/util/MapTileIntersectHelper';
import { MoveOrder } from '@/game/order/MoveOrder';
import { AttackOrder } from '@/game/order/AttackOrder';

export class RpgInteraction {
  private disposeCanvas?: () => void;
  private hero?: any;
  private badge?: HTMLDivElement;

  constructor(
    private game: any,
    private localPlayer: any,
    private worldScene: any,
    private pointer: any,
    private renderer: any
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

    // RPG uses click-to-move, so absolute pointer position must stay meaningful.
    try {
      this.pointer?.unlock?.();
      console.log('[RPG] Pointer lock disabled for click-to-move.');
    } catch (e) {
      console.warn('[RPG] Could not disable pointer lock:', e);
    }

    const helper = new MapTileIntersectHelper(this.game.map, this.worldScene);
    const canvas = this.renderer?.getCanvas?.();

    if (!canvas) {
      console.warn('[RPG] Renderer canvas unavailable.');
      return;
    }

    const handleMouseUp = (event: MouseEvent) => {
      if (event.button !== 0 && event.button !== 2) return;

      const rect = canvas.getBoundingClientRect();
      const tracked = this.pointer?.getPosition?.();
      const pointer = tracked
        ? { x: tracked.x, y: tracked.y }
        : {
            x: event.clientX - rect.left,
            y: event.clientY - rect.top,
          };

      const tile = helper.getTileAtScreenPoint(pointer);
      console.log('[RPG] Move click received', {
        button: event.button,
        pointer,
        tile: tile ? { rx: tile.rx, ry: tile.ry, z: tile.z } : null,
      });
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
          event.preventDefault();
          event.stopPropagation();
          return;
        }
      }

      const target = this.game.createTarget(undefined, tile);
      const order = new MoveOrder(this.game, this.game.map, this.game.unitSelection, false);
      order.set(this.hero, target);

      if (order.isValid() && order.isAllowed()) {
        const trait: any = this.hero.unitOrderTrait;
        const previewTasks = order.process?.() ?? [];
        const tickBefore = this.game.currentTick;

        console.log('[RPG] Before addOrder', {
          tick: tickBefore,
          queuedOrders: trait?.orders?.length,
          previewTasks: previewTasks.map((t: any) => t?.constructor?.name),
          heroSpawned: this.hero?.isSpawned,
          heroTile: this.hero?.tile ? { rx: this.hero.tile.rx, ry: this.hero.tile.ry } : null,
        });

        trait.addOrder(order, false);

        console.log('[RPG] After addOrder', {
          tick: this.game.currentTick,
          queuedOrders: trait?.orders?.length,
          hasTasks: trait?.hasTasks?.(),
          currentTask: trait?.getCurrentTask?.()?.constructor?.name,
        });

        console.log('[RPG] Move:', tile.rx, tile.ry);

        setTimeout(() => {
          try {
            console.log('[RPG] Movement diagnostic', {
              tickBefore,
              tickAfter: this.game.currentTick,
              queuedOrders: trait?.orders?.length,
              heroTile: this.hero?.tile ? { rx: this.hero.tile.rx, ry: this.hero.tile.ry } : null,
              worldPosition: this.hero?.position?.worldPosition,
              hasTasks: trait?.hasTasks?.(),
              currentTask: trait?.getCurrentTask?.()?.constructor?.name,
              moveState: this.hero?.moveTrait?.moveState,
              isMoving: this.hero?.moveTrait?.isMoving?.(),
            });
          } catch (e) {
            console.warn('[RPG] Movement diagnostic failed', e);
          }
        }, 250);

        event.preventDefault();
        event.stopPropagation();
      }
    };

    canvas.addEventListener('mouseup', handleMouseUp, true);
    this.disposeCanvas = () => canvas.removeEventListener('mouseup', handleMouseUp, true);
  }

  dispose(): void {
    this.disposeCanvas?.();
    this.disposeCanvas = undefined;
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
      marker + `\n\n    const rpgMode = new URLSearchParams(window.location.search).get('rpg') === '1';\n    if (rpgMode) {\n      this.rpgInteraction = new RpgInteraction(this.game, this.localPlayer, this.worldScene, this.pointer, this.renderer);\n      this.rpgInteraction.init();\n      this.disposables.add(this.rpgInteraction);\n    }`
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


// Centralize fatal error diagnostics so every message box includes the actual exception.
{
  const file = 'src/ErrorHandler.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    `  handle(error: any, message: string, callback?: () => void): void {
    if (!this.isErrorState) {`,
    `  handle(error: any, message: string, callback?: () => void): void {
    const technical = error instanceof Error
      ? (error.stack || error.message)
      : (typeof error === 'string' ? error : JSON.stringify(error));

    if (technical && !message.includes('Technical details:')) {
      message += '\\n\\nTechnical details:\\n' + technical;
    }

    if (!this.isErrorState) {`
  );

  fs.writeFileSync(file, src);
}

// Suppress replay save attempts when the game never reached a valid running state.
{
  const file = 'src/gui/screen/game/GameScreen.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    `  private handleGameError(error: any, message: string, game: any, debugDataProvider?: () => Promise<any>, isCustomMap?: boolean): void {
    // Simplified game error handling
    const replay = this.replay;
    if (replay) {
      this.saveReplay(replay);
    }`,
    `  private handleGameError(error: any, message: string, game: any, debugDataProvider?: () => Promise<any>, isCustomMap?: boolean): void {
    // Only save replay after the game has actually started.
    const replay = this.replay;
    if (replay && game?.status === GameStatus.Started) {
      this.saveReplay(replay);
    }`
  );

  fs.writeFileSync(file, src);
}


// Make all skirmish AI difficulties start even when optional upstream bot libraries are missing.
{
  const file = 'src/game/bot/BotFactory.ts';
  let src = fs.readFileSync(file, 'utf8');

  const oldSwitch = `    switch (player.aiDifficulty) {
      case AiDifficulty.Easy:
        return new DummyBot(player.name, player.country.name);
      case AiDifficulty.Medium:
        if (this.botsLib.SupalosaBot) {
          return new this.botsLib.SupalosaBot(player.name, player.country.name);
        }
      default:
        throw new Error(\`Unsupported AI difficulty "\${player.aiDifficulty}"\`);
    }`;

  const newSwitch = `    switch (player.aiDifficulty) {
      case AiDifficulty.Easy:
        return new DummyBot(player.name, player.country.name);

      case AiDifficulty.Medium:
        if (this.botsLib?.SupalosaBot) {
          return new this.botsLib.SupalosaBot(player.name, player.country.name);
        }
        console.warn('[BotFactory] SupalosaBot unavailable; using DummyBot for Medium AI.');
        return new DummyBot(player.name, player.country.name);

      case AiDifficulty.Brutal:
        console.warn('[BotFactory] Brutal AI implementation unavailable; using DummyBot fallback.');
        return new DummyBot(player.name, player.country.name);

      default:
        console.warn('[BotFactory] Unknown AI difficulty', player.aiDifficulty, '- using DummyBot fallback.');
        return new DummyBot(player.name, player.country.name);
    }`;

  if (!src.includes(oldSwitch)) {
    console.error('Expected BotFactory difficulty switch not found.');
    process.exit(1);
  }

  src = src.replace(oldSwitch, newSwitch);
  fs.writeFileSync(file, src);
}


// Prevent visibility/audio compatibility mismatches from crashing the game loop.
{
  const file = 'src/engine/GameAnimationLoop.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    `      this.sound.audioSystem.setMuted(this.paused);`,
    `      const audioSystem = this.sound?.audioSystem as any;
      if (audioSystem && typeof audioSystem.setMuted === 'function') {
        audioSystem.setMuted(this.paused);
      } else {
        console.warn('[GameAnimationLoop] audioSystem.setMuted unavailable; skipping visibility mute.');
      }`
  );

  fs.writeFileSync(file, src);
}

// Suppress replay-save error toast entirely for now; replay persistence in this
// upstream fork is incomplete and unrelated to RPG gameplay.
{
  const file = 'src/gui/screen/game/GameScreen.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    `      } catch (error) {
        console.error(error);
        this.toastApi.push(this.strings.get('GUI:SaveReplayError'));
      }`,
    `      } catch (error) {
        console.warn('[Replay] Save failed; ignoring in self-hosted RPG mode.', error);
      }`
  );

  fs.writeFileSync(file, src);
}


// Register the actual battlefield WorldScene with the renderer.
// The upstream fork currently creates it but only registers UiScene,
// resulting in a working HUD over a completely black battlefield.
{
  const file = 'src/gui/screen/game/GameScreen.ts';
  let src = fs.readFileSync(file, 'utf8');

  const oldBlock = `    if (ws?.set3DObject && ws?.scene) {
      ws.set3DObject(ws.scene);
    }
    worldViewInit.worldScene.create3DObject?.();

    return {`;

  const newBlock = `    if (ws?.set3DObject && ws?.scene) {
      ws.set3DObject(ws.scene);
    }
    worldViewInit.worldScene.create3DObject?.();

    // Critical: WorldScene must be registered separately from UiScene.
    this.renderer.addScene?.(worldViewInit.worldScene);
    this.disposables.add(() => {
      try {
        this.renderer.removeScene?.(worldViewInit.worldScene);
      } catch (e) {
        console.warn('[GameScreen] Failed to remove WorldScene from renderer', e);
      }
    });

    console.log('[GameScreen] WorldScene registered with renderer.', {
      scenes: this.renderer.getScenes?.().length
    });

    return {`;

  if (!src.includes(oldBlock)) {
    console.error('Expected WorldScene initialization block not found.');
    process.exit(1);
  }

  src = src.replace(oldBlock, newBlock);
  fs.writeFileSync(file, src);
}


// Render the actual isometric terrain using the upstream MapTileLayer.
// This is the first real world-rendering stage; units/buildings are wired next.
{
  const file = 'src/gui/screen/game/WorldView.ts';
  let src = fs.readFileSync(file, 'utf8');

  if (!src.includes("import { MapTileLayer }")) {
    src = src.replace(
      "import { MapPanningHelper } from '@/engine/util/MapPanningHelper';",
      "import { MapPanningHelper } from '@/engine/util/MapPanningHelper';\nimport { MapTileLayer } from '@/engine/renderable/entity/map/MapTileLayer';\nimport { Lighting } from '@/engine/Lighting';\nimport { ImageFinder } from '@/engine/ImageFinder';\nimport { BoxedVar } from '@/util/BoxedVar';"
    );
  }

  const old = `    // Minimal placeholders for components not yet migrated
    const worldSound = {};
    const superWeaponFxHandler = this.createSuperWeaponFxHandler();
    const beaconFxHandler = this.createBeaconFxHandler();
    const renderableManager = this.createRenderableManager();

    // Configure viewport
    this.setupViewport(viewport);

    return {
      worldScene,
      worldSound,
      superWeaponFxHandler,
      beaconFxHandler,
      renderableManager
    };`;

  const neu = `    // First real rendering stage: draw the actual RA2 isometric map tiles.
    const lighting = new Lighting();
    const imageFinder = new ImageFinder(Engine.getImages() as any, theater);
    const debugWireframe = this.runtimeVars?.debugWireframes ?? new BoxedVar(false);

    const mapTileLayer = new MapTileLayer(
      this.game.map,
      theater,
      this.game.art,
      imageFinder,
      worldScene.camera,
      debugWireframe,
      this.game.speed,
      null,
      lighting,
      false
    );

    worldScene.add(mapTileLayer as any);
    this.disposables.add(
      mapTileLayer as any,
      lighting as any,
      () => {
        try {
          worldScene.remove(mapTileLayer as any);
        } catch {}
      }
    );

    const worldSound = {};
    const superWeaponFxHandler = this.createSuperWeaponFxHandler();
    const beaconFxHandler = this.createBeaconFxHandler();
    const renderableManager = this.createRenderableManager();

    this.setupViewport(viewport);

    console.log('[WorldView] Real map tile layer attached.', {
      tiles: this.game.map?.tiles?.getAll?.().length
    });

    return {
      worldScene,
      worldSound,
      superWeaponFxHandler,
      beaconFxHandler,
      renderableManager
    };`;

  if (!src.includes(old)) {
    console.error('Expected WorldView placeholder block not found.');
    process.exit(1);
  }

  src = src.replace(old, neu);
  fs.writeFileSync(file, src);
}


// Three.js compatibility: BufferGeometry.applyMatrix() was renamed to applyMatrix4().
// Normalize the old API across the upstream rendering code.
{
  const { execSync } = require('child_process');
  execSync(
    "find src -type f \\( -name '*.ts' -o -name '*.tsx' \\) -print0 | xargs -0 sed -i 's/\\.applyMatrix(/.applyMatrix4(/g'",
    { stdio: 'inherit' }
  );
}


// Center the world camera on the actual loaded map.
// CameraPan defaults to (0,0) and the upstream WorldView.setupViewport() is empty,
// leaving a perfectly valid map outside the viewport.
{
  const file = 'src/gui/screen/game/WorldView.ts';
  let src = fs.readFileSync(file, 'utf8');

  if (!src.includes("import { IsoCoords }")) {
    src = src.replace(
      "import { BoxedVar } from '@/util/BoxedVar';",
      "import { BoxedVar } from '@/util/BoxedVar';\nimport { IsoCoords } from '@/engine/IsoCoords';"
    );
  }

  const marker = "    worldScene.add(mapTileLayer as any);";
  const cameraBlock = `
    // Center camera using the actual average map tile position in screen space.
    const mapTiles = this.game.map?.tiles?.getAll?.() ?? [];
    if (mapTiles.length) {
      let sx = 0;
      let sy = 0;
      let count = 0;

      for (const tile of mapTiles) {
        if (!tile) continue;
        const p = IsoCoords.tile3dToScreen(tile.rx, tile.ry, tile.z ?? 0);
        sx += p.x;
        sy += p.y;
        count++;
      }

      if (count) {
        const projectedCenter = { x: sx / count, y: sy / count };
        const projectedOrigin = IsoCoords.worldToScreen(0, 0);
        const pan = {
          x: projectedCenter.x - projectedOrigin.x,
          y: projectedCenter.y - projectedOrigin.y,
        };

        worldScene.cameraPan.setPan(pan);
        worldScene.updateCamera(pan, worldScene.cameraZoom.getZoom());
        console.log('[WorldView] Camera centered on map.', {
          projectedCenter,
          projectedOrigin,
          pan
        });
      }
    }
`;

  if (src.includes(marker) && !src.includes("[WorldView] Camera centered on map.")) {
    src = src.replace(marker, marker + cameraBlock);
  }

  fs.writeFileSync(file, src);
}


// Keep HUD above WorldScene, add camera controls, and show a live RPG hero marker.
{
  // 1) Render ordering: world first, UI last.
  const gameScreenFile = 'src/gui/screen/game/GameScreen.ts';
  let gs = fs.readFileSync(gameScreenFile, 'utf8');

  const reg = `    this.renderer.addScene?.(worldViewInit.worldScene);
    this.disposables.add(() => {`;

  const reg2 = `    this.renderer.addScene?.(worldViewInit.worldScene);

    // Renderer uses insertion order. UiScene was registered first, so re-add it
    // after WorldScene to keep the HUD/sidebar above the battlefield.
    if (this.uiScene) {
      this.renderer.removeScene?.(this.uiScene);
      this.renderer.addScene?.(this.uiScene);
    }

    this.disposables.add(() => {`;

  if (gs.includes(reg) && !gs.includes('keep the HUD/sidebar above the battlefield')) {
    gs = gs.replace(reg, reg2);
  }
  fs.writeFileSync(gameScreenFile, gs);

  // 2) Camera controls and temporary hero marker in WorldView.
  const worldViewFile = 'src/gui/screen/game/WorldView.ts';
  let wv = fs.readFileSync(worldViewFile, 'utf8');

  if (!wv.includes("import * as THREE from 'three';")) {
    wv = wv.replace(
      "import { IsoCoords } from '@/engine/IsoCoords';",
      "import { IsoCoords } from '@/engine/IsoCoords';\nimport * as THREE from 'three';"
    );
  }

  const marker = "    console.log('[WorldView] Real map tile layer attached.', {";
  const controls = `
    // Camera controls: arrow keys + middle-mouse drag.
    const canvas = this.renderer.getCanvas?.();
    if (canvas) {
      let dragging = false;
      let lastX = 0;
      let lastY = 0;

      const applyPanDelta = (dx: number, dy: number) => {
        const current = worldScene.cameraPan.getPan();
        const next = { x: current.x + dx, y: current.y + dy };
        worldScene.cameraPan.setPan(next);
        worldScene.updateCamera(worldScene.cameraPan.getPan(), worldScene.cameraZoom.getZoom());
      };

      const onMouseDown = (ev: MouseEvent) => {
        if (ev.button === 1) {
          dragging = true;
          lastX = ev.clientX;
          lastY = ev.clientY;
          ev.preventDefault();
        }
      };
      const onMouseMove = (ev: MouseEvent) => {
        if (!dragging) return;
        const dx = lastX - ev.clientX;
        const dy = lastY - ev.clientY;
        lastX = ev.clientX;
        lastY = ev.clientY;
        applyPanDelta(dx, dy);
      };
      const onMouseUp = (ev: MouseEvent) => {
        if (ev.button === 1) dragging = false;
      };
      const onKeyDown = (ev: KeyboardEvent) => {
        const step = ev.shiftKey ? 80 : 28;
        if (ev.key === 'ArrowLeft') applyPanDelta(-step, 0);
        else if (ev.key === 'ArrowRight') applyPanDelta(step, 0);
        else if (ev.key === 'ArrowUp') applyPanDelta(0, -step);
        else if (ev.key === 'ArrowDown') applyPanDelta(0, step);
        else return;
        ev.preventDefault();
      };

      canvas.addEventListener('mousedown', onMouseDown);
      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', onMouseUp);
      window.addEventListener('keydown', onKeyDown);

      this.disposables.add(() => {
        canvas.removeEventListener('mousedown', onMouseDown);
        window.removeEventListener('mousemove', onMouseMove);
        window.removeEventListener('mouseup', onMouseUp);
        window.removeEventListener('keydown', onKeyDown);
      });
    }

    // Temporary visible marker for the single RPG hero while the full RA2
    // RenderableManager is being restored.
    const rpgMode = new URLSearchParams(window.location.search).get('rpg') === '1';
    if (rpgMode) {
      const hero = (localPlayer?.getOwnedObjects?.() ?? []).find((obj: any) =>
        !obj?.isDestroyed && obj?.unitOrderTrait && (obj?.isInfantry?.() || obj?.isUnit?.())
      );

      if (hero?.position?.worldPosition) {
        const geometry = new THREE.CylinderGeometry(55, 55, 16, 24);
        const material = new THREE.MeshBasicMaterial({ color: 0xffff00 });
        const heroMarker = new THREE.Mesh(geometry, material);
        heroMarker.name = 'rpg_hero_marker';
        heroMarker.position.set(
          hero.position.worldPosition.x,
          hero.position.worldPosition.y + 12,
          hero.position.worldPosition.z
        );
        worldScene.scene.add(heroMarker);

        const updateHeroMarker = () => {
          const p = hero.position.worldPosition;
          heroMarker.position.set(p.x, p.y + 12, p.z);
          heroMarker.updateMatrix();
        };
        hero.position.onPositionChange?.subscribe(updateHeroMarker);

        this.disposables.add(() => {
          hero.position.onPositionChange?.unsubscribe(updateHeroMarker);
          worldScene.scene.remove(heroMarker);
          geometry.dispose();
          material.dispose();
        });

        console.log('[WorldView] RPG hero marker attached.', hero.name, hero.id);
      } else {
        console.warn('[WorldView] RPG mode active but no controllable hero found.');
      }
    }

`;

  if (wv.includes(marker) && !wv.includes('Camera controls: arrow keys + middle-mouse drag.')) {
    wv = wv.replace(marker, controls + marker);
  }
  fs.writeFileSync(worldViewFile, wv);
}


// RPG startup: ensure the local player gets a real infantry hero instead of the MCV.
{
  const file = 'src/game/Game.ts';
  let src = fs.readFileSync(file, 'utf8');

  const anchor = `      const mcvRules = this.rules.getObject(mcvName, ObjectType.Vehicle);
      const mcv = this.createUnitForPlayer(mcvRules, player);
      this.spawnObject(mcv, startTile);
`;

  const replacement = `      const mcvRules = this.rules.getObject(mcvName, ObjectType.Vehicle);
      const mcv = this.createUnitForPlayer(mcvRules, player);
      this.spawnObject(mcv, startTile);

      // RPG mode always gives the local player one infantry hero, independent
      // of the Skirmish starting-unit count.
      const rpgMode = typeof window !== 'undefined' &&
        new URLSearchParams(window.location.search).get('rpg') === '1';

      if (rpgMode && player === this.localPlayer) {
        const infantryRules = [...this.rules.infantryRules.values()].filter((unit: any) =>
          unit.techLevel !== -1 &&
          !unit.naval &&
          unit.isAvailableTo(player.country) &&
          unit.hasOwner(player.country) &&
          this.art.hasObject(unit.name, ObjectType.Infantry)
        );

        const preferredNames = ['E1', 'E2', 'GI', 'CONSCRIPT'];
        const heroRules =
          preferredNames
            .map((name) => infantryRules.find((u: any) => u.name.toUpperCase() === name))
            .find(Boolean) ??
          infantryRules.find((u: any) => !!u.primary) ??
          infantryRules[0];

        if (heroRules) {
          const finder = new CardinalTileFinder(
            this.map.tiles,
            this.map.mapBounds,
            startTile,
            4,
            1,
            (tile: any) =>
              !this.map
                .getGroundObjectsOnTile(tile)
                .find((obj: any) => !(obj.isSmudge() || (obj.isOverlay() && obj.isTiberium()))) &&
              this.map.terrain.getPassableSpeed(tile, SpeedType.Foot, false, false) > 0
          );

          const heroTile = finder.getNextTile() ?? startTile;
          const hero = this.createUnitForPlayer(heroRules, player);
          hero.position.subCell = Infantry.SUB_CELLS[0];
          (hero as any).__rpgHero = true;
          this.spawnObject(hero, heroTile);
          this.unitSelection.deselectAll();
          this.unitSelection.addToSelection(hero);

          console.log('[RPG] Spawned local hero:', hero.name, hero.id, heroTile.rx, heroTile.ry);
        } else {
          console.warn('[RPG] No infantry rules available for local player faction.');
        }
      }
`;

  if (!src.includes(anchor)) {
    console.error('Expected MCV spawn block not found.');
    process.exit(1);
  }

  src = src.replace(anchor, replacement);
  fs.writeFileSync(file, src);
}

// Prefer the explicit RPG hero and never fall back to the MCV unless no infantry exists.
{
  const file = 'src/gui/screen/game/worldInteraction/RpgInteraction.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    `    return (
      objects.find((obj: any) => obj.isInfantry?.() && obj.unitOrderTrait && !obj.isDestroyed) ??
      objects.find((obj: any) => obj.isUnit?.() && obj.unitOrderTrait && !obj.isDestroyed)
    );`,
    `    return (
      objects.find((obj: any) => obj.__rpgHero && obj.unitOrderTrait && !obj.isDestroyed) ??
      objects.find((obj: any) => obj.isInfantry?.() && obj.unitOrderTrait && !obj.isDestroyed)
    );`
  );

  fs.writeFileSync(file, src);
}

// Hero marker + camera should use the explicit RPG hero.
{
  const file = 'src/gui/screen/game/WorldView.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    `      const hero = (localPlayer?.getOwnedObjects?.() ?? []).find((obj: any) =>
        !obj?.isDestroyed && obj?.unitOrderTrait && (obj?.isInfantry?.() || obj?.isUnit?.())
      );`,
    `      const owned = localPlayer?.getOwnedObjects?.() ?? [];
      const hero =
        owned.find((obj: any) => obj?.__rpgHero && !obj?.isDestroyed) ??
        owned.find((obj: any) => obj?.isInfantry?.() && !obj?.isDestroyed && obj?.unitOrderTrait);`
  );

  const marker = `        console.log('[WorldView] RPG hero marker attached.', hero.name, hero.id);`;
  const centered = `        const heroPan = new MapPanningHelper(this.game.map).computeCameraPanFromWorld(hero.position.worldPosition);
        worldScene.cameraPan.setPan(heroPan);
        worldScene.updateCamera(worldScene.cameraPan.getPan(), worldScene.cameraZoom.getZoom());
        console.log('[WorldView] RPG hero marker attached and camera centered.', hero.name, hero.id, heroPan);`;

  if (src.includes(marker)) {
    src = src.replace(marker, centered);
  }

  fs.writeFileSync(file, src);
}


// In RPG mode, hard-lock the camera to the hero and disable manual camera panning.
{
  const file = 'src/gui/screen/game/WorldView.ts';
  let src = fs.readFileSync(file, 'utf8');

  // Manual camera controls remain available in RTS mode only.
  src = src.replace(
    `    const canvas = this.renderer.getCanvas?.();
    if (canvas) {`,
    `    const canvas = this.renderer.getCanvas?.();
    const cameraLockedToHero = new URLSearchParams(window.location.search).get('rpg') === '1';
    if (canvas && !cameraLockedToHero) {`
  );

  // Follow the hero every time its position changes.
  src = src.replace(
    `        const updateHeroMarker = () => {
          const p = hero.position.worldPosition;
          heroMarker.position.set(p.x, p.y + 12, p.z);
          heroMarker.updateMatrix();
        };`,
    `        const updateHeroMarker = () => {
          const p = hero.position.worldPosition;
          heroMarker.position.set(p.x, p.y + 12, p.z);
          heroMarker.updateMatrix();

          const heroPan = new MapPanningHelper(this.game.map).computeCameraPanFromWorld(p);
          worldScene.cameraPan.setPan(heroPan);
          worldScene.updateCamera(worldScene.cameraPan.getPan(), worldScene.cameraZoom.getZoom());
        };`
  );

  fs.writeFileSync(file, src);
}


// Fix screen -> tile conversion for RPG clicks.
// The upstream helper mixed absolute canvas coordinates with viewport-relative camera pan,
// causing different clicks to resolve to the same map tile.
{
  const file = 'src/engine/util/MapTileIntersectHelper.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
`interface Scene {
  viewport: Viewport;
  cameraPan: CameraPan;
}`,
`interface Scene {
  viewport: Viewport;
  cameraPan: CameraPan;
  cameraZoom?: { getZoom(): number };
}`
  );

  const oldMethod = `  getTileAtScreenPoint(screenPoint: Point): MapTile | undefined {
    const viewport = this.scene.viewport;
    if (rectContainsPoint(viewport, screenPoint)) {
      const intersectedTiles = this.intersectTilesByScreenPos(screenPoint);
      return intersectedTiles.length > 0 ? intersectedTiles[0] : undefined;
    }
    return undefined;
  }`;

  const newMethod = `  getTileAtScreenPoint(screenPoint: Point): MapTile | undefined {
    const viewport = this.scene.viewport;
    if (!rectContainsPoint(viewport, screenPoint)) {
      return undefined;
    }

    const origin = IsoCoords.worldToScreen(0, 0);
    const pan = this.scene.cameraPan.getPan();
    const zoom = this.scene.cameraZoom?.getZoom?.() ?? 1;

    // Convert absolute canvas coordinates to offsets from the center of the
    // world viewport, then undo camera zoom and pan.
    const localX = screenPoint.x - viewport.x - viewport.width / 2;
    const localY = screenPoint.y - viewport.y - viewport.height / 2;

    const worldScreenX = origin.x + pan.x + localX / zoom;
    const worldScreenY = origin.y + pan.y + localY / zoom;

    const worldPos = IsoCoords.screenToWorld(worldScreenX, worldScreenY);
    const tileX = Math.floor(worldPos.x / Coords.LEPTONS_PER_TILE);
    const tileY = Math.floor(worldPos.y / Coords.LEPTONS_PER_TILE);

    // Prefer the exact tile; if elevation/edge projection puts us just over a
    // boundary, choose the nearest valid neighboring tile.
    const exact = this.map.tiles.getByMapCoords(tileX, tileY);
    if (exact) {
      return exact;
    }

    for (let radius = 1; radius <= 2; radius++) {
      for (let dx = -radius; dx <= radius; dx++) {
        for (let dy = -radius; dy <= radius; dy++) {
          const tile = this.map.tiles.getByMapCoords(tileX + dx, tileY + dy);
          if (tile) return tile;
        }
      }
    }

    return undefined;
  }`;

  if (!src.includes(oldMethod)) {
    console.error('Expected MapTileIntersectHelper.getTileAtScreenPoint block not found.');
    process.exit(1);
  }

  src = src.replace(oldMethod, newMethod);
  fs.writeFileSync(file, src);
}


// Restore the actual game simulation loop.
// Upstream GameTurnManager.doGameTurn() is a placeholder that only returns true,
// so Game.currentTick never advances and queued orders are never processed.
{
  const file = 'src/game/GameTurnManager.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
`export class GameTurnManager {
  private gameTurnMillis: number = 33; // ~30 FPS default
  private errorState = false;`,
`export class GameTurnManager {
  private gameTurnMillis: number = 33; // ~30 FPS default
  private errorState = false;
  private game?: any;

  constructor(game?: any) {
    this.game = game;
  }`
  );

  src = src.replace(
`  doGameTurn(_timestamp: number): boolean {
    // In SP placeholder we just signal a successful tick
    return true;
  }`,
`  doGameTurn(_timestamp: number): boolean {
    if (this.errorState) {
      return false;
    }

    if (this.game) {
      this.game.update();
    }

    return true;
  }`
  );

  src = src.replace(
`  dispose(): void {
    // No-op
  }`,
`  dispose(): void {
    this.game = undefined;
  }`
  );

  fs.writeFileSync(file, src);
}

// Pass the loaded Game instance into GameTurnManager.
{
  const file = 'src/gui/screen/game/GameScreen.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
    "    this.gameTurnMgr = new GameTurnManager();",
    "    this.gameTurnMgr = new GameTurnManager(game);"
  );

  fs.writeFileSync(file, src);
}


// Harden BotManager against missing optional logger/bot instances in this fork.
{
  const file = 'src/game/BotManager.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
`      if (actionLog) {
        this.actionLogger.debug(\`(\${action.player.name})@\${gameState.currentTick}: \${actionLog}\`);
      }`,
`      if (actionLog) {
        this.actionLogger?.debug?.(
          \`(\${action.player?.name ?? 'AI'})@\${gameState.currentTick}: \${actionLog}\`
        );
      }`
  );

  src = src.replace(
`    for (const combatant of gameState.getCombatants().filter((c: any) => c.isAi)) {
      this.bots.get(combatant).onGameTick(this.gameApi);
    }`,
`    for (const combatant of gameState.getCombatants().filter((c: any) => c.isAi)) {
      const bot = this.bots.get(combatant);
      if (bot?.onGameTick) {
        bot.onGameTick(this.gameApi);
      }
    }`
  );

  fs.writeFileSync(file, src);
}


// Fix misuse of Traits.filter() inside MoveTrait.
// Traits.filter expects a trait interface descriptor, not an Array.filter callback.
// Passing arrow functions caused "Function has non-object prototype 'undefined' in instanceof check"
// as soon as a moving unit crossed a tile.
{
  const file = 'src/game/gameobject/trait/MoveTrait.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
`    gameObject.traits.filter((trait): trait is typeof NotifyTeleport => 
      'onBeforeTeleport' in trait
    ).forEach(trait => {
      trait[NotifyTeleport.onBeforeTeleport](gameObject, gameState, fromTile, preserveMovement);
    });`,
`    gameObject.traits.filter(NotifyTeleport).forEach((trait: any) => {
      trait[NotifyTeleport.onBeforeTeleport](gameObject, gameState, fromTile, preserveMovement);
    });`
  );

  src = src.replace(
`    gameState.traits.filter((trait): trait is typeof GlobalNotifyTileChange => 
      'onTileChange' in trait
    ).forEach(trait => {
      trait[GlobalNotifyTileChange.onTileChange](gameObject, gameState, oldTile, isTeleport);
    });`,
`    gameState.traits.filter(GlobalNotifyTileChange).forEach((trait: any) => {
      trait[GlobalNotifyTileChange.onTileChange](gameObject, gameState, oldTile, isTeleport);
    });`
  );

  src = src.replace(
`    gameObject.traits.filter((trait): trait is typeof NotifyTileChange => 
      'onTileChange' in trait
    ).forEach(trait => {
      trait[NotifyTileChange.onTileChange](gameObject, gameState, oldTile, isTeleport);
    });`,
`    gameObject.traits.filter(NotifyTileChange).forEach((trait: any) => {
      trait[NotifyTileChange.onTileChange](gameObject, gameState, oldTile, isTeleport);
    });`
  );

  src = src.replace(
`    gameState.traits.filter((trait): trait is typeof NotifyElevationChange => 
      'onElevationChange' in trait
    ).forEach(trait => {
      trait[NotifyElevationChange.onElevationChange](
        this.gameObject,
        gameState,
        oldElevation
      );
    });`,
`    gameState.traits.filter(NotifyElevationChange).forEach((trait: any) => {
      trait[NotifyElevationChange.onElevationChange](
        this.gameObject,
        gameState,
        oldElevation
      );
    });`
  );

  fs.writeFileSync(file, src);
}


// Make Traits.filter() support both trait descriptors/classes and predicate callbacks.
// Several files in this fork use Traits.filter like Array.filter, which previously caused
// "Function has non-object prototype 'undefined' in instanceof check".
{
  const file = 'src/game/Traits.ts';
  let src = fs.readFileSync(file, 'utf8');

  const oldBlock = `  filter(type: any): any[] {
    let cached = this.traitsByTypeCache.get(type);
    if (cached) {
      return cached;
    }

    cached = typeof type === 'function' 
      ? this.allTraits.filter(trait => trait instanceof type)
      : this.allTraits.filter(trait => this.traitImplements(trait, type));

    this.traitsByTypeCache.set(type, cached);
    return cached;
  }`;

  const newBlock = `  filter(type: any): any[] {
    let cached = this.traitsByTypeCache.get(type);
    if (cached) {
      return cached;
    }

    if (typeof type === 'function') {
      const proto = (type as any).prototype;

      // Constructor/class: preserve the original instanceof behavior.
      if (proto && typeof proto === 'object') {
        cached = this.allTraits.filter(trait => trait instanceof type);
      } else {
        // Arrow/function predicate: some forked gameplay files use Traits.filter
        // exactly like Array.filter().
        cached = this.allTraits.filter((trait, index) => {
          try {
            return !!type(trait, index, this.allTraits);
          } catch {
            return false;
          }
        });
      }
    } else {
      cached = this.allTraits.filter(trait => this.traitImplements(trait, type));
    }

    this.traitsByTypeCache.set(type, cached);
    return cached;
  }`;

  if (!src.includes(oldBlock)) {
    console.error('Expected Traits.filter implementation not found.');
    process.exit(1);
  }

  src = src.replace(oldBlock, newBlock);
  fs.writeFileSync(file, src);
}


// Preserve exact click position inside the destination tile for RPG movement.
{
  // Extend MoveOrder with an optional target offset and forward it to MoveTask.
  const file = 'src/game/order/MoveOrder.ts';
  let src = fs.readFileSync(file, 'utf8');

  if (!src.includes("import { Vector2 }")) {
    src = src.replace(
      'import { MoveTargetTask } from "@/game/gameobject/task/move/MoveTargetTask";',
      'import { MoveTargetTask } from "@/game/gameobject/task/move/MoveTargetTask";\nimport { Vector2 } from "@/game/math/Vector2";'
    );
  }

  src = src.replace(
    "    public feedbackType: OrderFeedbackType;",
    "    public feedbackType: OrderFeedbackType;\n    private targetOffset?: Vector2;
    private exactTarget: boolean = false;"
  );

  if (!src.includes("setTargetOffset(offset: Vector2)")) {
    src = src.replace(
      "    getPointerType(isMini: boolean): PointerType {",
      "    setTargetOffset(offset: Vector2): void {\n        this.targetOffset = offset;\n    }\n\n    getPointerType(isMini: boolean): PointerType {"
    );
  }

  src = src.replace(
    "{ closeEnoughTiles, forceMove: this.forceMove }",
    "{
                        closeEnoughTiles: this.exactTarget ? 0 : closeEnoughTiles,
                        strictCloseEnough: this.exactTarget,
                        forceMove: this.forceMove,
                        targetOffset: this.targetOffset
                    }"
  );

  src = src.replace(
    "                existingMoveTask.updateTarget(this.target.tile, !!this.target.getBridge());",
    "                existingMoveTask.updateTarget(this.target.tile, !!this.target.getBridge(), this.targetOffset);"
  );

  fs.writeFileSync(file, src);
}

// Allow an in-progress MoveTask to receive a new exact intra-tile offset.
{
  const file = 'src/game/gameobject/task/move/MoveTask.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src.replace(
`  updateTarget(tile: Tile, toBridge: boolean): void {
    this.targetTile = tile;
    this.toBridge = toBridge;
    this.needsPathUpdate = true;
    this.targetChangeRequested = true;
  }`,
`  updateTarget(tile: Tile, toBridge: boolean, targetOffset?: Vector2): void {
    this.targetTile = tile;
    this.toBridge = toBridge;
    if (targetOffset) {
      this.options ??= {};
      this.options.targetOffset = targetOffset;
      this.targetOffset = targetOffset;
    }
    this.needsPathUpdate = true;
    this.targetChangeRequested = true;
  }`
  );

  fs.writeFileSync(file, src);
}

// Compute the exact click offset inside the selected tile in RPG interaction.
{
  const file = 'src/gui/screen/game/worldInteraction/RpgInteraction.ts';
  let src = fs.readFileSync(file, 'utf8');

  if (!src.includes("import { IsoCoords }")) {
    src = src.replace(
      "import { AttackOrder } from '@/game/order/AttackOrder';",
      "import { AttackOrder } from '@/game/order/AttackOrder';\nimport { IsoCoords } from '@/engine/IsoCoords';\nimport { Coords } from '@/game/Coords';\nimport { Vector2 } from '@/game/math/Vector2';"
    );
  }

  const anchor = "      const target = this.game.createTarget(undefined, tile);";
  const replacement = `      const viewport = this.worldScene.viewport;
      const pan = this.worldScene.cameraPan.getPan();
      const zoom = this.worldScene.cameraZoom?.getZoom?.() ?? 1;
      const origin = IsoCoords.worldToScreen(0, 0);

      const localX = pointer.x - viewport.x - viewport.width / 2;
      const localY = pointer.y - viewport.y - viewport.height / 2;
      const worldScreenX = origin.x + pan.x + localX / zoom;
      const worldScreenY = origin.y + pan.y + localY / zoom;
      // The rendered tile is shifted upward by its elevation. Undo that shift
      // before converting back to ground-plane world coordinates.
      const elevationScreenOffset = IsoCoords.tileHeightToScreen(tile.z ?? 0);
      const worldPos = IsoCoords.screenToWorld(
        worldScreenX,
        worldScreenY + elevationScreenOffset
      );

      const clamp = (value: number) =>
        Math.max(0, Math.min(Coords.LEPTONS_PER_TILE - 1, value));

      const exactOffset = new Vector2(
        clamp(worldPos.x - tile.rx * Coords.LEPTONS_PER_TILE),
        clamp(worldPos.y - tile.ry * Coords.LEPTONS_PER_TILE)
      );

      const target = this.game.createTarget(undefined, tile);`;

  if (!src.includes(anchor)) {
    console.error('Expected RPG move target creation not found.');
    process.exit(1);
  }
  src = src.replace(anchor, replacement);

  src = src.replace(
    "      const order = new MoveOrder(this.game, this.game.map, this.game.unitSelection, false);\n      order.set(this.hero, target);",
    "      const order = new MoveOrder(this.game, this.game.map, this.game.unitSelection, false);\n      order.set(this.hero, target);\n      order.setTargetOffset(exactOffset, true);"
  );

  src = src.replace(
    "        console.log('[RPG] Move:', tile.rx, tile.ry);",
    "        console.log('[RPG] Move:', tile.rx, tile.ry, 'offset', { x: exactOffset.x, y: exactOffset.y });"
  );

  fs.writeFileSync(file, src);
}

NODE
