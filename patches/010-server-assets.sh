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

// Skip expensive Bink -> WebM conversion from language.mix.
// It is only used for the menu video and can stall for a long time in-browser.
{
  const file = 'src/engine/gameRes/GameResImporter.ts';
  let src = fs.readFileSync(file, 'utf8');

  const oldBlock = `} else if (mixFileNameLower.match(/language\\.mix$/)) {
            onProgress(S.get("ts:import_importing_long", mixFileNameLower));
            await this.importVideo(mixVirtualFile, targetRfsRootDir);
        } else if (mixFileNameLower.match(/ra2\\.mix$/)) {`;

  const newBlock = `} else if (mixFileNameLower.match(/language\\.mix$/)) {
            onProgress('Importing ' + mixFileNameLower + '...');
            console.log('[GameResImporter] Skipping Bink menu-video conversion for language.mix in self-hosted mode.');
        } else if (mixFileNameLower.match(/ra2\\.mix$/)) {`;

  if (!src.includes(oldBlock)) {
    console.error('Expected language.mix import block not found.');
    process.exit(1);
  }

  src = src.replace(oldBlock, newBlock);
  fs.writeFileSync(file, src);
}


// Force English UI strings even when the bundled general.csf is Chinese.
// The upstream en-US JSON is incomplete, so add a small fallback dictionary
// for the main menu keys that are otherwise inherited from the Chinese CSF.
{
  const file = 'src/Application.ts';
  let src = fs.readFileSync(file, 'utf8');

  const marker = "    // Final check and log sample strings";
  const inject = `    const selfHostedEnglishOverrides: Record<string, string> = {
      'GUI:MainMenu': 'Main Menu',
      'GUI:Options': 'Options',
      'GUI:Skirmish': 'Skirmish',
      'GUI:Fullscreen': 'Fullscreen',
      'TS:InfoAndCredits': 'Info & Credits',
      'GUI:Mods': 'Mods',
      'GUI:OK': 'OK',
      'GUI:OKAY': 'OK',
      'TS:TestEntry': 'Developer Tools',
      'STT:TestEntry': 'Open developer and storage tools',
    };
    this.strings.fromJson(selfHostedEnglishOverrides);

`;

  if (src.includes(marker) && !src.includes("selfHostedEnglishOverrides")) {
    src = src.replace(marker, inject + marker);
  }

  fs.writeFileSync(file, src);
}

// Replace Chinese strings hard-coded in the upstream home screen.
{
  const file = 'src/gui/screen/mainMenu/main/HomeScreen.ts';
  let src = fs.readFileSync(file, 'utf8');

  src = src
    .replace("label: '遭遇战'", "label: this.strings.get('GUI:Skirmish') || 'Skirmish'")
    .replace("tooltip: '与AI进行单人遭遇战'", "tooltip: 'Single-player skirmish against AI'")
    .replace("console.log('[HomeScreen] 遭遇战 clicked');", "console.log('[HomeScreen] Skirmish clicked');")
    .replace("label: '底层测试入口'", "label: this.strings.get('TS:TestEntry') || 'Developer Tools'")
    .replace("tooltip: '进入底层文件系统与测试工具'", "tooltip: this.strings.get('STT:TestEntry') || 'Open developer and storage tools'")
    .replace("'无法退出全屏模式'", "'Unable to exit fullscreen mode'")
    .replace("'无法进入全屏模式\\n\\n请检查浏览器权限设置'", "'Unable to enter fullscreen mode\\n\\nPlease check your browser permissions'");

  fs.writeFileSync(file, src);
}

NODE
