# Asteroid Blaster

A tilt-controlled asteroid-shooting frenzy for AsteroidOS smartwatches! Survive waves of tumbling rocks, rack up points, and dodge collisions with a mix of skill and luck. v1.1 brings smoother physics, cleaner visuals, and a touch of retro debug flair.

## Features
- **Tilt to Aim**: Use your watch’s accelerometer to rotate your ship—intuitive and immersive.
- **Autofire**: Shots fire every 150ms—focus on dodging and aiming.
- **Asteroid Physics**: Three sizes (large, mid, small) with mass-based collisions—big ones dominate, small ones bounce.
- **Scoring**: Double points inside the perimeter (20/50/100 base per size), +1 shield every 10k.
- **Shields & Afterburner**: Start with 3 shields, boost away from danger (10s cooldown).
- **Pause/Game Over**: Dimmed game content with a 50% black overlay—pause to breathe, lose to retry.
- **Debug Mode**: Toggle FPS display and graph (0-120 FPS) for performance nerds.

## Gameplay
Tilt your watch to aim your ship, firing cyan shots at asteroids. Large (20 pts), mid (50 pts), and small (100 pts) rocks split and explode—score double inside the blue perimeter. Shields absorb hits, and the afterburner (hold lower screen) zips you out of trouble. Clear a wave to level up, but watch out—speed and numbers ramp up! Pause mid-game, retry on game over.

## Changelog
### v1.1 (March 26, 2025)
- Mass-weighted asteroid collisions—size impacts pushback.
- 50% black dimming layer for pause/game over.
- Asteroid speeds down 10% (0.27/0.36/0.54).
- Restored `fpsGraph` in debug mode.
- Score particles linger longer (2000ms), smaller `pauseText`.

### v1.0 (Initial Release)
- Core game loop, tilt controls, autofire, shields, afterburner.


Blast off!
