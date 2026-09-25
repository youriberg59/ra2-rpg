# Asset pipeline

The game is a 2D isometric renderer. Assets are normal transparent images loaded by the browser.

## Supported image formats

Recommended:

- PNG for production sprites
- WebP for lighter web builds
- SVG for simple placeholders and UI
- spritesheets later for animated characters

## Folders

```text
client/public/assets/
  manifest.json
  characters/
  buildings/
  props/
  loot/
  projectiles/
```

## Adding a character

1. Put the image in `client/public/assets/characters/`.
2. Add an entry to `client/public/assets/manifest.json`.

Example:

```json
"engineer": {
  "src": "/assets/characters/engineer.png",
  "width": 64,
  "height": 96,
  "anchorX": 0.5,
  "anchorY": 0.9
}
```

The anchor defines which point of the sprite touches the world coordinate. For standing characters, `anchorY` should normally be close to the feet.

## Adding a building

Put a transparent isometric image in `assets/buildings/` and declare it:

```json
"power_plant": {
  "src": "/assets/buildings/power-plant.png",
  "width": 220,
  "height": 190,
  "anchorX": 0.5,
  "anchorY": 0.92,
  "footprint": [4, 4]
}
```

Then place it in `content/maps/world.json`:

```json
{
  "id": "power_plant_01",
  "asset": "power_plant",
  "x": 900,
  "y": 500
}
```

## Adding props

Props use the same workflow. Trees, crates, lamps, signs, rocks and wrecks belong in `assets/props/`.

## Adding loot

Declare the image in the `loot` section of the manifest. The current prototype already contains a medkit placeholder. World loot spawning/pickup logic is the next gameplay layer to add.

## Character animation plan

The renderer is prepared to remain fully 2D. The next animation format should use 8 directions:

```text
N
NE
E
SE
S
SW
W
NW
```

Each direction can have sequences for:

- idle
- walk
- shoot
- hit
- death

A production character can therefore be exported as a spritesheet from Blender, Aseprite, Krita, Photoshop or another 2D pipeline.

## Blender workflow while keeping the game 2D

You can still create assets in Blender:

1. build/model the object in 3D,
2. use a fixed isometric camera,
3. render with transparent background,
4. export PNG frames,
5. add the PNG or spritesheet to the manifest.

The game itself remains 2D.

## Map

The first map is:

```text
content/maps/world.json
```

It defines:

- world dimensions
- isometric tile dimensions
- roads
- buildings and props
- enemy spawn positions

The renderer sorts visible objects by `x + y`, which creates the classic isometric depth effect.

## Current tile projection

Default diamond:

```text
64 x 32 px
```

Logical world unit:

```text
32
```

These values can be changed in `content/maps/world.json`.
