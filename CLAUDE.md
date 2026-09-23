# Ghost Combinator — Factorio Mod

Building a Factorio mod called **ghost-combinator** (internal name in `mod/info.json`, title
"Ghost Combinator"). It tracks every construction ghost on a surface and outputs one circuit
signal per ghost type, with counts.

- Requirements: @docs/spec.md
- Current activity / task tracking: @docs/todo.md
- Where code belongs: @docs/module_responsibility_matrix.md
- New entity boilerplate: @docs/entity_creation_checklist.md
- flib helper reference: @docs/flib_api_reference.md

**🚨 CRITICAL: Factorio API version 🚨**

`info.json` declares `factorio_version: "2.1"` and depends on `base >= 2.1.0`.
**ALWAYS use 2.0/2.1-era APIs.** Using 1.1 APIs wastes time and gets everyone upset.

The most common 1.1-isms to avoid:

| Wrong (1.1) | Right (2.0+) |
|---|---|
| `global` | `storage` |
| `game.entity_prototypes` / `game.item_prototypes` | `prototypes.entity` / `prototypes.item` |
| `defines.circuit_connector_id` | `defines.wire_connector_id` |
| `entity.get_circuit_network(wire, connector)` | `entity.get_circuit_network(wire_connector_id)` |
| `control_behavior.parameters` on constant combinators | `cb.get_section(n)` / `section.set_slot()` (LuaLogisticSection) |
| Bare signals `{type, name}` | Signals carry `quality` — always set it explicitly |

**Verify every API before using it.** Sources, in order of preference:

1. https://lua-api.factorio.com/latest/ — authoritative. Working URL shapes:
   - `/latest/events.html` (all runtime events on one page)
   - `/latest/classes/LuaEntity.html`, `/latest/classes/LuaTilePrototype.html`, etc.
   - `/latest/defines.html`, `/latest/concepts.html`
   - `/latest/prototypes/TechnologyPrototype.html` (data-stage prototypes)
   - NOTE: per-event pages like `/latest/events/on_built_entity.html` do **not** exist (404).
     Use `events.html` and search within it.
2. https://github.com/wube/factorio-data — vanilla prototype definitions, e.g.
   `core/prototypes/utility-sprites.lua` for GUI sprite names.
3. Context7 "Factorio Lua API", if a Context7 MCP server is connected to the session.

State the doc version you verified against when it matters — the page header shows it
(e.g. "API Version: 2.1.14").

## File Structure

```
CLAUDE.md                                # This file
README.md                                # Player-facing mod description
Makefile                                 # package / localdeploy / lint / ci
.luacheckrc                              # luacheck config
docs/
├── spec.md                              # Requirements specification
├── todo.md                              # Development tracking (index of feature todos)
├── module_responsibility_matrix.md      # Code organization rules — READ BEFORE CODING
├── entity_creation_checklist.md         # Checklist for adding a new entity type
├── flib_api_reference.md                # flib utility reference
├── construction_demand_tracking_todo.md # Feature plan: untracked construction demand
└── issue_fixes_todo.md                  # v1.2.0 plan: GitHub issues #1/#3/#4/#5
mod/
├── info.json                            # Mod metadata (name, version, factorio_version)
├── changelog.txt                        # Factorio-format changelog
├── thumbnail.png                         # Mod portal thumbnail
├── data.lua                             # Data stage entry point
├── data-final-fixes.lua                 # Final-fixes entry — runs after all other mods
├── control.lua                          # Runtime entry — event registration & routing only
├── lib/                                 # Stateless utility libraries (no storage access)
│   ├── entity_lib.lua                   # Entity name / ghost helpers
│   ├── circuit_utils.lua                # Circuit network read/write helpers
│   ├── gui_utils.lua                    # Shared GUI builders (byte-identical across family)
│   ├── signal_utils.lua                 # Pure signal table ops + prototype lookups
│   └── gui/                             # Shared GUI components
│       ├── gui_entity.lua               # Entity GUI utilities (power/status display)
│       └── gui_circuit_inputs.lua       # Signal grid display
├── scripts/                             # Stateful logic (owns `storage`)
│   ├── globals.lua                      # Storage aggregator + shared player GUI state
│   └── ghost_combinator/                # Entity-specific module
│       ├── storage.lua                  # Per-category counters, slots, registrations, mode
│       ├── config.lua                   # Per-instance combinator config (mode, network filter)
│       ├── networks.lua                 # Per-logistic-network buckets + background re-bucket
│       ├── control.lua                  # Event handlers + tick/compaction/resync
│       ├── rescan.lua                   # Full surface rescan (migration + /gc-rescan)
│       └── gui.lua                      # Ghost count GUI + mode selector + network filter
├── locale/
│   └── en/
│       └── ghost-combinator.cfg         # Localization strings
├── prototypes/
│   ├── entity/ghost_combinator.lua      # Entity prototype
│   ├── item/ghost_combinator.lua        # Item prototype
│   ├── recipe/ghost_combinator.lua      # Recipe prototype
│   └── technology/
│       ├── technologies.lua             # Technology definitions (vanilla fallback cost)
│       └── derive_cost.lua              # Recomputes cost from prerequisites (final fixes)
└── graphics/
    └── entities/
        ├── ghost-combinator.png         # Entity sprite (4-way spritesheet)
        └── ghost-combinator-icon.png    # 64x64 item/tech icon
```

Keep this tree in sync when files are added or moved.

## Important Process Rules

1. All implementation files go under `mod/` and follow the File Structure above.
2. Implementation specs, feature specs, and todos go under `docs/`.
3. Make/git/pre-commit hooks and other SDLC infrastructure may live in the root directory.
4. Plan before you code. Write the feature plan to `docs/<feature>_todo.md` and add a line to
   `docs/todo.md` referencing the new file.
5. Before writing ANY code, consult @docs/module_responsibility_matrix.md and use its decision
   tree to place new functions.

## Important Coding Rules

1. Keep code well organized. Each entity type gets its own module directory under
   `mod/scripts/`; shared code goes in `mod/lib/`.
2. Code files (`.lua`/`.java`/`.py`) should not exceed 750–900 lines. Break larger files into
   multiple modules. (Single JSON/XML/CSV data files that can't reasonably be split should live
   as `.json`/`.xml`/`.csv` and be imported as such.)
3. Use in-line documentation heavily (LuaLS `---@param` / `---@return` annotations) and follow
   best practices.
4. Ghost tracking runs on *every* entity built on the map. Handlers on that path must reject
   irrelevant entities on the first line and do no allocation in the common case.

## Build & Test

```
make check        # verify mod structure and info.json
make lint         # luacheck
make ci           # check + lint
make localdeploy  # copy mod/ into the local Factorio mods directory
make package      # build dist/<name>_<version>.zip
```

No Lua toolchain (and no `make`) on the Windows dev machine. For a syntax-only check, parse
every file with `luaparse@0.3.1` via Node from a temp directory (use `npm.cmd`; PowerShell
blocks `npm.ps1`). Validate `mod/changelog.txt` against
https://lua-api.factorio.com/latest/auxiliary/changelog-format.html — one bad line hides the
whole in-game changelog.
