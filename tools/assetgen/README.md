
## Audio

`gen_audio.py` synthesises every sound effect and the music loop from scratch
(numpy/scipy DSP only -- no samples, no network) and writes Ogg Vorbis files
(`libvorbis -q:a 5`, 44.1 kHz) to `assets/audio/`.

```sh
python3 tools/assetgen/gen_audio.py                  # render all + QC table (~30 s)
python3 tools/assetgen/gen_audio.py --only place_1 crown
python3 tools/assetgen/gen_audio.py --analyze-only   # QC existing files only
python3 tools/assetgen/gen_audio.py --plots /tmp/sfx # + waveform/spectrogram PNGs
```

Needs Python 3 + numpy + scipy and `ffmpeg` built with libvorbis (matplotlib
only for `--plots`). Output is **deterministic**: each sound has its own RNG
seeded with `crc32("checkers:<name>")` and ffmpeg runs bit-exact, so a re-run
produces byte-identical files. The DSP core and the QC code are identical to
Shadow Chess 3D's `gen_audio.py`. Only the sound-design section differs.

**Techniques.** Discs use modal synthesis: a hard (unfelted) raised-cosine contact
pulse, doubled 1-2.5 ms apart as the disc lands nearly flat (flam), excites
thick-disc modes (~1.5-8 kHz, T60 = 2.2 / (loss x f)), a dense set of
mahogany-board plate modes and a 110-135 Hz body thump. Captures add a
disc-on-disc knock and a few accelerating "settle" taps. Cues use additive
vibraphone (partials 1 : 4 : 9.8 with motor tremolo) and a brass handbell
(tuned twelfth). Music uses a 1:1-FM electric piano with a decaying index,
tine ping and pickup saturation, a plucked-string upright bass, and brushes
made from periodic band-passed noise. Everything passes through a warm synthetic
club room.

**Levels.** SFX are normalised to a target max-momentary loudness with a
true-peak ceiling; the place family anchors the set at -3 dBFS peak. Variants
in a family are loudness-matched (spread < 0.5 LU). UI sounds sit 9-19 LU below
placements. Every file is checked after encoding: true peak <= -1 dBTP. The
music loop is -20 LUFS integrated.

**Integration notes.**
- `music_club.ogg` is a seamless loop of exactly 4 838 400 samples (109.7 s,
  32 bars at 70 BPM, a 16-bar form played twice). It is rendered circularly,
  so loop the **whole file** (`AudioStreamOggVorbis.loop = true`,
  `loop_offset = 0`) and fade it in.
- SFX start with 4 ms of digital silence (this keeps Vorbis pre-echo off sample
  0) and end with 12 ms of silence.
- `crown` is the stack-and-chime only and is meant to follow the move sound.
  `multi_capture` is a complete three-hop sequence.
- SFX are mono. `crown`, `game_start`, `hint`, `victory`, `defeat`, `draw` and
  the music are stereo.

| file | design |
|---|---|
| place_1..4 | thick lacquered hardwood disc on mahogany: bright clack with strong board body and thump. Flam, no flam, or a settle bounce per variant |
| slide | short felt slide: dark swept friction noise with stick-slip grain and a soft stop |
| capture_1..3 | firm landing, then the captured disc is knocked (disc-on-disc) and rocks to rest (3-4 accelerating taps) |
| multi_capture | three hops at 0, 150 and 300 ms, each followed by a disc-on-disc tick, then a settle |
| crown | disc clacks onto disc (the lower one taps the board) plus a small F6 handbell and a soft F5 vibraphone |
| illegal | muted low double thud (disc put back) |
| select | tiny scuff and a light disc tap |
| ui_click / ui_hover | warm damped modal ticks with a small wooden body; hover is almost subliminal |
| ui_open / ui_close | air swell up (with a faint brass glint) or down, with a soft tick |
| game_start | vibraphone F3 and C4 fifth with a faint handbell F5 |
| clock_tick | brass chess-clock escapement with a wooden case |
| clock_warning | two soft, dry vibraphone pings on A5 with a tick |
| hint | vibraphone C5 then G5 |
| victory | plagal cadence Bbmaj9 to F6/9 on vibraphone, with electric-piano pad and handbell |
| defeat | electric piano Gm9 settling into Dm9 with a soft vibraphone A4. Gentle, not sad |
| draw | vibraphone Fsus4 resolving to an open fifth (neutral) |
| music_club | slow swing ballad in F: ii-V-I changes with extensions (Fmaj9, Dm9, Gm9, C13, Bbm6, D7b9 ...), rootless-voiced electric-piano comping with suitcase auto-pan, two-feel upright bass, brushed swirl with taps on 2 and 4, fills in chorus 1 and a soft melody in chorus 2, warm 1.4 s room |

