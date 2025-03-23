# Asteroid Blaster

**Asteroid Blaster** is a thrilling QML-based arcade game inspired by classics like *Asteroids*. Pilot your spaceship, blast asteroids, and rack up points in a minimalist yet addictive survival challenge. Built with Qt Quick, it’s lightweight, fun, and now polished for v1.0!

## Features

- **Core Gameplay**:
  - Control a spaceship with smooth tilt-based or manual input (calibration included).
  - Fire auto-shots (150ms interval) to destroy asteroids of three sizes: large (20 points), mid (50 points), small (100 points).
  - Survive with 3 shields—lose them all, and it’s game over!

- **Score Perimeter**:
  - A `Dims.l(55)` centered circle with a `#0860C4` 1px outline and `#010A13` fill.
  - Double points for asteroids destroyed inside (e.g., 40, 100, 200), shown in cyan (`#00FFFF`); outside scores in `#67AAF9`.
  - Inner hits flash the outline to white (`#FFFFFF`) and fill to `#074588` for 100ms, fading back over 1s.

- **Progressive Difficulty**:
  - Asteroid spawn interval decreases from 3000ms (level 1) to 500ms (level 20+), with instant first spawns.
  - Fixed speeds (large: 0.3, mid: 0.4, small: 0.6) ensure consistent movement, with difficulty tied to quantity (5 at level 1, 6 at level 2, etc.).

- **Visuals & Effects**:
  - Larger, faster-spinning asteroids (large: `Dims.l(20)`, rotation multiplier: 800ms).
  - Enhanced explosions: ~33% bigger area, grey (`#D3D3D3`) for shots, red (`#DD1155`) for shield hits.
  - Clean UI with updated colors (e.g., `#F9DC5C` level text), sizes, and tighter layouts.

- **Persistence**:
  - Highscore saves instantly on game-over, persisting even if the app closes before restart.

Blast those asteroids and enjoy!  
