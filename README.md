# Asteroid Blaster

**Asteroid Blaster** is a fast-paced, vector-style space shooter for wearable devices, built with QtQuick 2.15. Navigate your ship through a field of spinning asteroids, blast them into smaller pieces, and survive as long as you can using tilt controls and rapid-fire shots. Inspired by classic arcade space games, this project brings retro vibes to modern wearables.

## Features

**Vector-Style Asteroids**: Jagged, spiky asteroids with 5-7+ points, generated in three sizes (large, medium, small) within square bounding areas, rotating slowly with random variance.
**Dynamic Gameplay**:
  - Start with 5 large asteroids at level 1, increasing by 1 per level (6 at level 2, etc.), spawned with a 4-second delay each.
  - Asteroids wrap around screen edges, persisting until fully destroyed (large → medium → small).
  - Levels advance only when all asteroid parts are cleared.
**Player Controls**:
  - Tilt-based movement using accelerometer input, with smoothed responsiveness.
  - Autofire shots (1.5 dimsFactor width, 3 dimsFactor height) at 200ms intervals, emitted from the ship's tip.
**Collision Mechanics**:
  - Asteroids collide with each other like billiard balls, deflecting realistically with equal mass physics.
  - Shots break asteroids into smaller pieces (large splits into 2 medium, medium into 2 small, small disappears).
  - Player-asteroid collisions reduce shields (starts at 2, +1 per 10,000 points), ending the game at 0 shields.
**Scoring and Progression**:
  - Points: 100 (large), 50 (medium), 20 (small) per destruction.
  - Shields increase by 1 every 10,000 points.
**UI and Game States**:
  - Displays score, shields, and level during play.
  - Pause mode freezes asteroids and player movement (tap to toggle).
  - Game over screen shows final score, level, high score, high level, and a "Try Again" button, skipping calibration on restart.
**Performance**:
  - Optimized for wearables with debug FPS display and graph (toggleable in pause).
  - Continuous display blanking prevention via Nemo.KeepAlive.


## Controls

Tilt: Rotate the ship using your device’s accelerometer.

Tap: Pause/unpause during gameplay; restart from the game over screen.

