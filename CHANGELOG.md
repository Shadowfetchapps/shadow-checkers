# Changelog

## 2.0.0 — Flagship

### Rules
- Three variants: English/American, Russian, and Brazilian (international rules on 8×8) — flying kings, backward captures by men, the maximum-capture rule, mid-capture crowning, and the Turkish-strike rule where they apply.
- Moves are now whole turns (a full multi-jump is one move), with prefix queries so the interface can take them hop by hop.
- Standard PDN FEN and PDN import/export; numeric notation (`11-15`, `22x15x6`) for English and algebraic for the flying-king variants.
- Move-rule counters reset on captures and man moves, per variant; threefold repetition in all variants.

### Shadow
- New full-sequence search: iterative deepening, PVS, transposition table, killers and history, capture quiescence, draw awareness, variant-tuned evaluation (runaway men, back-rank guard, king values for short and flying kings).
- Six levels from Beginner to Master and an English opening book with three-move-ballot starts.
- At 0.8 s a move, the new Master scored 8.5/9 against the 1.x Master.

### New modes and tools
- 33 tactics **puzzles** in all three variants, each with a unique winning first move proven by search.
- **Analysis board** with evaluation bar and principal variation; **game review**; **hints**; **draw offers**; **rematch** and **swap sides**.
- **Statistics** with an Elo-style rating per variant and level; **Continue** from autosave.
- Time controls with increments; typed moves.

### Look and feel
- Blender-built fluted discs and stacked kings with a gold coronet; bullnose board frame with brass inlay.
- New club room: mahogany table with green leather, panelled walls, bookcases, fireplace, sconces, green-shaded pendant lamp, tournament clock.
- Procedural PBR textures and an HDR room panorama; four board themes and four disc sets that switch live.
- Hop-by-hop multi-jump entry with ghosted captures, crowning animation, capture trays, movable-disc rings, route dots, two-tone marks, hint arrows.
- New interface shared with Shadow Chess 3D: player cards, clickable scoresheet, status pill, frosted dialogs, original icons, overlay settings and help.
- Original synthesised audio on Music/SFX/UI buses.
- Reduce-motion, high-contrast marks, interface scaling, optional square numbers.

### Under the hood
- Versioned settings with 1.x migration and corrupt-file recovery; save format v2 (1.x per-hop saves still load).
- `install_linux.sh` now installs the real binary to `~/.local/bin` (1.x installed a wrapper script) and supports `--uninstall`.
- Test suites grew from 163 to 775 checks.
- Reproducible asset pipeline in `tools/assetgen/`; MIT licence.

## 1.1.0

- Shadow's search moved off the UI thread; table polish.

## 1.0.0

- English/American rules engine with headless tests, 3D board, local and AI play, XDG saves and settings, Linux export.
