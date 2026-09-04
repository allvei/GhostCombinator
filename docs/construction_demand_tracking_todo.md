# Feature: Extend tracking to upgrade requests and tile ghosts

Status: **implemented, not yet tested in game**

Implementation landed in waves A–D (see the checklist in §7). Everything below the
checklist is design/verification reference and stays accurate. What remains is the
in-game testing, which no amount of static review can substitute for — there is no Lua
toolchain on this machine, so nothing has even been syntax-checked by an interpreter.

Today the combinator counts only `entity-ghost`. Three other kinds of outstanding construction
demand are invisible to it. This plan covers upgrade requests and tile ghosts.

All API facts below were verified against `runtime-api.json` from
https://lua-api.factorio.com/latest/runtime-api.json — **application_version 2.1.14, api_version 6**.
Anything marked ⚠️ is a behavioral question that needs in-game confirmation, not a doc lookup.

---

## 1. What's missing today

| Demand kind | Object in world | Currently counted? |
|---|---|---|
| Entity ghost | entity, `type == "entity-ghost"` | ✅ yes |
| Tile ghost | entity, `type == "tile-ghost"` | ❌ no |
| Upgrade request | a **real** entity with `to_be_upgraded() == true` | ❌ no |
| Deconstruction order | a real entity marked for deconstruction | ❌ no — out of scope, see §6 |

`mod/control.lua:77` gates on `entity.type == "entity-ghost"`, so tile ghosts are silently
dropped even though they arrive through the exact same events.

---

## 2. Verified API surface

### 2.1 Tile ghosts are ordinary entities

