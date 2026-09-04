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
| Prerequisites | `logistic-system`, `production-science-pack` |
| Science packs | automation, logistic, chemical, production, utility (1 each per cycle) |
| Unlocks | `ghost-combinator` recipe |
| Icon | `graphics/entities/ghost-combinator-icon.png` (64x64) |

> ⚠️ **Known deviation:** the intended cost is 500 cycles at 30s each. The prototype currently
> ships `count = 5, time = 3` (dev-testing values). Tracked in `docs/todo.md`.

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

Read-only. The GUI shows the current ghost counts as a signal grid (reusing
`lib/gui/gui_circuit_inputs.lua`) plus a status row. There is nothing for the player to
configure — the combinator always reports its own surface.

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
  a freshly built combinator immediately reflects existing ghosts.

## Architecture

### Storage Structure

```lua
storage.ghost_combinator = {
  [surface_index] = {
    combinators = { [unit_number] = LuaEntity },
    ghosts = {
      ["<item_name>:<quality>"] = {
        count      = N,
        slot       = M,          -- logistic section slot index
        changed    = boolean,    -- dirty flag, drives incremental writes
        item_name  = "iron-chest",
        quality    = "normal",
      },
    },
    any_changes      = boolean,  -- surface-level dirty flag
    next_slot        = 1,
    last_compact_tick = 0,
    slot_high_water  = 0,        -- highest slot ever used; bounds orphan clearing on resync
  },
}

storage.ghost_registrations = {
  [registration_number] = { surface = idx, name = ghost_name, quality = quality_name },
}

storage.player_gui_states = { [player_index] = { open_entity, gui_type, is_ghost } }
```

### Lifecycle

**Increment** — `on_built_entity`, `on_robot_built_entity`, `script_raised_built`,
`script_raised_revive`. Registered without filters (ghost tracking must see every entity), so
the handler's first line is a `entity.type ~= "entity-ghost"` fast rejection.

**Decrement** — every tracked ghost is registered with
`script.register_on_object_destroyed()`, and `on_object_destroyed` drives the decrement. This is
deliberately *not* done via mined/died events, because `on_object_destroyed` also fires when a
ghost is **revived** into a real entity, which is the most common way a ghost disappears.

### Update Cadence

| Cadence | Work |
|---|---|
| Every tick | For each surface with `any_changes`, write only the `changed` slots. Dirty flags clear only if *every* combinator write succeeded, so a failure retries next tick. |
| Every 300 ticks (5s) | Compact: drop zero-count entries, reassign slots to close gaps, clear orphaned slots above the new max. |
| Every 600 ticks (10s) | Full resync: rewrite every slot from storage truth up to `slot_high_water`, clearing orphans. Safety net against desync from failed incremental writes. |

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
| `/gc-ghost-state` | Dump per-surface ghost counts, slot assignments, combinator count, registration count |
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

1. **Bootstrap** — ghosts that existed before the mod was installed are not tracked. There is no
   startup scan.
2. **Signal type** — output is always `type = "item"`. An entity with no
   `items_to_place_this` falls back to its entity name, which may not resolve to a real item
   signal and can render as a placeholder icon.
3. **Coverage** — only `entity-ghost` objects are counted. Upgrade requests, tile ghosts
   (landfill, concrete, space platform foundation), and deconstruction orders are **not**
   tracked. See `docs/todo.md`.

## Final Notes

- Extends vanilla without replacing anything; all vanilla behavior stays intact.
- Circuit usage is entirely optional — players can ignore the mod's output.
- Prioritize stability and per-tick performance over feature count.
- When in doubt, follow vanilla Factorio patterns.
