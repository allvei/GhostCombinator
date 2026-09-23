-- Ghost Combinator - Rescan Module
-- Rebuilds all demand counters from world truth.
--
-- WHY THIS EXISTS
-- Tracking is event-driven, so anything that existed before the events were
-- registered is invisible. This module is the one-time repair path, used for:
--   1. Migration to a version that tracks new categories (tiles, upgrades) -
--      there is no other way to learn about demand that already exists.
--   2. The /gc-rescan command, for repairing a save without a mod update.
--   3. Fixing the long-standing "ghosts placed before the mod was installed are
--      never counted" limitation.
--
-- COST: this is a blocking, whole-surface sweep. It is deliberately NOT wired to
-- anything routine - never to mode changes, never to on_load. Runtime tracking
-- counts all categories all the time precisely so no scan is ever needed to
-- "catch up" during normal play.
--
-- Lives in its own module to keep control.lua within the file-size limit in
-- CLAUDE.md, and belongs under scripts/ per docs/module_responsibility_matrix.md
-- because it is stateful and entity-specific.

local gc_storage = require("scripts.ghost_combinator.storage")
local gc_networks = require("scripts.ghost_combinator.networks")
local signal_utils = require("lib.signal_utils")

local rescan = {}

local GHOST_COMBINATOR = "ghost-combinator"
local UPGRADE_CATEGORY = "upgrades"

--- Ghost entity types we track, and the category each feeds.
--- CRITICAL: filter on `type`, NOT `ghost_type`. find_entities_filtered's
--- ghost_type filter does not match tile ghosts (a known engine limitation),
--- so `ghost_type = "tile"` silently returns nothing.
local GHOST_TYPES = {"entity-ghost", "tile-ghost"}
local GHOST_TYPE_CATEGORY = {
    ["entity-ghost"] = "builds",
    ["tile-ghost"] = "tiles"
}

-----------------------------------------------------------
-- INTERNAL
-----------------------------------------------------------

--- Reset every category on a surface to empty, preserving combinator records
--- @param surface_index number The surface index
--- @return table|nil The surface data table
local function reset_surface_categories(surface_index)
    local surface_data = gc_storage.get_surface_data(surface_index)
    if not surface_data then
        return nil
    end

    for _, category_name in ipairs(gc_storage.CATEGORIES) do
        surface_data.categories[category_name] = {
            entries = {},
            dirty = true,
            next_slot = 1,
            slot_high_water = 0
        }
    end

    -- Buckets are rebuilt alongside the categories by the scans below.
    gc_networks.reset_surface(surface_data)

    return surface_data
end

--- Count every ghost and tile ghost on a surface
--- @param surface LuaSurface The surface to scan
--- @return number Number of ghosts counted
local function scan_ghosts(surface)
    -- No area and no position means the entire surface.
    local ghosts = surface.find_entities_filtered{type = GHOST_TYPES}
    local surface_index = surface.index
    local counted = 0

    for _, ghost in pairs(ghosts) do
        if ghost.valid then
            local category = GHOST_TYPE_CATEGORY[ghost.type]
            local item_name = category and signal_utils.get_item_name_for_ghost(ghost)

            if item_name then
                local quality_name = ghost.quality and ghost.quality.name or "normal"

                gc_storage.increment(surface_index, category, item_name, quality_name)

                -- Re-registering an object that is already registered returns
                -- its EXISTING registration number, so this cannot create
                -- duplicates for ghosts the previous version already tracked.
                local registration_number = script.register_on_object_destroyed(ghost)
                local record = gc_storage.register_tracked_object(
                    registration_number, surface_index, category, item_name, quality_name)
                if record then
                    gc_networks.attach(record, ghost)
                end

                counted = counted + 1
            end
        end
    end

    return counted
end

--- Count every pending upgrade request on a surface
--- @param surface LuaSurface The surface to scan
--- @return number Number of upgrade requests counted
local function scan_upgrades(surface)
    local marked = surface.find_entities_filtered{to_be_upgraded = true}
    local surface_index = surface.index
    local counted = 0

    for _, entity in pairs(marked) do
        if entity.valid then
            -- Returns TWO values: the target prototype and its quality.
            local target, target_quality = entity.get_upgrade_target()

            local item_name = target and signal_utils.get_item_name_for_entity(target.name)
            if item_name then
                local quality_name = target_quality and target_quality.name or "normal"

                gc_storage.increment(surface_index, UPGRADE_CATEGORY, item_name, quality_name)

                local registration_number = script.register_on_object_destroyed(entity)
                local record = gc_storage.register_tracked_object(
                    registration_number, surface_index, UPGRADE_CATEGORY, item_name, quality_name)
                if record then
                    gc_networks.attach(record, entity)
                end

                counted = counted + 1
            end
        end
    end

    return counted