## Models

`build_models.py` generates every 3D model in Blender from code (no external
assets, no network) and writes Wavefront OBJ + MTL files to `assets/models/`.
The same file lives in Shadow Chess 3D; keep the two copies identical. The
script detects which set to build from `project.godot` (`--game` overrides).

```sh
blender -b --factory-startup --python tools/assetgen/build_models.py                 # build + validation table (~2 s)
blender -b --factory-startup --python tools/assetgen/build_models.py -- --only king
blender -b --factory-startup --python tools/assetgen/build_models.py -- --preview /tmp/models   # + EEVEE contact sheets
```

Needs Blender 5.2+ (tested with 5.2.1). Output is **deterministic**: a re-run
writes byte-identical files.

**Conventions (as stored in the OBJ, i.e. Godot space).**
- 1.0 = one board square, +Y up.
- Pieces: origin at the centre of the base, with the bottom at y = 0.
- Every piece has `usemtl body` first, then `usemtl trim` (gold). So surface
  0 = body and surface 1 = trim. Tiles and the base slab are body only.
- Smooth normals are split at crisp edges and face-area weighted. UVs are
  included.
- Faces are triangles and planar quads only.
- The king's crown emblem reads upright when seen from the +Z side of the
  board: its top points to -Z.
- The `.mtl` colours are placeholders; the game overrides them.

| file | tris (trim) | size | notes |
|---|---|---|---|
| man.obj | 6 720 (960) | 0.76 dia x 0.15 | 60 reeds on the rim, rounded edges, 2 shallow grooves and a recessed centre on top, inlaid gold ring (1.5 mm proud) |
| king.obj | 8 344 (1 544) | 0.76 dia x 0.30 (0.316 with emblem) | two stacked men as one lathe (top disc 0.97x wide, V seam), gold ring and a raised 5-point crown emblem (0.30 wide) in the recess |
| square_tile.obj | 28 | 1.0 x 1.0 x 0.07 | top at y = 0.07, 0.01 rounded top edge |
| board_frame.obj | 8 072 (7 712) | 9.2 x 9.2, y -0.12..0.10 | bold bullnose profile (unlike the chess ogee), 8.0 x 8.0 opening, gold inlay stripe and 4 rosettes |
| board_base.obj | 12 | 8.0 x 8.0 x 0.10 | slab under the squares, top at y = 0 |

**Techniques.**
- Discs are lathed with three ring resolutions:
  - 240 segments on the reeded rim (4 samples per reed)
  - 120 on the top rounding and the top face
  - 80 underneath and on the seam
- The reeds run out on the top rounding through a half-depth ring.
- The crown emblem is an outline extruded with a rounded bevel. Jewels are
  small spheres.
- Gold parts are separate closed shells embedded in the body and never
  coplanar with it.
- Every run prints a validation table: usemtl order, non-manifold edges,
  normal orientation, flipped faces, normals/UVs.

## Textures

`gen_textures.py` generates every PBR texture set and the HDR environment
panorama procedurally (numpy/scipy/Pillow only -- no photos, no network) and
writes them to `assets/textures/`. The same file lives in both Shadow Chess 3D
and Shadow Checkers; keep the two copies identical. The game is detected from
`project.godot` (`--game chess|checkers` overrides).

