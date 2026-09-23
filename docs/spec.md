# Ghost Combinator — Specification

Mod internal name: `ghost-combinator` · Target: Factorio 2.1 (`base >= 2.1.0`, `flib >= 0.17.2`)

## Vision Statement

Roboport logistics signals report *items in the logistics network* but say nothing about
*construction demand*. The Ghost Combinator closes that gap: it keeps a running count of every
construction ghost on its surface and emits one signal per ghost type, so players can automate
against what still needs building.

## Core Components

### 1. Technology — "Ghost Combinator"

| Field | Value |
|---|---|
| Name | `ghost-combinator` |
| Prerequisites | `construction-robotics`, `circuit-network` |
| Science packs | automation, logistic, chemical (1 each per cycle) |
| Cost | 100 cycles at 30s each |
| Unlocks | `ghost-combinator` recipe |
| Icon | `graphics/entities/ghost-combinator-icon.png` (64x64) |

**Cost derivation:** the prerequisites are the two things that actually make the mod meaningful —
construction bots (which is what creates ghosts) and the circuit network (which is how the output
is read). `logistic-system` is deliberately avoided: in vanilla it already requires
`utility-science-pack` (its prerequisites are `utility-science-pack` and `logistic-robotics`), and
overhaul mods — Pyanodons especially — push it later still, which stranded this mod in the very
late game. The research cost is
the union of the two prerequisites' science pack types, each at the higher of the two amounts,
with `count` and `time` likewise the higher of the two — verified against Factorio 2.1 base
(`data/base/prototypes/technology.lua`): `construction-robotics` = 100 x 30s with
automation/logistic/chemical, `circuit-network` = 100 x 15s with automation/logistic.

Those literals in `prototypes/technology/technologies.lua` are only the vanilla fallback.
`prototypes/technology/derive_cost.lua` re-applies the same rule in **data-final-fixes**, reading
the prerequisites' final `unit` after every other mod has re-costed them, so an overhaul that
makes `construction-robotics` cost 800 cycles of five pack types drags this technology along with
it. On base + Space Age + Quality neither prerequisite is modified, so the pass is a no-op there.

The prerequisite *list* is read as it stands at final fixes rather than from a hardcoded copy, so
a mod that re-parents this technology is honoured rather than overwritten. The pass also drops any
prerequisite naming a technology that no longer exists (a dangling prerequisite is a hard load
error), omits any science pack that is not a `tool` prototype, and leaves the technology alone
entirely if a mod converted it to `research_trigger`. Every failure path leaves the shipped
literals in place.

Limits: a mod whose own `data-final-fixes` runs after ours (because it does not depend on this
mod) is not observed, and nothing in the data stage can react to runtime changes —
`LuaTechnology.research_unit_count` is read-only.

### 2. Ghost Combinator Entity

| Field | Value |
|---|---|
| Prototype type | `constant-combinator` (copied from vanilla via `flib_data_util.copy_prototype`) |
| Size | 1x1 |
| Health | 150 (scales with quality) |
| Power | **None** — see note below |
| Recipe | 5x electronic circuit, 5x advanced circuit (0.5s) |
| Stack size | 50 |
| Minable | 0.1s → `ghost-combinator` |
| Corpse | `constant-combinator-remnants` |
| Fast replace group | `ghost-combinator` |
| Flags | `placeable-player`, `player-creation` |
| Circuit connections | Vanilla constant combinator output (red + green) |
| Graphics | Custom 4-way spritesheet + vanilla constant combinator shadow |

**Power note:** the `constant-combinator` prototype type does **not** support `energy_source` or
`active_energy_usage` — those belong to `CombinatorPrototype` (arithmetic/decider) and
crafting-machine descendants. Setting them here is ignored or strands the entity in a permanent
`no_power` status with no way to satisfy it. The Ghost Combinator therefore runs unpowered,
consistent with vanilla constant combinators. (An earlier draft of this spec called for 1kW;
that is not implementable on this prototype type.)

### 3. Configuration UI