end

--- Discover every combinator on a surface and (re)register it
--- Preserves the mode and network filter of any combinator already known;
--- anything newly discovered gets DEFAULT_MODE ("builds") with the filter OFF,
--- which reproduces the pre-1.2.0 behavior exactly.
--- @param surface LuaSurface The surface to scan
--- @param surface_data table The surface data table
--- @return number Number of combinators registered
local function scan_combinators(surface, surface_data)
    -- Preserve modes of combinators we already know about. The type check
    -- matters: a save from before the mode feature stored a bare LuaEntity here,
    -- and reading `.mode` off a LuaEntity raises "doesn't contain key mode".
    -- get_surface_data normally upgrades those in place, but this must not
    -- depend on that having run.
    local existing_modes = {}
    local existing_filters = {}
    for unit_number, record in pairs(surface_data.combinators) do
        if type(record) == "table" and record.mode then
            existing_modes[unit_number] = record.mode
            existing_filters[unit_number] = record.network_filter == true
        end
    end

    -- Rebuild from scratch so stale references to destroyed entities are dropped.
    surface_data.combinators = {}

    local combinators = surface.find_entities_filtered{name = GHOST_COMBINATOR}
    local counted = 0

    for _, entity in pairs(combinators) do
        if entity.valid and entity.unit_number then
            local mode = existing_modes[entity.unit_number] or gc_storage.DEFAULT_MODE
            -- Explicit false, never nil: nil would apply DEFAULT_NETWORK_FILTER
            -- (on) to a combinator built before the setting existed.
            local network_filter = existing_filters[entity.unit_number] or false
            if gc_storage.register_combinator(entity, mode, network_filter) then
                counted = counted + 1
            end
        end
    end

    return counted
end

-----------------------------------------------------------
-- PUBLIC API
-----------------------------------------------------------

--- Rebuild all counters for a single surface
--- @param surface LuaSurface The surface to rescan
--- @return table Counts {ghosts, upgrades, combinators}
function rescan.rescan_surface(surface)
    local result = {ghosts = 0, upgrades = 0, combinators = 0}

    if not surface or not surface.valid then
        return result
    end

    local surface_data = reset_surface_categories(surface.index)
    if not surface_data then
        return result
    end

    result.ghosts = scan_ghosts(surface)
    result.upgrades = scan_upgrades(surface)
    result.combinators = scan_combinators(surface, surface_data)

    return result
end

--- Rebuild all counters on every surface
--- Wipes the registration table first so records left by a previous version
--- cannot double-count. Objects still alive are re-registered by the scans and
--- keep their original registration numbers.
---
--- IMPORTANT: this only rebuilds STORAGE. Combinator sections still hold their
--- pre-rescan slots, and the incremental tick pass will not clear them (it only
--- writes entries carrying `changed`, and a category that rescanned to empty has
--- none). Callers MUST follow this with a full resync - see the call sites in
--- mod/control.lua. Kept separate rather than calling control from here so this
--- module stays free of a control dependency.
--- @return table Totals {ghosts, upgrades, combinators, surfaces, elapsed_ticks}
function rescan.rescan_all()
    local started_at = game.tick

    gc_storage.init_storage()
    storage.ghost_registrations = {}

    local totals = {ghosts = 0, upgrades = 0, combinators = 0, surfaces = 0, elapsed_ticks = 0}

    for _, surface in pairs(game.surfaces) do
        local result = rescan.rescan_surface(surface)
        totals.ghosts = totals.ghosts + result.ghosts
        totals.upgrades = totals.upgrades + result.upgrades
        totals.combinators = totals.combinators + result.combinators
        totals.surfaces = totals.surfaces + 1
    end

    totals.elapsed_ticks = game.tick - started_at

    log(string.format(
        "[ghost_combinator] Rescan complete: %d surfaces, %d ghosts, %d upgrades, %d combinators (%d ticks)",
        totals.surfaces, totals.ghosts, totals.upgrades, totals.combinators, totals.elapsed_ticks))

    return totals
end

return rescan