```sh
python3 tools/assetgen/gen_textures.py                      # everything (~1 min, 8 processes)
python3 tools/assetgen/gen_textures.py --only sq_maple,env  # a subset ('env' = the HDR)
python3 tools/assetgen/gen_textures.py --preview-dir /tmp/texqc   # + QC preview sheets
python3 tools/assetgen/gen_textures.py --selftest           # periodicity + HDR round-trip tests
```

Output is **deterministic** (every material has its own RNG seeded from
`crc32(name)`; re-runs are byte-identical) and **seamlessly tileable**: all
noise is periodic spectral noise (integer frequencies per tile), periodic
Worley noise or analytic patterns with integer periods, sampled through
periodic domain warps. `--selftest` checks that every primitive gives the same
value one whole tile away. Every run prints a table with file sizes, mean
albedo, roughness range and a seam check (`seam` = difference of the
wrap-around pixel pair / mean interior neighbour difference, ~1 = seamless;
`rank` = share of interior neighbour pairs at least as different -- a real
seam would be the worst pair, 0%; values of 2-3 with rank > 0 are texture
content, e.g. a vein or ring line running along the tile edge).

**Per material `<name>`:**
- `<name>_albedo.jpg` -- sRGB base colour, JPEG q92. Linear albedo is kept
  in a plausible range (darkest dyes/woods ~0.015-0.02 linear, whites <= ~0.8).
- `<name>_normal.png` -- tangent-space normal, **OpenGL convention (green =
  +Y up)**, which is what Godot expects. Baked from a height field with the
  intended strength, so start with `normal_scale = 1.0`.
- `<name>_rough.jpg` -- greyscale roughness (white = rough). Use
  `roughness_texture_channel = GRAYSCALE` (or RED) with `roughness = 1.0`.
- 1024^2 unless noted, piece finishes 512^2, floors and rug 2048^2.
- Everything is `metallic = 0` except `brass_brushed` (`metallic = 1`, the
  albedo is the brass F0 colour).
- Wood grain always runs along **U** (texture x). Board squares are designed
  so one square shows the whole tile (UV 0..1); random offsets and 180-degree
  flips are safe. 90-degree rotations turn the grain across the square.
- Import settings: for 3D use make sure the textures import as *VRAM
  Compressed* with *mipmaps* on, and the `_normal` maps with
  `compress/normal_map = Enable` (Godot's detect-3D usually does this the
  first time a texture is used on a 3D material).

**Techniques.** Wood: growth-ring contour `rings*y + warp(x,y)` with a large,
x-elongated domain warp (gives straight grain that occasionally forms flat-sawn
cathedral arches), ring-width jitter, per-ring darkness, asymmetric
earlywood/latewood profile anti-aliased by the ring gradient; thin grain lines
are zero sets of x-elongated noise; pores are elongated Worley cells (dense in
earlywood for ring-porous oak), medullary ray flecks, mineral streaks, ribbon
figure (mahogany). Fibres use a coordinate that only loosely follows the ring
warp so nothing stretches where arches fold. Burl: three-level domain warp +
clustered Worley "eyes" with rings wrapped around them. Marble veins: zero set
of a low-frequency, strongly anisotropic field pushed through a fractal domain
warp (long, jagged, branching veins without little closed loops), plus
secondary veins near the primaries, warped Voronoi crack webs and cloudy
ground. Floors: exact herringbone lattice at 45 degrees / staggered courses;
every plank samples a different region, flip and tint of a large periodic
wood field; bevels and gaps are in the height/roughness. Damask: symmetric
ornament (pomegranate, palmette crown, acanthus scrolls, berries) drawn from
Bezier/spiral polygons on a half-drop lattice, satin (weft) vs matte (warp)
weave in roughness/normal. HDR: a small analytic room renderer (box room,
point/area lights with lobes, emissive lamps/windows) written as
Radiance RGBE with per-channel RLE and verified by reading it back.