The GUI shows the current counts as a signal grid (reusing `lib/gui/gui_circuit_inputs.lua`)
plus a status row, and two per-combinator settings. Both are stored on the combinator record
(real entities) or in ghost tags, and survive blueprints, copy-paste and cloning:

| Setting | Values | Default |
|---|---|---|
| Output mode | Builds (entity ghosts), Tiles (tile ghosts), Upgrades (upgrade requests) | Builds |
| Only count ghosts in this logistic network | on / off | **on** for new combinators; **off** for combinators and blueprints from before 1.2.0 |

A status line shows what is being counted: the whole surface, logistic network *N*, or nothing
(filter on, but not inside any roboport's supply area).

## Signal Behavior

- One signal per **(item, quality)** pair, value = number of outstanding ghosts.
- Signals are written as `type = "item"` into a `LuaLogisticSection` on the combinator's
  constant-combinator control behavior.
- **Entity name ≠ item name.** Ghosts are keyed by the item that *places* them, resolved via
  `LuaEntityPrototype.items_to_place_this[1]` (`signal_utils.get_item_name_for_entity`). This
  merges entities that share a placement item — e.g. `straight-rail` and `curved-rail-a` both
  report as `rail`.
- Quality is always written explicitly; omitting it triggers a "non-trivial filter" error.
- Tracking starts as soon as the mod is installed — **before** the technology is researched — so
  a freshly built combinator immediately reflects existing ghosts. Adding the mod to an existing
  save triggers a full rescan, so pre-existing ghosts are counted too.

### Scope — surface vs. logistic network

- **Filter off:** every tracked object on the combinator's surface, all forces.
- **Filter on:** the combinator must stand inside the *supply* (logistic) area of a stationary
  roboport. The network is found with `LuaSurface.find_logistic_network_by_position`, then one of
  its cells must pass `is_in_logistic_range(position)`, with `mobile == false` and
  `owner.type == "roboport"`. The closest cell is checked first, then all cells. Personal
  roboports and non-roboport cells never qualify, so a filtered combinator on a space platform
  outputs nothing. It counts objects whose position lies in that
  network's *construction* area (`find_logistic_networks_by_construction_area`). An object covered
  by several networks counts in each. Networks are per force, so only the combinator's force is
  seen. Outside every network the combinator outputs nothing, so it can never request items no
  robot can deliver (GitHub #5).

## Architecture

### Storage Structure

The authoritative, field-by-field description lives at the top of
`mod/scripts/ghost_combinator/storage.lua`. In outline:

```lua
storage.ghost_combinator = {
  [surface_index] = {
    categories  = { builds = CATEGORY, tiles = CATEGORY, upgrades = CATEGORY },  -- surface-wide
    networks    = { [network_id] = { categories = { builds = CATEGORY, ... } } }, -- per network
    combinators = { [unit_number] = { entity, mode, network_filter, network_id } },
    last_compact_tick = 0,
  },
}
-- CATEGORY = { entries = { ["<item>:<quality>"] = {count, slot, changed, item_name, quality} },
--              dirty, next_slot, slot_high_water }

storage.ghost_registrations = {
  [registration_number] = { surface, category, item_name, quality,
                            position, force, networks = {network_id, ...} },
}

storage.gc_rebucket = { keys = {registration_number, ...}, index, next_cycle_tick }
storage.pending_ghost_upgrades = { {surface, position}, ... }
storage.player_gui_states = { [player_index] = { open_entity, gui_type, is_ghost } }
```

### Lifecycle

**Increment** — `on_built_entity`, `on_robot_built_entity`, `on_space_platform_built_entity`,
`script_raised_built`, `script_raised_revive`, plus `on_post_entity_died` for the ghost a dying
entity leaves behind (no build event is raised for it). Upgrade requests come from
`on_marked_for_upgrade`. All registered without filters (tracking must see every entity), so each
handler's first line is a fast rejection. Each new record is also added to the network buckets
covering its position.

Tiles destroyed by asteroids raise no event at all, so their tile ghosts are only found by a
rescan.

**Decrement** — every tracked ghost is registered with
`script.register_on_object_destroyed()`, and `on_object_destroyed` drives the decrement. This is
deliberately *not* done via mined/died events, because `on_object_destroyed` also fires when a
ghost is **revived** into a real entity, which is the most common way a ghost disappears.

### Update Cadence

| Cadence | Work |
|---|---|
| Every tick | Re-bucket 50 tracked objects against current network coverage (a full pass starts at most every 300 ticks, over a sorted snapshot of registration numbers for multiplayer determinism). Then, for each dirty category or network bucket, write only the `changed` slots to the combinators displaying it. Dirty flags clear only if *every* combinator write succeeded, so a failure retries next tick. |
| Every 300 ticks (5s) | Compact categories and buckets: drop zero-count entries, reassign slots to close gaps, rewrite affected combinators. Drop empty buckets. |
| Every 600 ticks (10s) | Full resync: re-resolve each filtered combinator's network, then rewrite every combinator from storage truth. Safety net against desync from failed incremental writes. |

### Performance Constraints

The build handler runs for *every* entity placed anywhere on the map, so it must reject
non-ghosts immediately and allocate nothing in the common case. Combinator slots update on a
tick loop rather than per-ghost, gated by the `changed` / `any_changes` dirty flags.

## Critical Implementation Requirements

1. **Entity lifecycle** — clean up storage and any open GUI when a combinator is destroyed.
2. **Save/load** — all state lives in `storage`; `globals.init_storage()` runs on both `on_init`
   and `on_configuration_changed`.
3. **Multiplayer** — all state changes are deterministic and event-driven; no per-player state
   affects signal output.
4. **Quality** — health scales with quality automatically; ghost counts are keyed per quality.
5. **Invalid references** — combinator `LuaEntity` references stored per surface are validated
   on every use and dropped when stale.

## Debug Commands

| Command | Effect |
|---|---|
| `/gc-ghost-state` | Dump per-surface counts, slot assignments, combinators by mode (filtered ones as `mode@network_id`), network bucket sizes, registration count |
| `/gc-rescan` | Rebuild every counter and network bucket from a full surface scan |
| `/gc-ghost-clear [surface_id]` | Clear tracking data for one surface, or all surfaces if omitted |

## Validation Checklist

### Core Functionality
- [x] One signal per ghost item/quality with correct count
- [x] Counts survive ghost revival (bot builds it) as well as manual removal
- [x] Entities sharing a placement item merge into one signal (`rail`)
- [x] Tracking active before the technology is researched
- [ ] Recipe gated behind the technology unlock

### Entity Behavior
- [x] Health scales with quality
- [ ] Entity can be blueprinted and copy/pasted
- [ ] Circuit connections preserved in blueprints
- [x] No power requirement (constant-combinator prototype limitation)

### UI/UX
- [x] Read-only signal grid reflects live ghost counts
- [x] Pipette (`gui-pipette-signal`) works on GUI signal buttons
- [ ] GUI refreshes while open as counts change

### Events & Lifecycle
- [x] `on_object_destroyed` cleanup decrements and unregisters
- [x] Combinator destruction clears storage and closes open GUIs
- [ ] Save/load verified across a real save cycle
- [ ] Multi-surface verified (Nauvis, other planets, space platforms)

## Known Limitations

1. **Network coverage lag** — when roboports are built/removed, filtered combinators converge
   over one background re-bucket cycle (a few seconds at ~10k tracked objects).
2. **Signal type** — output is always `type = "item"`. An entity with no
   `items_to_place_this` falls back to its entity name, which may not resolve to a real item
   signal and can render as a placeholder icon.
3. **Coverage** — deconstruction orders are not tracked. Tile ghosts left by asteroid-destroyed
   foundation are only found by `/gc-rescan`. See `docs/todo.md`.

## Final Notes

- Extends vanilla without replacing anything; all vanilla behavior stays intact.
- Circuit usage is entirely optional — players can ignore the mod's output.
- Prioritize stability and per-tick performance over feature count.
- When in doubt, follow vanilla Factorio patterns.
