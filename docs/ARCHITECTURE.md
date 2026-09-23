# Architecture

Shadow Checkers is a Godot 4.7 (Forward+) project in typed GDScript. The rules, notation, Shadow engine, and puzzles are pure `RefCounted` classes with no scene-tree access, so headless tests drive them directly and the AI runs on worker threads. It shares its UI kit, camera, and rendering approach with Shadow Chess 3D.

```
scripts/
  checkers/   CheckersTypes, CheckersMove, CheckersEngine, CheckersRules (variants),
              CheckersPdn (PDN import/export), CheckersPuzzles, fen.gd (legacy FEN)
  ai/         CheckersAI (levels, SearchJob, search), CheckersBook (English openings)
  game/       GameController (the live game), GameSession (menu → game hand-off)
  board/      BoardView (tiles, frame, numbers, marks, trays), ClubBuilder (room), GameClockProp
  pieces/     PieceMeshBuilder (OBJ discs + lathed fallback), PieceView (motion, crowning)
  gfx/        MaterialLibrary (themes, marks, style-aware side names), WorldLook
  camera/     OrbitCamera
  audio/      AudioManager
  save/       SettingsStore, ProfileStore, SaveManager
  ui/         ThemeFactory, IconLibrary, widgets/, screens and dialogs
data/         opening_book_english.txt, puzzles.json
tests/        test_runner.gd (rules, variants, notation, AI, puzzles), test_ai_worker.gd,
              scene_runner.tscn (presentation)
tools/        run_tests.sh, export_linux.sh, install_linux.sh, capture_screenshots.sh,
              check_scripts.gd, assetgen/ (Blender models, audio, textures)
```

## Rules engine

A move is one **complete turn**: `CheckersMove.path` lists every square visited (`[from, landing1, landing2, …]`) and `captures` lists the jumped squares in order. `CheckersEngine.generate_legal_moves()` returns full sequences and applies each variant's constraints:

| Variant | First move | Men capture backwards | Kings | Capture choice | Crowning |
|---|---|---|---|---|---|
| `english` | Black | no | one step | any sequence | ends the move |
| `russian` | White | yes | flying | any sequence | mid-capture, continues as king |
| `brazilian` | White | yes | flying | must take the most pieces | only if the move ends on the far row |

All variants use the Turkish-strike rule (captured pieces stay until the move ends and can't be jumped twice) and threefold repetition. Move-rule draws are 80 plies (English), 30 (Russian), and 50 (Brazilian) without a capture or man move.

For click-by-click input the engine exposes `candidates_for_prefix(prefix)` and `next_landings(prefix)`: the UI never needs to know capture rules, it just follows legal prefixes. `to_fen()`/`from_fen()` use standard PDN FEN (`W:W21,22,K5:B1,2`) and still read 1.x FEN strings. Notation is numeric (`11-15`, `22x15x6`) for English and algebraic (`c3-d4`, `c3:e5:g7`) for the flying-king variants.

## The live game (`GameController`)

- **Input**: pick against square bodies (layer 1) and disc bodies (layer 2). Selecting a disc shows its next landings; each click (or drag-drop) extends the path. When the path is a complete legal move it is played; if only one continuation remains and *auto-complete* is on, the rest plays itself. Partial hops animate immediately; jumped discs ghost in place until the move is committed. Esc or X takes back an unfinished sequence.
- **Guidance**: when it's a human's turn, discs that can move get an emerald ring; if a capture is compulsory the status pill says so, and clicking a disc that can't move explains why.
- **Animation**: each hop is an eased arc; captured discs fly to the felt trays (immediately in English, at the end of the move under Turkish-strike rules); crowning drops a second disc onto the man with a chime.
- **Threads**: Shadow's move, evaluation, hints, and puzzle checks run as `WorkerThreadPool` tasks on data-only jobs (`CheckersAI.SearchJob`, `FuncJob`). Every task is awaited; undo, restart, and scene exit cancel first.
- **Side names**: the classic red-and-black set calls the light side *Red*; `label_text()` rewrites engine messages accordingly.
- **Autosave** after every turn to `saves/autosave.json`; *Continue* resumes unfinished games.

## Save format (v2)

```json
{
  "format": "shadow-checkers-save", "version": 2, "variant": "russian",
  "mode": "ai", "ai_side": 1, "ai_level": "club",
  "start_fen": "", "moves_uci": ["c3d4", "f6e5", "d4f6"],
  "result": "*", "finished": false,
  "clock": {"base": 600, "increment": 0, "white": 598.0, "black": 600.0, "enabled": true},
  "pdn": "[Event \"Shadow Checkers\"] …"
}
```

Each `moves_uci` entry is a full turn written as its concatenated path. 1.x saves stored one entry per hop; they are regrouped into turns with `replay_legacy_hops()` on load.

## Rendering and UI

Same structure as Shadow Chess 3D: `MaterialLibrary` mutates shared materials in place for four board themes (Club Room, Red & Black, Slate & Stone, Marble Hall) and four piece sets; tileable PBR textures with per-square quadrant and rotation variation; Blender-built fluted discs; HDR club-room panorama for reflections; quality tiers from Low to Ultra; a HUD-aware orbit camera; frosted-glass modals; rendered disc icons.

## Tests

`./tools/run_tests.sh` runs the rules/variants/notation/AI/puzzle suites (`--script`), the worker-thread test, and the scene-based presentation suite. English perft is checked to depth 8; Russian and Brazilian perft are pinned; puzzle solutions are verified by search.
