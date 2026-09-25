# RPG engine patches

This directory is reserved for modifications applied on top of the pinned DD-Channel/ra2-web source tree.

The initial Docker migration intentionally starts the upstream client without invasive code changes so we can first verify that:

1. the upstream project builds in Docker,
2. it opens on http://localhost:8080,
3. the user's original Red Alert 2 files are visible inside the container,
4. the upstream client can initialize correctly.

After that baseline is confirmed, RPG-specific modifications will be added here in small, reviewable steps.

Planned first patch:
- expose/load local original-game assets automatically
- add a dedicated RPG boot mode
- replace RTS selection with single-character click-to-move controls