**Shadow Checkers material notes** (roughness min / mean / max as generated;
"tile" = suggested world size of one 0..1 UV repeat):

| material | use | roughness | notes |
|---|---|---|---|
| `sq_maple` | club light square: warm hard maple, satin | 0.26 / 0.38 / 0.49 | one square = one tile |
| `sq_mahogany` | club dark square: reddish-brown mahogany with ribbon figure | 0.15 / 0.28 / 0.54 | |
| `frame_mahogany` | club frame: darker, calmer mahogany | 0.15 / 0.28 / 0.55 | tile ~0.3 m, U along the rail |
| `sq_lacquer_red` | classic red square: deep red lacquer with fine crackle | 0.04 / 0.10 / 0.36 | clearcoat 0.5-1 optional |
| `sq_lacquer_black` | classic black square: black lacquer, faint crackle, polish swirls | 0.04 / 0.09 / 0.23 | |
| `frame_lacquer_black` | classic frame: black lacquer, rub marks along U | 0.05 / 0.08 / 0.14 | |
| `sq_stone_cream` | slate theme light square: cream limestone, shell fragments, pores, honed | 0.44 / 0.58 / 0.87 | |
| `sq_slate` | slate theme dark square: riven blue-grey slate, flaky layer steps | 0.51 / 0.71 / 0.93 | normal_scale 0.7-1 |
| `frame_oak_smoked` | slate theme frame: fumed oak, open pores, ray flecks | 0.34 / 0.53 / 0.80 | |
| `sq_marble_white`, `sq_marble_black`, `frame_marble_green` | marble theme (same generator/seed as Shadow Chess 3D) | 0.02 / 0.07 / 0.26 | |
| `table_leather_green` | green desk-leather table inlay, fine grain + creases | 0.35 / 0.50 / 0.74 | tile ~0.3 m |
| `floor_plank_oak` (2048) | warm oak strip floor, 12 courses, staggered joints | 0.31 / 0.46 / 0.94 | tile ~2 m (planks ~17 cm wide) |
| `wall_panel_wood` | raised-panel mahogany wainscot (stiles full height, rails between) | 0.25 / 0.37 / 0.70 | one tile = one panel ~0.6 m; tile U for more panels, one V repeat for the wainscot height |
| `felt_green` | green baize | 0.90 / 0.91 / 0.94 | tile ~0.1-0.2 m |
| `brass_brushed` | brass fittings, lamp (metallic 1) | 0.15 / 0.31 / 0.49 | brushing along U |
| `piece_cream` | cream resin / bone pieces | 0.26 / 0.27 / 0.37 | triplanar, tile ~6 cm (`uv1_scale` ~16) |
| `piece_mahogany_red` | red-brown polished wood pieces | 0.10 / 0.23 / 0.49 | triplanar |
| `piece_ebony`, `piece_ivory` | ebony / ivory pieces | 0.06-0.22 / 0.22-0.27 | triplanar |

**`env/club.hdr`** -- 2048x1024 equirectangular Radiance HDR (RLE RGBE),
warm club room: mahogany-panelled walls with warm bounce and a dark green
frieze, coffered ceiling, a green-glass banker's lamp straight overhead (bulb
~45, reflector ~12, glowing green rim), a fireplace with an orange glow on -X,
a dim cool window with green curtains on +X, two warm sconces on +Z, oak
floor and a lamp-lit green baize table just below the viewpoint. Solid-angle
mean luminance ~0.11 (a little brighter than the chess salon), peak ~57.
Mapping follows Godot 4's panorama lookup (u = atan2(x, -z)/2pi,
v = acos(y)/pi): image edges face -Z (Godot's forward), centre +Z, u = 0.25 is
+X. Use via `PanoramaSkyMaterial.panorama`, ambient + reflections from Sky,
`energy_multiplier = 1` to start; rotate with `Environment.sky_rotation.y`.
