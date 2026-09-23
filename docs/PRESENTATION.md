# Presentation

The look is an old club room after hours: a green-shaded banker's lamp over a mahogany table with a green leather top, panelled walls, a fire glowing at the side, and brass everywhere a hand would touch.

## Scene

- **Room** (`ClubBuilder`): oak plank floor with a baize rug, wood-panelled walls with brass rails, two tall bookcases filled with hundreds of instanced spines, a fireplace, brass wall sconces, and a pendant lamp above the table. The room is open above so the camera can rise freely.
- **Table**: mahogany with a green tooled-leather inset and brass banding.
- **Board** (`BoardView`): a bullnose frame with a brass inlay and corner rosettes, 64 bevelled tiles, coordinates that turn to face the player, optional engraved square numbers 1–32 for PDN, and felt capture trays with brass rails on both sides.
- **Clock**: the same working tournament clock as Shadow Chess 3D.
- **Discs**: Blender-built pieces with a reeded rim, concentric grooves, and an inlaid ring; kings are two stacked discs with a gold coronet.

## Themes

| Board | Squares | Frame |
|---|---|---|
| Club Room | maple / mahogany | mahogany, brass inlay |
| Red & Black | red / black lacquer | black lacquer, gold inlay |
| Slate & Stone | limestone / cleft slate | smoked oak, silver inlay |
| Marble Hall | Carrara / Nero Marquina | verde marble, gold inlay |

Piece sets: Cream & Mahogany, Red & Black (the light side is called *Red* throughout the interface), Ivory & Ebony, and Marble. Themes switch live.

## Light and quality

A warm pendant key with soft shadows, fire glow from the side, a rim light, a cool window fill, and an HDR panorama of the room for ambient light and reflections. AgX tone mapping and the same Low → Ultra tiers as Shadow Chess 3D (shadows, bloom, fog; SSAO, SSR, reflection probe, depth of field; SSIL, volumetric light, TAA).

## Motion and guidance

- Discs hop on eased arcs, one hop at a time for multi-jumps; captured discs arc into the trays; crowning drops a second disc on top with a chime.
- While you enter a multi-jump, each hop animates immediately and jumped discs stay ghosted in place until the move is complete.
- Discs that can move get an emerald ring; forced captures are called out in the status pill; the route of the last multi-jump is dotted on the board.
- Legal landings are emerald dots in a dark outline; captures are rings; hints draw an arrow through every landing square.
- **Reduce motion** removes arcs, bobbing, and the menu camera orbit.

## Interface

Green-black lacquer panels with brass accents, Inter typography with tabular figures, original SVG icons, frosted-glass dialogs, and captured-piece counts drawn with icons rendered from the real 3D discs.
