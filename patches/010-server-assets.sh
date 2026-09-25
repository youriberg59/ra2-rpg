#!/bin/bash
set -euo pipefail

cd /app

echo "Applying centralized server-assets and English-language patch..."

if [ -f public/config.ini ]; then
  sed -i 's#^defaultLanguage=.*#defaultLanguage=en-US#' public/config.ini
  sed -i 's#^gameResArchiveUrl=.*#gameResArchiveUrl=/__SERVER_RA2_SOURCE__#' public/config.ini
fi

node <<'NODE'
const fs = require('fs');

// Force the UI locale to English after CSF loading.
{
  const file = 'src/Application.ts';
  let src = fs.readFileSync(file, 'utf8');
  const marker = "    // --- Step 2: Load and merge JSON locale file ---";
  if (src.includes(marker) && !src.includes("this.currentLocale = 'en-US';\n\n    // --- Step 2")) {
    src = src.replace(marker, "    this.currentLocale = 'en-US';\n\n" + marker);
  }
  fs.writeFileSync(file, src);
}

// Auto-resolve the server resource source instead of prompting the browser.
{
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
        const resourceUrl = archiveUrlFallback.includes('__SERVER_RA2_SOURCE__')
          ? window.location.protocol + '//' + window.location.hostname + ':' + assetPort + '/__server_ra2__'
          : archiveUrlFallback;
        userSelection = new URL(resourceUrl, window.location.href);
        console.log('[GameRes] Auto-importing server-hosted RA2 resources:', userSelection.toString());
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
}

// Teach the importer to fetch the essential MIX files directly from our server,
// bypassing the huge ZIP + 7z-wasm path.
{
  const file = 'src/engine/gameRes/GameResImporter.ts';
  let src = fs.readFileSync(file, 'utf8');

  const marker = "        // Handle archive files (URL, File, or FileSystemFileHandle)\n";
  if (!src.includes(marker)) {
    console.error('Expected GameResImporter marker not found.');
    process.exit(1);
  }

  const directImport = `        // Special self-hosted source: fetch the required MIX files directly.
        if (source instanceof URL && source.pathname.endsWith('/__server_ra2__')) {
            const base = new URL('/', source);
            const directMixes = [
                { name: 'ra2.mix', optional: false },
                { name: 'language.mix', optional: false },
                { name: 'multi.mix', optional: false },
                { name: 'theme.mix', optional: true },
            ];

            for (const entry of directMixes) {
                const fileUrl = new URL('files/' + entry.name, base).toString();
                onProgress('Downloading ' + entry.name + '...');

                try {
                    const buffer = await new HttpRequest().fetchBinary(fileUrl, undefined, {
                        onProgress: (_delta, _total) => {},
                    });
                    const vf = VirtualFile.fromBytes(new Uint8Array(buffer), entry.name);
                    onProgress('Importing ' + entry.name + '...');
                    await this.importMixArchive(vf, targetRfsRootDir, onProgress, S);
                } catch (e: any) {
                    if (entry.optional && (e instanceof DownloadError || e?.statusCode === 404)) {
                        console.warn('Optional server resource missing:', entry.name);
                        continue;
                    }
                    console.error('Direct server resource import failed for', entry.name, e);
                    throw e;
                }
            }

            onProgress('Game assets successfully imported.');
            return;
        }

`;

  src = src.replace(marker, directImport + marker);
  fs.writeFileSync(file, src);
}
NODE
