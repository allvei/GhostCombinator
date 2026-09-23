# Ghost Combinator — Development TODO

Index of active work. Detailed per-feature plans live in `docs/<feature>_todo.md` and are
linked from here.

## Current Status

Shipped through v1.1.0; v1.2.0 in progress. Entity ghosts, tile ghosts and upgrade requests are
all tracked, with a per-combinator output mode selector. v1.1.0 re-gated the technology behind
Construction robotics + Circuit network and derives its cost from those prerequisites.

v1.2.0 fixes GitHub issues #3 (in-game changelog), #4 (ghosts left by destroyed entities) and #5
(per-logistic-network filter); #1 was already fixed in 1.0.0.
**Plan: [docs/issue_fixes_todo.md](issue_fixes_todo.md)** — awaiting in-game test.

## Completed

### Ghost Combinator core (v0.1.0 – v0.2.0)
- [x] Entity prototype (1x1 constant-combinator base, unpowered)
- [x] Item and recipe definitions
- [x] Technology unlock
- [x] Ghost tracking (increment on build, decrement via `on_object_destroyed`)
- [x] Signal output via `LuaLogisticSection` (`get_section` / `set_slot` / `clear_slot`)
- [x] Item-name resolution through `items_to_place_this` (so `straight-rail` → `rail`)
- [x] Per-quality tracking
- [x] Read-only GUI showing ghost counts, with pipette support
- [x] Per-surface tracking
- [x] Slot compaction every 5s, full resync every 10s
- [x] EN locale strings
- [x] Custom entity sprite + icon
- [x] Debug commands (`/gc-ghost-state`, `/gc-ghost-clear`)

## Open Work

### Correctness
- [ ] **Locale mod-name key mismatch.** `locale/en/ghost-combinator.cfg` has
      `[mod-name] mission-control=` / `[mod-description] mission-control=`, but `info.json`
      declares `name = "ghost-combinator"`, so neither string resolves. Rename both keys.
- [ ] **Stale "Mission Control" headers** in `mod/data.lua`, `mod/lib/gui/gui_entity.lua`,
      `mod/lib/gui/gui_circuit_inputs.lua`, `mod/scripts/ghost_combinator/gui.lua`,
      `mod/prototypes/technology/technologies.lua`, and the `Makefile` banner.
- [ ] **Dead references in `lib/circuit_utils.lua` header** — points at a `validation.lua` that
      does not exist in this project.
- [ ] **1.1-era API in `lib/circuit_utils.lua`.** `has_circuit_connection` /
      `has_any_circuit_connection` use `defines.circuit_connector_id` (removed in 2.0, replaced
      by `defines.wire_connector_id`) and the 1.1 two-arg `get_circuit_network(wire, connector)`.
      Currently unreachable — nothing outside the lib calls them — so latent, not a live crash.
      Delete or port. Detail in the feature plan, §8.

### Coverage — untracked construction demand
Originally the combinator only counted `entity-ghost`:
- [x] Upgrade requests (`on_marked_for_upgrade` / `on_cancelled_upgrade`) — 1.0.0
- [x] Tile ghosts (`type == "tile-ghost"`) — landfill, all concrete variants, stone brick,
      space platform foundation, and the Space Age soils/platforms — 1.0.0
- [ ] Deconstruction orders — out of scope for now; they *produce* items rather than requiring
      them, so they'd invert the meaning of the signal

**Feature plan: [docs/construction_demand_tracking_todo.md](construction_demand_tracking_todo.md)**
(APIs verified against Factorio 2.1.14 / api_version 6)

### Space platform events
- [x] `on_space_platform_built_entity` / `on_space_platform_mined_entity` registered (1.0.0).
- [x] Ghosts left by destroyed entities (asteroids) tracked via `on_post_entity_died` (1.2.0, #4).
- [ ] Foundation tiles destroyed by asteroids raise no event; their tile ghosts are only picked up
      by `/gc-rescan`.

### Upstream fixes for `../FactorioBaseMod` (affect the whole mod family)
- [ ] **`lib/gui_utils.lua:134` uses `utility/close_white`, which does not exist in Factorio 2.x.**
      Verified against `wube/factorio-data` `core/prototypes/utility-sprites.lua`: the key is
      `close` (line 2694); `close_white` is a 1.1 name. Assigning a nonexistent sprite raises
      `Sprite 'utility/close_white' does not exist`, so **any call to `create_titlebar` crashes**.
      Latent today — `create_titlebar` and `create_status_label` have zero callers anywhere in
      the family. Fix in the base mod and re-sync, rather than diverging in one mod.
      (`utility/warning_icon` at :36 was also flagged but is **valid** — it exists at line 836.)
- [ ] `lib/gui_utils.lua` `create_status_label` concatenates its `status_text` parameter, which
      is documented as a `LocalisedString`; passing the documented type throws. Build a
      localised caption (`{"", icon, " ", status_text}`) instead.
- [ ] `lib/gui_utils.lua` declares ~17 functions as globals rather than locals.
- [ ] Family-wide `defines.circuit_connector_id` / `get_merged_signals` 1.1 leftovers in
      `lib/circuit_utils.lua` (unreachable in all four mods).
- [ ] Backport this mod's better `lib/gui/gui_entity.lua` (uses `entity.status` + locale keys).

### Code health
- [x] Split the per-instance config concern out of `storage.lua` into
      `scripts/ghost_combinator/config.lua`. All modules now within the 750–900 line limit.
- [ ] **No Lua toolchain on this machine** — `lua`, `luac`, `luacheck` and `luarocks` are all
      absent, so `make lint` cannot run and nothing has been compiled. Static checks used
      instead: cross-module call resolution, and a block/delimiter balance pass. Install
      luacheck before trusting any of this in game.
- [ ] **`.luacheckrc` has never been executed.** Added in v1.1.0 (the `Makefile` and `CLAUDE.md`
      both referenced it, but the file did not exist, so `make lint` and `make ci` were dead even
      with luacheck installed). It bans `global` outright to catch 1.1-isms, enables the
      undefined-global codes 111/112/113 that the family config disables, and forbids `storage`
      inside `mod/lib/` to enforce the stateless-lib rule. Expect to tune it on the first real
      run. It exempts `mod/lib/gui_utils.lua` from 111/112/113 — see the global-functions item
      under upstream fixes; delete that exemption once the base mod is fixed.

### Testing & Performance
- [ ] Integration testing with blueprints (place/cancel large blueprints)
- [ ] Performance profiling with large ghost counts (10k+ ghosts)
- [ ] Multi-surface testing (Nauvis, other planets, space platforms)
- [ ] Save/load round-trip verification
- [ ] Multiplayer desync check

## Known Limitations

1. **Network re-bucket lag** — when roboport coverage changes, filtered combinators converge over
   one background re-bucket cycle rather than instantly (see `docs/issue_fixes_todo.md`).
2. **Signal type** — output is always `type = "item"`. Entities without `items_to_place_this`
   fall back to their entity name, which may not be a valid item signal.
