# Ghost Combinator

A Factorio 2.1 mod that outputs circuit signals for all construction ghosts on a surface.

## What It Does

Roboports tell you what items logistics bots are moving, but not what construction bots need to build. This combinator fills that gap by outputting a signal for each ghost entity awaiting construction.

## Usage

1. Research **Ghost Combinator** (requires Logistic System + Production Science)
2. Build a Ghost Combinator anywhere on your base
3. Connect red or green wire to read ghost counts
4. Each ghost type outputs as a signal with its count

The combinator automatically tracks all ghosts on the same surface. Place ghosts via blueprints or by removing existing structures - the signals update in real-time.

## Recipe

- 5x Electronic Circuit
- 5x Advanced Circuit

## Notes

- One combinator covers an entire surface (Nauvis, Vulcanus, platforms, etc.)
- Entities that share a placement item are merged into one signal (rails report as `rail`)
- Signals compress automatically - zero-count entries are cleaned up every 5 seconds
- Ghosts placed before installing the mod are not tracked
- Upgrade requests and tile ghosts (landfill, concrete, platform foundation) are not yet tracked