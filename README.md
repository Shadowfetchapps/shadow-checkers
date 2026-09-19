# Shadow Checkers

A premium desktop 3D English/American checkers game for Linux, built with Godot 4.7 and a presentation-independent rules engine.

Sibling to [Shadow Chess 3D](../ShadowChess3D) — same visual family, not a fork.

## Run

**Exported binary**

```bash
~/src/ShadowCheckers/export/linux/shadow-checkers.x86_64
# or
~/.local/bin/shadow-checkers
```

**From Godot**

```bash
godot --path ~/src/ShadowCheckers
```

The editor is installed at `~/.local/opt/godot/Godot_v4.7.2-stable_linux.x86_64` and linked as `~/.local/bin/godot`.

**Desktop launcher** (not pinned): `~/.local/share/applications/shadow-checkers.desktop`

## Tests

```bash
~/src/ShadowCheckers/tools/run_tests.sh
```

## Export for Linux

Export templates for 4.7.2 must live in `~/.local/share/godot/export_templates/4.7.2.stable/`.

```bash
~/src/ShadowCheckers/tools/export_linux.sh
# or
godot --headless --path ~/src/ShadowCheckers --export-release Linux ~/src/ShadowCheckers/export/linux/shadow-checkers.x86_64
```

Install the wrapper, icon, and applications-folder entry:

```bash
~/src/ShadowCheckers/tools/install_linux.sh
```

## Rules

English/American draughts:

- 8×8 board, play on dark squares only
- Black moves first
- Men move diagonally forward one square
- Kings move one square diagonally in any direction (no flying kings)
- Jumps are mandatory; multi-jumps continue with the same piece
- Promoting a man to king ends the turn
- Win by capturing all opposing pieces or leaving the opponent with no legal moves

## Controls

- **LMB** — select and move
- **RMB** — orbit
- **Wheel** — zoom
- **MMB** — pan
- **H** — reset camera
- **F** — flip board
- **Z** — undo last turn
- **Esc** — pause

Saves and settings use XDG paths:

- `~/.config/shadow-checkers/settings.json`
- `~/.local/share/shadow-checkers/saves/`
