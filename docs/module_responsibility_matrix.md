# Module Responsibility Matrix

**Read this before writing any code.** It defines exactly where each kind of function belongs.
When a new function doesn't obviously fit, run the decision tree at the bottom.

The governing split:

- `mod/lib/**` — **stateless.** Never touches `storage`. Never knows a mod entity name.
  Pure functions plus thin wrappers over the Factorio API. Reusable by any future entity.
- `mod/scripts/**` — **stateful.** Owns `storage`. Knows mod entity names. One directory per
  entity type.
- `mod/control.lua` — **routing only.** Registers events and dispatches. No business logic.
- `mod/prototypes/**` — **data stage only.** Never referenced at runtime.

---

## Module Table

| Module | Owns | Must NOT do |
|---|---|---|
| `mod/control.lua` | `script.on_event` / `on_nth_tick` registration, event filters, dispatch to `scripts/*`, console commands | Business logic, storage reads/writes, prototype lookups |
| `mod/data.lua` | Requiring prototype files in order | Anything runtime |
| `lib/entity_lib.lua` | Ghost-aware entity identity: `get_name`, `is_type`, `is_ghost` | Storage access, mod-specific names |
| `lib/circuit_utils.lua` | Reading/writing signals on a `LuaEntity`'s wire connectors, connection checks | Signal *table* math, storage, mod-specific entities |
| `lib/signal_utils.lua` | Pure signal-table math (add/merge/copy/compare/count), signal keys, condition evaluation, prototype lookups (`signal_to_prototype`, `get_item_name_for_entity`) | Reading signals off entities (that's `circuit_utils`), storage |
| `lib/gui/gui_entity.lua` | Generic entity GUI widgets (status/power row) | Mod-specific layout, storage |
| `lib/gui/gui_circuit_inputs.lua` | Reusable signal-grid rendering | Mod-specific layout, storage |
| `scripts/globals.lua` | `init_storage()` aggregation, shared player GUI state, GUI cleanup on entity death | Entity-specific counting logic |
| `scripts/ghost_combinator/storage.lua` | The `storage.ghost_combinator` and `storage.ghost_registrations` tables: surface data, increment/decrement, slot assignment, compaction, combinator registration | Writing to combinator control behaviors, GUI, event registration |
| `scripts/ghost_combinator/control.lua` | Event handlers, writing ghost counts into combinator `LuaLogisticSection` slots, per-tick update, periodic compaction and full resync | Direct `script.on_event` calls, GUI element creation |
| `scripts/ghost_combinator/rescan.lua` | Rebuilding all counters from a full surface scan (`find_entities_filtered`), used by the version-change migration and `/gc-rescan` | Running on any routine path — it is a blocking whole-surface sweep |
| `scripts/ghost_combinator/gui.lua` | Building/refreshing/closing the read-only ghost GUI, GUI event handling | Mutating ghost counts, registering events |
| `prototypes/**` | Data-stage prototype definitions | Any `storage`/`game`/`script` reference |

---

## Storage Ownership

Only `scripts/` modules touch `storage`. Each top-level key has exactly one owning module:

| Storage key | Owner |
|---|---|
| `storage.ghost_combinator[surface_index]` | `scripts/ghost_combinator/storage.lua` |
| `storage.ghost_registrations[registration_number]` | `scripts/ghost_combinator/storage.lua` |
| `storage.player_gui_states[player_index]` | `scripts/globals.lua` |

Other modules read this data only through the owning module's accessors
(`get_surface_data`, `get_entries`, `get_category`, `get_combinators`, `get_mode`,
`get_player_gui_state`, …).
Every new storage key must be initialized in that owner's `init_storage()` and reachable from
`globals.init_storage()`, which `on_init` and `on_configuration_changed` both call.

---

## Decision Tree

Start at 1 and take the first branch that matches.

1. **Does it run in the data stage (defines a prototype)?**
   → `mod/prototypes/<category>/<entity>.lua`, and require it from `mod/data.lua`.
   Follow @docs/entity_creation_checklist.md.

2. **Is it a `script.on_event` / `on_nth_tick` / `commands.add_command` registration?**
   → `mod/control.lua`. The registration is one line that calls into a `scripts/` handler.
   Put the filter on the registration where the API supports it; put fast-rejection type checks
   on the first line of the handler where it doesn't.

3. **Does it read or write `storage`?**
   → `mod/scripts/`.
   - Data shape, counts, slot bookkeeping, registration tables → `<entity>/storage.lua`
   - Reacting to an event, driving the entity's behavior, writing to control behaviors →
     `<entity>/control.lua`
   - State shared across *all* entity types (player GUI state) → `scripts/globals.lua`

4. **Does it create or update `LuaGuiElement`s?**
   → Reusable across entity types: `mod/lib/gui/`.
   → Specific to one entity's window: `mod/scripts/<entity>/gui.lua`.

5. **Does it name a specific mod entity (e.g. `"ghost-combinator"`)?**
   → `mod/scripts/<entity>/`. `lib/` must stay entity-agnostic.

6. **Does it call the Factorio API but hold no state?**
   → `mod/lib/`.
   - Entity identity/ghost handling → `entity_lib.lua`
   - Circuit connector reads/writes → `circuit_utils.lua`
   - Prototype lookups and signal-table math → `signal_utils.lua`

7. **Is it a pure function over plain Lua tables?**
   → `mod/lib/signal_utils.lua` (signals) or a new `mod/lib/<topic>_utils.lua`.

---

## Adding a New Tracked Object Type

Extending tracking to something beyond entity ghosts (upgrade requests, tile ghosts,
deconstruction orders) does **not** get its own `scripts/` directory — it feeds the same
combinator. Place the work as:

- New event registrations → `mod/control.lua`
- New handlers and the increment/decrement calls → `scripts/ghost_combinator/control.lua`
- Any new storage sub-table or key-namespacing → `scripts/ghost_combinator/storage.lua`
- Prototype → item-name resolution for the new object kind (e.g. tile prototypes) →
  `lib/signal_utils.lua`, alongside `get_item_name_for_entity`

---

## Anti-Patterns

- `require`ing a `scripts/` module from a `lib/` module. `lib/` depends on nothing in `scripts/`.
- Reading `storage.ghost_combinator` directly from `gui.lua` or `control.lua` instead of going
  through `storage.lua` accessors. (`control.lua` currently iterates
  `storage.ghost_combinator` directly in its tick loops for speed — that is a deliberate
  exception on the hot path, not a pattern to copy.)
- Business logic inside a `script.on_event` closure in `control.lua`.
- Hardcoding an entity name in `lib/`.
- Prototype lookups (`prototypes.entity[...]`) inside a per-ghost hot path without caching.
