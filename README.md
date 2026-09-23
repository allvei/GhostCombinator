# Ghost Combinator

A Factorio 2.1 mod that outputs circuit signals for construction ghosts in a logistic network or on a whole surface.

## What It Does

Roboports tell you what items logistics bots are moving, but not what construction bots need to build. This combinator fills that gap by outputting a signal for each ghost entity awaiting construction.

## Usage

1. Research **Ghost Combinator** (requires Construction Robotics + Circuit Network)
2. Build a Ghost Combinator inside the supply area (orange) of a roboport in the network you want to monitor
3. Connect red or green wire to read ghost counts
4. Each ghost type outputs as a signal with its count

Open the combinator to choose:

- **Output mode** - Builds (entity ghosts), Tiles (tile ghosts) or Upgrades (upgrade planner requests)
- **Only count ghosts in this logistic network** - on by default. The combinator must stand in a roboport's supply area. Only demand inside the construction area of that roboport's logistic network is counted, and nothing is output anywhere else, so it never requests items no robot can deliver. Personal roboports don't count, and space platforms have no roboports, so use the whole-surface setting there. Turn it off to count the whole surface.

Place ghosts via blueprints or by removing existing structures - the signals update in real-time.

## Recipe

- 5x Electronic Circuit
- 5x Advanced Circuit

## Notes

- Entities that share a placement item are merged into one signal (rails report as `rail`)
- Signals compress automatically - zero-count entries are cleaned up every 5 seconds
- Ghosts left behind by destroyed entities (asteroids, biters) are tracked
- Ghosts placed before installing the mod are picked up by a scan when the mod is added; `/gc-rescan` rebuilds tracking at any time
- Combinators built before version 1.2.0 keep counting the whole surface until you tick the network option
- After roboports are built or removed, network-filtered counts settle within a few seconds
- Foundation tiles destroyed by asteroids raise no game event; run `/gc-rescan` to count their ghosts