- `TileGhostPrototype` exists, type string `"tile-ghost"`: *"The entity used for tile ghosts."*
- They arrive through the **build events already registered** — `on_built_entity`,
  `on_robot_built_entity`. Confirmed by forum bug report 113438, which is specifically about
  filtering tile ghosts *in `on_built_entity`*; Rseding91: *"This is now fixed for 2.0."*
  (The fix: `ghost_name` event filters now match the underlying tile name instead of the
  literal `"tile-ghost"`. We register unfiltered, so this doesn't affect us either way.)
- On a tile ghost entity:
  - `entity.type` → `"tile-ghost"`
  - `entity.ghost_name` → underlying **tile** name, e.g. `"refined-concrete"`, `"stone-path"`
  - `entity.ghost_type` → `"tile"`
  - `entity.ghost_prototype` → `LuaTilePrototype` (the attribute is a union of
    `LuaEntityPrototype | LuaTilePrototype`)
  - `entity.unit_number` → present (prior art dedups tile ghosts on it)
- `LuaTilePrototype.items_to_place_this :: array[ItemToPlace]?` — *"Items that when placed will
  produce this tile, if any. Construction bots will choose the first item in the list."*
  `ItemToPlace = {name :: string, count :: ItemCountType}` — same shape as the entity version.

### 2.2 Placeable tiles are data-driven — do NOT hardcode

Verified against `wube/factorio-data@master`, items carrying `place_as_tile`:

- **base**: `stone-brick`, `concrete`, `refined-concrete`, `hazard-concrete`,
  `refined-hazard-concrete`, `landfill`
- **space-age**: `space-platform-foundation`, `foundation`, `ice-platform`,
  `artificial-yumako-soil`, `overgrowth-yumako-soil`, `artificial-jellynut-soil`,
  `overgrowth-jellynut-soil`

So yes — **concrete is placeable**, as suspected, along with all its variants.

⚠️ **`stone-brick` is the reason we must resolve through `items_to_place_this`.** The tile is
named `stone-path` but the item is `stone-brick`. The current fallback in
`signal_utils.get_item_name_for_entity` ("if lookup fails, return the name unchanged") would
emit a `stone-path` signal, which is not a valid item signal. Same class of bug as the existing
`straight-rail` → `rail` case.

### 2.3 Upgrade events

```
on_marked_for_upgrade   entity :: LuaEntity
                        target :: LuaEntityPrototype        -- the upgrade target
                        quality :: LuaQualityPrototype      -- target quality
                        previous_target :: LuaEntityPrototype?   -- set if ALREADY marked
                        previous_quality :: LuaQualityPrototype? -- set if ALREADY marked
                        player_index :: uint32?
   "Called when an entity is marked for upgrade with the upgrade planner or via script."

on_cancelled_upgrade    entity, target, quality, player_index?
   "Called when the upgrade of an entity is canceled."

on_pre_ghost_upgraded   ghost :: LuaEntity, target, quality, player_index?
   "Called before a ghost entity is upgraded."
```

- `LuaEntity:get_upgrade_target()` returns **two** values: `LuaEntityPrototype?, LuaQualityPrototype?`
- `LuaEntity:to_be_upgraded() -> boolean`
- Event filters exist (`LuaEntityMarkedForUpgradeEventFilter`, `LuaUpgradeCancelledEventFilter`)
  but we want every entity, so we register unfiltered — same as the existing ghost path.

### 2.4 Bootstrap / rescan support

`EntitySearchFilters` (for `find_entities_filtered` / `count_entities_filtered`) confirmed to
include `to_be_upgraded :: boolean`, `to_be_deconstructed :: boolean`, `type`, `name`,
`ghost_name`, `ghost_type`, `force`, `quality`, `limit`, `invert`.

⚠️ **`ghost_type` does not match tile ghosts.** Forum thread 123048 (Nov 2024, unanswered
modding-interface request) reports `find_entities_filtered{ghost_type="tile"}` returns nothing.
Use `type = {"entity-ghost", "tile-ghost"}` instead — that is what the prior-art mod
(codekitchen/factorio-construction-signaler) does.

`LuaTile:get_tile_ghosts(force?)` and `LuaTile:has_tile_ghost(force?)` also exist if
per-tile access is ever needed.

### 2.5 Destruction tracking

`script.register_on_object_destroyed(entity)` works on any `LuaEntity`, including tile ghosts.
Notes from the docs that matter here:

- *"Registering the same object multiple times will still only fire the destruction event once,
  and will return the same registration number."* → registration numbers are **shared**, so the
  record stored at `storage.ghost_registrations[reg]` must be able to describe what kind of
  demand it represents (see §3.2).
- The event may fire *at the end of the current tick or the next tick* — already true for the
  existing ghost path, no change.
- `LuaEntity:revive()` on a tile ghost raises `script_raised_set_tiles`, **not**
  `script_raised_revive`. Irrelevant for decrementing (we use `on_object_destroyed`), but it
  means `script_raised_set_tiles` is *not* a substitute for the destroy path.

---

## 3. Implementation plan

Placement follows `docs/module_responsibility_matrix.md` §"Adding a New Tracked Object Type" —
this is not a new entity, it feeds the existing combinator.

### 3.1 `lib/signal_utils.lua` — unified item resolution

Add a ghost-prototype-based resolver and stop guessing from names:

```lua
--- Resolve the item that places whatever this ghost represents.
--- Works for BOTH entity-ghost and tile-ghost: ghost_prototype is a union of
--- LuaEntityPrototype | LuaTilePrototype and both expose items_to_place_this.
--- @param ghost LuaEntity a tile-ghost or entity-ghost
--- @return string|nil item name, or nil if the ghost places no item
function signal_utils.get_item_name_for_ghost(ghost)
```

Also add `get_item_name_for_tile(tile_name)` for the `prototypes.tile[...]` path, and change the
existing fallback behavior: returning an unresolvable name produces an invalid signal, so
**return `nil` and skip the entry** rather than emitting a bad signal. That fixes `stone-path`
and hardens the existing entity path too.

### 3.2 `scripts/ghost_combinator/storage.lua` — registration records gain a kind

`storage.ghost_registrations[reg_number]` currently stores `{surface, name, quality}`. It needs
to say *what kind of demand* to decrement, because upgrade requests and ghosts now share the
table and a registration number is shared across registrations of the same object:

```lua
storage.ghost_registrations[reg] = {
  surface   = surface_index,
  item_name = "fast-inserter",   -- store the RESOLVED item, not the entity name
  quality   = "normal",
  kind      = "ghost" | "tile_ghost" | "upgrade",
}
```

Storing the already-resolved `item_name` also removes a `prototypes.*` lookup from the
decrement path, which currently re-resolves on every destroy.

⚠️ **Migration**: existing saves have records without `kind`/`item_name`. Handle in
`on_configuration_changed` — treat a record missing `kind` as `"ghost"` and resolve `item_name`
from the stored `name` once.

### 3.3 `scripts/ghost_combinator/control.lua` — handlers

**Tile ghosts** — smallest change of the three:

```lua
-- in control.lua's on_entity_built router
local t = entity.type
if t == "entity-ghost" or t == "tile-ghost" then
    gc_control.on_ghost_built(event)
```

`on_ghost_built` then resolves via `ghost_prototype.items_to_place_this[1].name` for both cases.
Tiles have no meaningful quality — use `entity.quality and entity.quality.name or "normal"`,
which is what the existing code already does.

**Upgrade requests**:

| Event | Action |
|---|---|
| `on_marked_for_upgrade` | If `previous_target` is set, **decrement** `previous_target`/`previous_quality` first (re-marking an already-marked entity). Then increment `target`/`quality` and `register_on_object_destroyed(entity)` with `kind = "upgrade"`. ⚠️ **2.1-only field — see §8.** |
| `on_cancelled_upgrade` | Decrement `target`/`quality`, clear the registration record. |
| `on_object_destroyed` (kind `upgrade`) | Decrement — covers upgrade completed, entity mined, entity died. |

⚠️ **The double-decrement risk.** It is not documented whether `on_cancelled_upgrade` also
fires when a bot *completes* an upgrade. If it does, the cancel path and the destroy path would
both decrement. **Mitigation (do this regardless):** make the decrement idempotent — whichever
path fires first deletes `storage.ghost_registrations[reg]`, and the second path finds no record
and does nothing. This is the same guard the existing ghost path already gets for free.

**Ghost upgraded** (`on_pre_ghost_upgraded`): ⚠️ verify in game whether upgrading an existing
ghost destroys the old ghost and builds a new one (in which case the existing
destroy + build handlers already balance the books and no new handler is needed), or mutates it
in place (in which case we must decrement `ghost.ghost_name` here and increment `target`).
Test before writing code for it.

### 3.4 `mod/control.lua` — registrations

```lua
script.on_event(defines.events.on_marked_for_upgrade, gc_control.on_marked_for_upgrade)
script.on_event(defines.events.on_cancelled_upgrade,  gc_control.on_cancelled_upgrade)
-- and, pending the §3.3 test:
-- script.on_event(defines.events.on_pre_ghost_upgraded, gc_control.on_pre_ghost_upgraded)
```

No filters — same rationale as the existing ghost registration.

### 3.5 Optional: bootstrap scan

This also fixes the long-standing "ghosts placed before the mod was installed aren't tracked"
limitation. On `on_configuration_changed`, rebuild from world truth:

```lua
surface.find_entities_filtered{ type = {"entity-ghost", "tile-ghost"} }
surface.find_entities_filtered{ to_be_upgraded = true }
```

Both filters verified present in `EntitySearchFilters`. Expensive on large maps — run it once
on config change, not on load, and consider chunking it across ticks.

---

## 4. Separate bug found while verifying — space platforms

`mod/control.lua` registers `on_built_entity`, `on_robot_built_entity`, `script_raised_built`,
`script_raised_revive` — but **not** `on_space_platform_built_entity`, which is a real 2.1 event:
*"Called when a space platform builds an entity."* There is a matching
`on_space_platform_mined_entity`.

Consequence: on a space platform, construction is done by the platform, not by construction
robots. A **ghost combinator built by the platform is never registered**, so it sits there
outputting nothing forever. Mining it never unregisters it either.

This is independent of this feature but should be fixed in the same pass:

```lua
script.on_event(defines.events.on_space_platform_built_entity, on_entity_built)
script.on_event(defines.events.on_space_platform_mined_entity, on_entity_removed)
```

---

## 5. DECIDED — output mode selector

Entity ghosts, tile ghosts and upgrade requests all resolve to **item names**, so a fast-inserter
ghost and a fast-inserter upgrade request would collide on the same `item_name:quality` key.

**Resolution: each combinator outputs exactly one category, chosen in its GUI.**
Want all three? Place three combinators and wire their outputs together — the circuit network
sums signals from multiple constant combinators on the same wire, so totals come out right with
no new signal scheme. This is strictly better than inventing an encoding, and it keeps each
combinator's output meaningful on its own.

### 5.1 Modes

| Mode | Counts | Storage category key |
|---|---|---|
| Builds *(default)* | `entity-ghost` | `builds` |
| Tiles | `tile-ghost` | `tiles` |
| Upgrades | entities with a pending upgrade request | `upgrades` |

Default is `builds`, which preserves today's behavior for existing saves and new placements.

### 5.2 Always track, filter on output

**Tracking stays global — all three categories are always counted.** The mode only selects which
category a given combinator *writes*. This makes switching modes instant (no rescan), and means
a newly placed combinator in any mode is immediately correct.

### 5.3 Storage restructure

This is the significant change. Slot numbering is currently one flat space per surface, but two
combinators in different modes need different slot→signal mappings. Categories therefore need
independent counter sets *and* independent slot spaces:

```lua
storage.ghost_combinator[surface_index] = {
  categories = {
    builds   = { entries = {["item:quality"] = {count, slot, changed, item_name, quality}},
                 any_changes = false, next_slot = 1, slot_high_water = 0 },
    tiles    = { ... },
    upgrades = { ... },
  },
  combinators_by_mode = {                 -- so the tick loop only visits matching combinators
    builds   = { [unit_number] = LuaEntity },
    tiles    = { ... },
    upgrades = { ... },
  },
  last_compact_tick = 0,
}
```

Consequences:
- `any_changes`, `next_slot`, `slot_high_water` move from surface level to **category** level, so
  a tile ghost change no longer dirties build combinators.
- The per-tick loop, `compact_slots`, and `full_resync_surface` all iterate per category.
- Changing a combinator's mode must **clear every slot it currently holds**, then write the new
  category's full set — i.e. a targeted full-resync for that one entity, not just a dirty-flag
  set. Simplest clear: `section.filters = {}` (verified read/write) rather than looping
  `clear_slot` up to `slot_high_water`.
- **Migration**: see §9 — rebuild from a world rescan rather than translating the old tables.

### 5.4 The combinator stops being read-only — verified API cost

This is the part worth being explicit about: today `on_player_setup_blueprint`,
`on_entity_settings_pasted` and `on_entity_cloned` in `scripts/ghost_combinator/control.lua` are
**deliberate no-ops** because there was nothing to persist. A per-entity setting makes all three
real work, plus a ghost-tag path. Verified against 2.1.14:

| Path | API | Notes |
|---|---|---|
| Copy/paste settings (shift+RMB/LMB) | `on_entity_settings_pasted {source, destination, player_index}` | Copy mode source→destination. Cannot be event-filtered — already handled by the existing name check in `mod/control.lua:138`. |
| Blueprint capture | `on_player_setup_blueprint {stack::LuaItemStack?, record::LuaRecord?, mapping::LuaLazyLoadedValue<uint32 → LuaEntity>, area, surface, item, quality, alt}` | ⚠️ **Must handle `record` as well as `stack`** — `record` is the blueprint-library case and is writable. `mapping` gives blueprint index → source entity. |
| Writing the tag | `LuaItemCommon:set_blueprint_entity_tag(index::uint32, tag::string, value::AnyBasic)` | ⚠️ Lives on **`LuaItemCommon`**, inherited by both `LuaItemStack` and `LuaRecord` — not on `LuaItemStack` directly. Read back with `get_blueprint_entity_tag` / `get_blueprint_entity_tags`. |
| Ghost carries the setting | `LuaEntity.tags :: Tags` — *"The tags associated with this entity ghost. `nil` if this is not an entity ghost."* | Set on the combinator's own ghost. |
| Ghost revived → real entity | `on_built_entity`, `on_robot_built_entity`, **and `on_space_platform_built_entity`** all carry `tags :: Tags?` | Read `event.tags.mode` in `on_combinator_built` and apply. Ties into the §4 space-platform bug — that registration is needed for this to work on platforms. |
| Cloning | `on_entity_cloned {source, destination}` | Copy the mode across. |
| `BlueprintEntity` | has a `tags` field | Confirms the round trip. |

### 5.5 GUI component

`GuiElementType` confirmed to include `radiobutton`, `drop-down`, `switch`, `checkbox`.

**Recommend three `radiobutton`s in a horizontal flow.** Rationale:
- Three mutually exclusive options is exactly what radio buttons are for; a `drop-down` hides the
  current value behind a click, and `switch` only has two meaningful positions (its third state
  is "none", which is semantically wrong here).
- `on_gui_checked_state_changed` is **already registered** in `mod/control.lua:186` and routed to
  `gui.on_gui_checked_state_changed`, which is currently an explicit stub. This fills it in
  rather than adding a new event path.
- Radio buttons don't auto-deselect their siblings — the handler must clear the other two
  explicitly.

Alternative if the GUI gets crowded later: `drop-down` +
`on_gui_selection_state_changed` (also verified present).

New locale strings needed under `[gui]` in `locale/en/ghost-combinator.cfg`:
`ghost-combinator-mode`, `ghost-combinator-mode-builds`, `ghost-combinator-mode-tiles`,
`ghost-combinator-mode-upgrades`, plus tooltips explaining the wire-them-together trick.

### 5.6 Still open

- Exact labels. Plan assumes **Builds / Tiles / Upgrades** per your wording. "Builds" could
  equally be "Ghosts" or "Entities" — "Builds" reads better next to the other two.
- Whether a 4th **All** mode is wanted. Not free: it needs its own counter set and slot space
  (it's a union of item keys, not a sum of the other three's slots). Cheap to add later within
  this structure; deliberately omitted for now per your design.

---

## 6. Explicitly out of scope

**Deconstruction orders.** `on_marked_for_deconstruction` / `on_cancelled_deconstruction`
(+ `on_pre_ghost_deconstructed` for ghosts) exist and are usable, but deconstruction *produces*
items rather than requiring them, so folding it into the same counters would invert the meaning
of the signal. If wanted later it should be a negative count or a separate section — a design
question, not an extension of this work.

---

## 8. Factorio 2.0 vs 2.1 compatibility

Method: diffed the full API surface (classes, attributes, methods, defines, events, concepts) of
`runtime-api.json` at 2.0.15 / 2.0.28 / 2.0.47 / 2.0.55 / 2.0.60 / 2.1.14. All are `api_version 6`.

**`info.json` is the hard gate regardless of code:** it declares `factorio_version: "2.1"` and
`base >= 2.1.0`, so the mod will not load on 2.0 at all. Dropping to 2.0 means changing both.

### Currently shipped code

Nothing 2.1-exclusive. Every runtime symbol in use exists in 2.0.15, with one caveat:

- **`LuaPlayer:pipette()`** (`mod/control.lua:37`) — absent in 2.0.15 / .28 / .47 / .55,
  present in 2.0.60. So it needs roughly **2.0.56+**, not 2.1. Not a 2.1 dependency, but not
  compatible with all of 2.0 either.
- `LuaEntityPrototype.items_to_place_this` / `LuaTilePrototype.items_to_place_this` exist in
  both, but the array element type was **renamed** `ItemStackDefinition` (2.0) → `ItemToPlace`
  (2.1). Both shapes carry `.name` and `.count`, so `items_to_place_this[1].name` is correct on
  both. Documentation rename only, no code change.
- `LuaEntity:get_signals`, `get_circuit_network`, `get_control_behavior`, `get_section`,
  `add_section`, `set_slot`, `clear_slot`, `register_on_object_destroyed`,
  `defines.wire_connector_id`: all present since 2.0.15.

### This feature

One genuine 2.1-only dependency:

- ⚠️ **`on_marked_for_upgrade.previous_target` / `.previous_quality`** — verified **absent
  through 2.0.60**, present in 2.1.14. This is the field §3.3 relies on to decrement the old
  target when an already-marked entity is re-marked.
  **2.0 fallback if ever needed:** store the last known upgrade target on our own registration
  record and diff against it on re-mark. We already keep a per-entity record, so this costs one
  extra field and no new API.

Everything else the feature needs — `on_marked_for_upgrade`, `on_cancelled_upgrade`,
`on_pre_ghost_upgraded`, `on_space_platform_built_entity`, `on_space_platform_mined_entity`,
`EntitySearchFilters.to_be_upgraded`, tile-ghost handling — exists as far back as 2.0.15.

### Unrelated 1.1 leftovers found in `lib/circuit_utils.lua`

`defines.circuit_connector_id` does **not exist in 2.0 or 2.1** (it was replaced by
`defines.wire_connector_id`). It is still referenced in live code:

- `circuit_utils.has_circuit_connection` (line ~168-172) indexes
  `defines.circuit_connector_id.*` → would error on a nil index, and also calls the 1.1
  two-argument form `entity.get_circuit_network(wire_type, connector_id)`.
- `circuit_utils.has_any_circuit_connection` (line 244) is its only caller.

**Currently unreachable** — nothing outside `circuit_utils.lua` calls either function; the only
external entry point is `gui_circuit_inputs.lua:144` → `get_input_signals_raw`, which correctly
uses `entity.get_signals(defines.wire_connector_id.…)`. So this is latent, not a live crash.
Delete both functions or port them to `wire_connector_id` before anything starts calling them.
(The `get_merged_signals` reference at line 132 is inside a comment block — harmless, but
`LuaEntity:get_merged_signals` does not exist in 2.0/2.1 either, so the "migration guide" it
documents is wrong.)

---

## 9. Migration strategy — rescan, don't translate

**Yes, a full surface rescan is possible, and it should be the migration.** Translating the old
flat tables into the new per-category shape would faithfully preserve state that we already know
is *incomplete* — it's missing pre-install ghosts (§ Known Limitations), anything lost to a
missed event, every combinator built by a space platform (§4), and of course all tile and upgrade
demand, which was never counted. Rebuilding from world truth is both simpler and strictly more
correct.

### 9.1 Existing combinators default to Builds

There is no stored mode in old saves, so every combinator discovered by the rescan is assigned
`mode = "builds"`. That reproduces today's exact behavior: an existing base keeps emitting the
same entity-ghost signals it did before the update, and nothing silently changes meaning.

### 9.2 The rescan

Run from `on_configuration_changed`. Every call verified against 2.1.14:

```lua
for _, surface in pairs(game.surfaces) do
  -- whole surface: docs state that with no `area` and no `position`, the entire surface is searched
  local ghosts   = surface.find_entities_filtered{ type = {"entity-ghost", "tile-ghost"} }
  local upgrades = surface.find_entities_filtered{ to_be_upgraded = true }
  local combs    = surface.find_entities_filtered{ name = "ghost-combinator" }
end
```

- `type` accepts `string | array[string]`, and `to_be_upgraded :: boolean` is a confirmed member
  of `EntitySearchFilters`.
- ⚠️ Use `type`, **not** `ghost_type` — `ghost_type="tile"` does not match tile ghosts (§2.4).
- Per ghost: `ghost.ghost_prototype.items_to_place_this[1].name` → item, same resolver as §3.1.
- Per upgrade: `entity.get_upgrade_target()` returns **two** values,
  `LuaEntityPrototype?, LuaQualityPrototype?` — take `.items_to_place_this[1].name` from the
  prototype and `.name` from the quality.

### 9.3 Why re-registering is safe

The rescan wipes `storage.ghost_registrations` and re-registers everything it finds. This is safe
because of a documented property of the API:

> *"Registering the same object multiple times will still only fire the destruction event once,
> and will return the same registration number."*

So objects that were already registered by the previous version return their **existing**
registration numbers — no duplicates, no double-decrement, no leaked registrations. Registrations
also survive save/load on their own, so nothing is lost by rebuilding the lookup table around them.

### 9.4 Combinator output must be wiped first

Slot numbering is reassigned by the rescan, so stale slots from the old flat numbering would
survive as phantom signals. Before rewriting, clear each combinator's section outright:

```lua
local section = cb.get_section(1)
if section then section.filters = {} end   -- `filters` is read/write; wipes every slot at once
```

Then do a normal full resync for that combinator's category.

### 9.5 Rescan as a side benefit

The same pass fixes three standing problems for existing saves:

1. **The bootstrap limitation** — ghosts placed before the mod was installed finally get counted.
2. **The space-platform bug (§4)** — combinators built by a platform were never registered;
   `find_entities_filtered{name="ghost-combinator"}` finds them regardless of how they were built.
3. Any drift accumulated from a missed or failed event.

Worth exposing manually too, alongside the existing debug commands: **`/gc-rescan`** — same code
path, for repairing a save without an update. Cheap to add once the function exists.

### 9.6 Cost and open question

⚠️ `on_configuration_changed` is a single blocking call at load. On a megabase with a very large
ghost count this does real work: it materializes a `LuaEntity` per ghost and calls
`register_on_object_destroyed` on each. Expect a one-time hitch measured in seconds at the top
end. That is acceptable for a migration, but it should `log()` the counts and elapsed ticks so
it's diagnosable.

If profiling shows it's too slow, the fallback is to set a `storage.pending_rescan` flag and
process surfaces (or chunks) across ticks in `on_tick`, accepting that combinators show partial
counts until it finishes. **Recommend starting with the simple blocking version** and only
building the chunked path if measurement justifies it.

Trigger: rescan when `data.mod_changes["ghost-combinator"]` is present (verified —
`ConfigurationChangedData.mod_changes` is a dictionary indexed by mod name, values carrying
`old_version` / `new_version`). Rescanning on *every* unrelated mod change would be self-healing
but makes every mod update in the save pay the cost.

### 9.7 Pre-existing behavior to be aware of

The rescan counts ghosts of **all forces**, matching what the event handlers already do. In a
multi-force PvP save that means one combinator reports every force's demand. This is existing
behavior, not a regression — but if it should be per-force, both the rescan and the event
handlers need a `force` filter, and that's a separate decision.

---

## 7. Task checklist

**Counting**
- [x] `signal_utils`: add `get_item_name_for_ghost` / `get_item_name_for_tile`, return `nil`
      instead of a bad-name fallback, memoized
- [x] `storage.lua`: `category` + resolved `item_name` on registration records
- [x] `control.lua` (router): accept `tile-ghost` in the build path
- [x] `control.lua` (gc): `on_marked_for_upgrade` incl. `previous_target` handling
- [x] `control.lua` (gc): `on_cancelled_upgrade`, idempotent decrement
- [x] `mod/control.lua`: register upgrade events
- [x] Register space platform build/mine events (§4)
- [x] Drop surface data on `on_surface_deleted` / `on_surface_cleared`

**Output mode (§5)**
- [x] `storage.lua`: restructure to per-category `entries`/`next_slot`/`dirty`/`slot_high_water`;
      combinator records became `{entity, mode}` (no `combinators_by_mode` index — the tick
      loop filters by `mode`, which is free at realistic combinator counts)
- [x] `control.lua`: per-category tick loop, compaction, and full resync
- [x] `control.lua`: mode change wipes the section (`section.filters = {}`) then rewrites
- [x] `gui.lua`: **drop-down**, not radiobuttons — `on_gui_selection_state_changed` +
      `tags.action`, matching LogisticsCombinator. No mod in the family uses `radiobutton`.
- [x] Persist mode: `on_entity_settings_pasted`, `on_entity_cloned`,
      `on_player_setup_blueprint` (**both `stack` and `record`**, via
      `set_blueprint_entity_tags`), ghost `LuaEntity.tags`, and `event.tags` in
      `on_combinator_built`
- [x] Locale strings, following FilterCombinator's `-mode-header` / `-mode-<x>` / `-desc` keys
- [ ] Test: blueprint a configured combinator → paste → revive from ghost, mode survives on all
      three build paths (player, robot, space platform)
- [ ] Test: two combinators in different modes on one surface do not corrupt each other's slots
- [ ] Test: wiring two combinators' outputs together sums as expected

**Migration (§9)**
- [x] `rescan.lua`: per surface, `find_entities_filtered` for ghosts / `to_be_upgraded` /
      `name="ghost-combinator"`; rebuilds all category counters from scratch
- [x] Wipes `storage.ghost_registrations` and re-registers everything found
- [x] Preserves the mode of already-known combinators; anything newly discovered gets "builds"
- [x] `ensure_schema` upgrades pre-category save records in place — legacy
      `combinators[un] = LuaEntity` becomes `{entity, mode}`. Without this, reading `.mode`
      off a `LuaEntity` raises "doesn't contain key mode" — a hard crash on old saves.
- [x] Gated on `data.mod_changes["ghost-combinator"]`; logs counts + elapsed ticks
- [x] `/gc-rescan` command on the same code path; `/gc-ghost-state` now dumps per category
- [ ] Test: update an existing save — combinators keep emitting the same build signals,
      no phantom slots, and previously-untracked ghosts now appear
- [ ] Profile the rescan on a large save; build the chunked fallback only if needed
- [ ] ⚠️ In-game: confirm `on_cancelled_upgrade` does **not** fire on upgrade completion
- [ ] ⚠️ In-game: confirm `on_pre_ghost_upgraded` destroy/rebuild behavior
- [ ] ⚠️ In-game: confirm tile ghosts reach `on_built_entity` with `type == "tile-ghost"`
- [ ] Test: landfill, concrete, refined concrete, stone brick (→ `stone-brick`, not `stone-path`),
      space platform foundation
- [ ] Test: upgrade planner mark → cancel → re-mark with a different target
- [ ] Optional: bootstrap scan (§3.5)
