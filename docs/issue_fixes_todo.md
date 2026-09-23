# GitHub Issue Fixes — v1.2.0

Covers the open issues on `gpalumbo/GhostCombinator` as of 2026-09-23.
APIs verified against Factorio Runtime Docs **2.1.20**.

| Issue | Title | Resolution |
|---|---|---|
| #1 | Pre-existing construction ghosts are not recognized | Already fixed in 1.0.0 — no code change |
| #3 | Changelog not accessible via mod portal/mods page | Fixed `changelog.txt` format errors |
| #4 | Destroyed space platform entity ghosts don't appear | Track `on_post_entity_died.ghost` |
| #5 | Only output signals of the logistic network the combinator is in | Per-network buckets + per-combinator filter |

---

## #1 — Pre-existing ghosts (no code change)

- [x] Confirmed fixed since 1.0.0: `on_configuration_changed` runs `gc_rescan.rescan_all()` whenever
      `mod_changes["ghost-combinator"]` is present, which includes adding the mod to an existing
      save. `/gc-rescan` repairs on demand.
- [x] Removed the stale "Bootstrap" known limitation from `docs/todo.md` and `README.md`.
- [ ] Close #1 on GitHub with a pointer to 1.0.0 / `/gc-rescan` (maintainer action).

## #3 — In-game changelog does not display

Root cause: the in-game parser (see
<https://lua-api.factorio.com/latest/auxiliary/changelog-format.html>) aborts on the first error,
which hides the whole changelog. The mod portal displays it as plain text, so it looked fine there.

- [x] `Version: 0.2.0` used `  Update` — a category line without the mandatory trailing colon.
- [x] Trailing whitespace on four entry lines (the spec forbids it).
- [x] Malformed date `2025-11-226`.
- [x] Renamed `Bug Fixes:` → `Bugfixes:` and the ad-hoc categories to recognized ones so they sort
      into the proper tabs.

## #4 — Ghosts left by destroyed entities are not counted

When an entity dies and leaves a ghost (asteroid damage on platforms, biters on planets), the engine
raises `on_post_entity_died` with `event.ghost` and **no build event**. The mod only counted ghosts
from build events, so these were invisible.

- [x] `control.on_post_entity_died` — first-line reject when `event.ghost` is nil/invalid, then the
      idempotent `track_ghost`.
- [x] Registered unfiltered in `mod/control.lua` (no filter selects "left a ghost").
- Out of scope: **tiles**. Foundation destroyed by asteroids (`TilePrototype.dying_explosion`) raises
  no runtime event, so tile ghosts created that way are only picked up by `/gc-rescan`.

## #5 — Only count demand inside the combinator's logistic network

Surface-wide counts can request items no robot can ever deliver, which, wired into a requester,
creates requests that never go away.

### Behavior
- New per-combinator checkbox **"Only count ghosts in this logistic network"**.
  - New combinators: **on**.
  - Existing combinators (and blueprints made before 1.2.0): **off** — they keep the surface-wide
    behavior. A missing `network_filter` field is read as off.
- A filtered combinator must stand inside the **supply area of a stationary roboport**. The
  network comes from `LuaSurface.find_logistic_network_by_position`, and one of its cells must
  pass `LuaLogisticCell.is_in_logistic_range(position)` with `mobile == false` and
  `owner.type == "roboport"`. The closest cell is checked first, then all `network.cells`.
  Personal roboports and non-roboport cells (e.g. a space platform hub) do not qualify.
- It counts demand whose position lies in that network's *construction* area
  (`find_logistic_networks_by_construction_area`).
- Not in any roboport's supply area → outputs nothing. On space platforms this means filtered
  combinators output nothing; use the whole-surface setting there.
- Networks are per force, so a filtered combinator only ever sees its own force's demand.
  Unfiltered combinators remain surface-wide across forces, as before.

### Design
- Each registration record also stores `position`, `force` (index) and `networks` (array of the
  network ids it is currently counted in).
- `surface_data.networks[network_id].categories[category]` — per-network buckets with the same
  entry/slot shape as the surface categories, so all write/compact/resync code is shared.
- **Incremental:** when an object is tracked, look up the covering networks and add it to each
  bucket; when it is destroyed or cancelled, remove it from every bucket in its record.
- **Background re-bucket** (`networks.rebucket_step`, every tick): walks a sorted snapshot of
  registration numbers, `REBUCKET_BATCH` records per tick, re-checking each record's networks and
  moving it between buckets when roboport coverage changed. A new cycle starts at most every
  `REBUCKET_CYCLE_TICKS`. The snapshot is sorted so every peer processes records in the same
  order (bucket slot assignment is game state).
- Filtered combinators re-resolve their `network_id` on placement, config change and on every full
  resync (10s); a changed id triggers a full rewrite.
- Compaction also runs over network buckets, and drops buckets left with no entries.

### Tasks
- [x] `scripts/ghost_combinator/networks.lua` — buckets, attach/detach, re-bucket, network lookup.
- [x] `storage.lua` — extract `category_add` / `category_remove` / `compact_category`, export
      `new_category`, record `network_filter` on combinators, return the registration record.
- [x] `control.lua` — attach/detach on every track/untrack path; output source selection;
      tick/compaction/resync over buckets; `get_display_entries` for the GUI.
- [x] `rescan.lua` — rebuild buckets; preserve `network_filter` on existing combinators.
- [x] `config.lua` — `network_filter` get/set, blueprint/paste/clone/ghost-tag round trip.
- [x] `gui.lua` — checkbox + network status line; grid shows the filtered set.
- [x] Locale strings.

### Known limitations
- After roboports are built/removed, bucket counts converge over one re-bucket cycle (a few seconds
  for ~10k tracked objects) rather than instantly.
- Tile ghosts from destroyed foundation (see #4).

## Release
- [x] `info.json` → 1.2.0, changelog entry.
- [x] `docs/todo.md`, `docs/spec.md`, `docs/module_responsibility_matrix.md`, `CLAUDE.md`,
      `README.md` updated.
- [ ] In-game test (no Lua toolchain on the dev machine): place/remove roboports under a filtered
      combinator, destroy an entity on a platform, verify the in-game changelog renders.
