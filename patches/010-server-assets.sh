#!/bin/bash
set -euo pipefail

cd /app

echo "Applying centralized server-assets and English-language patch..."

if [ -f public/config.ini ]; then
  sed -i 's#^defaultLanguage=.*#defaultLanguage=en-US#' public/config.ini
  sed -i 's#^gameResArchiveUrl=.*#gameResArchiveUrl=/__SERVER_RA2_ARCHIVE__#' public/config.ini
fi

node <<'NODE'
const fs = require('fs');

const file = 'src/engine/gameRes/GameRes.ts';
let src = fs.readFileSync(file, 'utf8');

const oldBlock = `      console.log('[GameRes] Calling gameResBoxApi.promptForGameRes');
      const userSelection = await gameResBoxApi.promptForGameRes(
        archiveUrlFallback,
        !!this.appConfig.gameresBaseUrl && !this.modName,
      );
      console.log('[GameRes] User selection from prompt:', userSelection);`;

const newBlock = `      console.log('[GameRes] Resolving game resource source');
      let userSelection: URL | FileSystemFileHandle | FileSystemDirectoryHandle | undefined;

      if (archiveUrlFallback) {
        const assetPort = '8090';
        const archiveUrl = archiveUrlFallback.includes('__SERVER_RA2_ARCHIVE__')
          ? `${window.location.protocol}//${window.location.hostname}:${assetPort}/original-game-pack.zip`
          : archiveUrlFallback;
        userSelection = new URL(archiveUrl, window.location.href);
        console.log('[GameRes] Auto-importing server-hosted RA2 archive:', userSelection.toString());
      } else {
        userSelection = await gameResBoxApi.promptForGameRes(
          archiveUrlFallback,
          !!this.appConfig.gameresBaseUrl && !this.modName,
        );
      }

      console.log('[GameRes] User selection from resource resolver:', userSelection);`;

if (!src.includes(oldBlock)) {
  console.error('Expected GameRes prompt block not found; upstream may have changed.');
  process.exit(1);
}

src = src.replace(oldBlock, newBlock);
fs.writeFileSync(file, src);
NODE
