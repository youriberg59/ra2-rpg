# Chrono Divide integration notes

## Engine choice

The project uses Chrono Divide as the Red Alert 2-compatible browser engine and the official Chrono Divide Mod SDK as the supported modding surface.

## What the Mod SDK supports

Chrono Divide loads mod content from its browser virtual file system. A mod directory can contain RA2-compatible files such as:

- INI files
- MIX archives
- MMX archives
- CSF language files
- MPR/MAP maps
- PKT map listings

The required Chrono Divide manifest for a supported mod is `modcd.ini`.

## Loading priority

Standalone INI/map files in a mod folder have high priority. MIX archives use RA2-compatible names such as `expand##.mix`, `ecache##.mix`, and `elocal##.mix`.

This makes incremental development easy: start with standalone INI files, then package art/audio assets into MIX archives later.

## Development loop

1. Edit files under `mod/`.
2. Package them with Docker if desired, or copy them directly.
3. In Chrono Divide open Options -> Storage.
4. Put the files in `mods/ra2-rpg`.
5. Reload the client.
6. Load the mod.
7. Check browser dev tools for INI warnings/errors.

## Original RA2 assets

Chrono Divide uses original Red Alert 2 MIX archives supplied by the user.

Do not commit those archives to this repository.

## RPG scope

The Mod SDK is primarily an RA2 rules/art/map compatibility layer. The first RPG experiments should therefore focus on mechanics expressible with supported engine features:

- one or a few controllable hero units
- custom hero stats
- custom weapons
- map-driven objectives
- civilian/NPC-like units
- supported triggers/actions
- custom maps
- custom SHP/VXL/buildings

Persistent accounts, free-form dialogue systems, inventory databases and similar systems are outside ordinary RA2 INI modding and should be treated as separate engineering work rather than assumed to exist in the Mod SDK.

## Official documentation

- https://github.com/chronodivide/mod-sdk
- https://github.com/chronodivide/mod-sdk/blob/master/RULES.md
- https://github.com/chronodivide/mod-sdk/blob/master/ART.md
- https://github.com/chronodivide/mod-sdk/blob/master/MAPS.md
