-- Ghost Combinator Mod - Main Control
-- Event registration and routing to entity-specific handlers
-- CRITICAL: Uses Factorio 2.0 APIs only!

local flib_gui = require("__flib__.gui")

-- Entity modules
local gc_control = require("scripts.ghost_combinator.control")
local gc_gui = require("scripts.ghost_combinator.gui")
local gc_rescan = require("scripts.ghost_combinator.rescan")
local gc_storage = require("scripts.ghost_combinator.storage")
local globals = require("scripts.globals")
local entity_lib = require("lib.entity_lib")
local circuit_utils = require("lib.circuit_utils")
local signal_utils = require("lib.signal_utils")

-- Entity name constants
local GHOST_COMBINATOR = "ghost-combinator"

-- Periodic tick intervals (in ticks; 60 ticks = 1 second)
local COMPACT_INTERVAL = 300   -- 5 seconds: remove zero-count ghosts & compress slots
local RESYNC_INTERVAL  = 600   -- 10 seconds: full resync of combinator outputs from storage

-- Register custom input handler for pipette tool on GUI signal buttons
script.on_event("gui-pipette-signal", function(event)
    -- Check if hovering over a signal sprite-button with signal data
    if event.element and event.element.tags and event.element.tags.signal_sel then
        local signal_id = event.element.tags.signal_sel
        local player = game.get_player(event.player_index)

        if not player then return end

        -- Convert signal_id to PipetteID format
        local pipette_id = signal_utils.signal_to_prototype(signal_id)

        if pipette_id then
            -- Try pipette with error handling
            pcall(function()
                player.pipette(pipette_id, signal_id.quality, true)
            end)
        end
    end
end)

-----------------------------------------------------------
-- LIFECYCLE EVENTS
-----------------------------------------------------------

script.on_init(function()
    log("[ghost-combinator] on_init")
    globals.init_storage()
end)

script.on_load(function()
    log("[ghost-combinator] on_load")
    -- No initialization needed on load - storage already exists
end)

script.on_configuration_changed(function(data)
    log("[ghost-combinator] on_configuration_changed")
    globals.init_storage()  -- Ensure storage tables exist

    -- Rebuild every counter from world truth when OUR mod version changes.
    --
    -- This is mandatory rather than optional: tracking is event-driven, so any
    -- demand that predates the new event handlers is invisible. It is also the
    -- only way an existing save learns about tile ghosts and upgrade requests,
    -- which were never counted before.
    --
    -- Gated on our own mod entry so unrelated mod updates in the same save do
    -- not pay the cost. Every combinator it finds is assigned the default
    -- "builds" mode, which reproduces the pre-mode behavior exactly.
    if data and data.mod_changes and data.mod_changes["ghost-combinator"] then
        gc_rescan.rescan_all()
        -- Rescan rebuilds storage only. Combinator sections still hold their old
        -- slots, and the incremental tick pass cannot clear them, so repaint
        -- every combinator from the fresh storage state immediately.
        gc_control.full_resync_all()
    end
end)

-- Surfaces can be deleted (space platforms especially). Drop their data so the
-- tick/compaction/resync loops stop iterating records for surfaces that are gone.
script.on_event(defines.events.on_surface_deleted, function(event)
    gc_storage.drop_surface(event.surface_index)
end)

script.on_event(defines.events.on_surface_cleared, function(event)
    gc_storage.drop_surface(event.surface_index)
end)

-----------------------------------------------------------
-- ENTITY BUILD/DESTROY EVENT ROUTING
-- CRITICAL: Ghost tracking requires NO filters (monitors all entities)
-- Combinator events use filters for performance
-----------------------------------------------------------

--- Unified handler for all entity build events
--- Routes to ghost tracking OR combinator creation based on entity type
--- @param event EventData Event data with entity and optional tags
local function on_entity_built(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    -- Route to appropriate handler based on entity type.
    -- CRITICAL: tile-ghost must be routed too, or the entire "tiles" category is
    -- dead - and worse, a rescan would populate it and register every tile ghost
    -- for destruction, so the counts would decay to zero and never recover.
    local entity_type = entity.type

    if entity_type == "entity-ghost" or entity_type == "tile-ghost" then
        -- Track ALL ghosts (no filter - this runs on every ghost built)
        gc_control.on_ghost_built(event)

        -- A ghost OF our combinator additionally carries blueprint config that
        -- needs storing on the ghost's tags.
        if entity_type == "entity-ghost" and entity.ghost_name == GHOST_COMBINATOR then
            gc_control.on_combinator_built(event)
        end
        return
    end

    if entity.name == GHOST_COMBINATOR then
        -- Handle combinator creation
        gc_control.on_combinator_built(event)
    end
end

--- Unified handler for all entity removal events
--- Only handles combinator cleanup - ghost tracking uses on_object_destroyed
--- @param event EventData Event data with entity
local function on_entity_removed(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    -- Only handle combinator destruction here
    -- Ghost tracking is handled by on_object_destroyed which fires for ALL
    -- destruction reasons including revive (ghost built into real entity)
    if entity.name == GHOST_COMBINATOR then
        gc_control.on_combinator_removed(event)
    end
end

-- Register build events WITHOUT filters to catch both ghosts and combinators.
--
-- DELIBERATE DEVIATION FROM FactorioBaseMod: the base filters these by
-- {filter="name"}/{filter="ghost_name"}. We cannot - demand tracking must
-- observe EVERY entity built, not just our own. The handlers do first-line type
-- rejection instead (see gc_control.on_ghost_built).
script.on_event(defines.events.on_built_entity, on_entity_built)
script.on_event(defines.events.on_robot_built_entity, on_entity_built)
script.on_event(defines.events.on_space_platform_built_entity, on_entity_built)
script.on_event(defines.events.script_raised_built, on_entity_built)
script.on_event(defines.events.script_raised_revive, on_entity_built)

-- Register destroy events for combinator cleanup only
-- Ghost entities are tracked via register_on_object_destroyed instead
script.on_event(defines.events.on_player_mined_entity, on_entity_removed)
script.on_event(defines.events.on_robot_mined_entity, on_entity_removed)
script.on_event(defines.events.on_space_platform_mined_entity, on_entity_removed)
script.on_event(defines.events.on_entity_died, on_entity_removed)
script.on_event(defines.events.script_raised_destroy, on_entity_removed)

-----------------------------------------------------------
-- UPGRADE REQUEST TRACKING
-- Unfiltered for the same reason as the build events: any entity on any
-- surface can be marked for upgrade.
-----------------------------------------------------------

script.on_event(defines.events.on_marked_for_upgrade, function(event)
    gc_control.on_marked_for_upgrade(event)
end)

script.on_event(defines.events.on_cancelled_upgrade, function(event)
    gc_control.on_cancelled_upgrade(event)
end)

-- Upgrading a GHOST replaces it rather than marking it, so it does not go
-- through on_marked_for_upgrade. Without this the replacement ghost is never
-- counted and the "builds" total drifts down by one per upgraded ghost.
script.on_event(defines.events.on_pre_ghost_upgraded, function(event)
    gc_control.on_pre_ghost_upgraded(event)
end)

-- Register on_object_destroyed for ghost tracking
-- This fires when ANY registered object is destroyed, including ghost revives
script.on_event(defines.events.on_object_destroyed, function(event)
    gc_control.on_object_destroyed(event)
end)

-----------------------------------------------------------
-- COMBINATOR-SPECIFIC EVENTS (WITH FILTERS)
-- These only apply to the ghost-combinator entity itself
-----------------------------------------------------------

-- Combinator event filter
local combinator_filter = {
    {filter = "name", name = GHOST_COMBINATOR},
    {filter = "ghost_name", name = GHOST_COMBINATOR}
}

-- Blueprint and copy-paste events for combinators only
script.on_event(defines.events.on_player_setup_blueprint, function(event)
    gc_control.on_player_setup_blueprint(event)
end)

-- NOTE: on_entity_settings_pasted does NOT support filtering in Factorio 2.0
script.on_event(defines.events.on_entity_settings_pasted, function(event)
    local source = event.source
    local destination = event.destination

    if not source or not source.valid then return end
    if not destination or not destination.valid then return end

    -- Only handle if one of them is our combinator
    if entity_lib.is_type(source, GHOST_COMBINATOR) or
       entity_lib.is_type(destination, GHOST_COMBINATOR) then
        gc_control.on_entity_settings_pasted(event)
    end
end)

script.on_event(defines.events.on_entity_cloned, function(event)
    local source = event.source
    local destination = event.destination

    if not source or not source.valid then return end
    if not destination or not destination.valid then return end

    -- Only handle if one of them is our combinator
    if entity_lib.is_type(source, GHOST_COMBINATOR) or
       entity_lib.is_type(destination, GHOST_COMBINATOR) then
        gc_control.on_entity_cloned(event)
    end
end, combinator_filter)

-----------------------------------------------------------
-- GUI EVENT ROUTING
-----------------------------------------------------------

-- Handle GUI opened events - let the GUI module decide if it's relevant
script.on_event(defines.events.on_gui_opened, function(event)
    gc_gui.on_gui_opened(event)
end)

-- Handle GUI closed events - let the GUI module decide if it's relevant
script.on_event(defines.events.on_gui_closed, function(event)
    gc_gui.on_gui_closed(event)
end)

-- Handle all GUI clicks - let the GUI module decide if it's relevant
script.on_event(defines.events.on_gui_click, function(event)
    gc_gui.on_gui_click(event)
end)

-- Handle all checkbox state changes - let the GUI module decide if it's relevant
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    gc_gui.on_gui_checked_state_changed(event)
end)

-- Handle dropdown selection changes - drives the output mode selector
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    gc_gui.on_gui_selection_state_changed(event)
end)

-----------------------------------------------------------
-- PERIODIC UPDATES
-----------------------------------------------------------

-- Every tick: Update combinator outputs if ghost counts changed
-- CRITICAL: This must be fast! Only processes combinators on surfaces with changes
script.on_event(defines.events.on_tick, function(event)
    gc_control.on_tick(event)
end)

-- Compact ghost slot assignments: remove zero-count ghosts and compress slot IDs
script.on_nth_tick(COMPACT_INTERVAL, function(event)
    gc_control.compact_ghost_slots(event)
end)

-- Full resync of combinator slots from storage truth (safety net for desyncs)
script.on_nth_tick(RESYNC_INTERVAL, function(event)
    gc_control.full_resync_all(event)
end)

-----------------------------------------------------------
-- DEBUG COMMANDS
-----------------------------------------------------------


-- /gc-ghost-state - Dumps the per-surface, per-category tracking state
commands.add_command("gc-ghost-state", "Dumps the ghost combinator tracking state", function(command)
    local player = game.get_player(command.player_index)
    if not player then return end

    if not storage.ghost_combinator then
        player.print("[Ghost Combinator] No data (storage.ghost_combinator is nil)")
        return
    end

    -- Build a summary structure (never print LuaEntity references directly)
    local summary = {}
    for surface_index, surface_data in pairs(storage.ghost_combinator) do
        local surface = game.surfaces[surface_index]
        local surface_name = surface and surface.name or ("surface_" .. surface_index)

        -- Combinators, grouped by the mode they output
        local combinators_by_mode = {}
        local combinator_count = 0
        if surface_data.combinators then
            for unit_number, record in pairs(surface_data.combinators) do
                -- type check guards against legacy bare-entity records
                local mode = (type(record) == "table" and record.mode) or "<legacy>"
                combinators_by_mode[mode] = combinators_by_mode[mode] or {}
                table.insert(combinators_by_mode[mode], unit_number)
                combinator_count = combinator_count + 1
            end
        end

        local categories = {}
        if surface_data.categories then
            for category_name, category in pairs(surface_data.categories) do
                local entry_count = 0
                for _ in pairs(category.entries) do
                    entry_count = entry_count + 1
                end

                categories[category_name] = {
                    entry_count = entry_count,
                    dirty = category.dirty,
                    next_slot = category.next_slot,
                    slot_high_water = category.slot_high_water,
                    entries = category.entries
                }
            end
        end

        summary[surface_name] = {
            surface_index = surface_index,
            combinator_count = combinator_count,
            combinators_by_mode = combinators_by_mode,
            last_compact_tick = surface_data.last_compact_tick,
            categories = categories
        }
    end

    -- Registration counts, broken down by category
    local registrations_by_category = {}
    local registration_total = 0
    if storage.ghost_registrations then
        for _, record in pairs(storage.ghost_registrations) do
            local category = record.category or "<none>"
            registrations_by_category[category] = (registrations_by_category[category] or 0) + 1
            registration_total = registration_total + 1
        end
    end
    summary._registrations = {
        total = registration_total,
        by_category = registrations_by_category
    }

    player.print("[Ghost Combinator] Tracking state:")
    player.print(serpent.block(summary))
end)

-- /gc-rescan - Rebuild every counter from world truth
-- Same code path the version-change migration uses. Repairs a save without
-- needing a mod update, and picks up anything that predates the mod.
commands.add_command("gc-rescan", "Rebuilds ghost combinator tracking from a full surface scan", function(command)
    local player = game.get_player(command.player_index)
    if not player then return end

    player.print("[Ghost Combinator] Rescanning all surfaces...")

    local totals = gc_rescan.rescan_all()

    -- Repaint every combinator from the rebuilt storage - see rescan_all's note.
    gc_control.full_resync_all()

    player.print(string.format(
        "[Ghost Combinator] Rescan complete: %d surfaces, %d ghosts, %d upgrade requests, %d combinators (%d ticks)",
        totals.surfaces, totals.ghosts, totals.upgrades, totals.combinators, totals.elapsed_ticks))
end)

-- /gc-ghost-clear [surface_id] - Clears tracking data for one surface, or all
-- NOTE: this only empties the counters. Use /gc-rescan to rebuild them.
commands.add_command("gc-ghost-clear", "Clears ghost tracking data. Usage: /gc-ghost-clear [surface_id]", function(command)
    local player = game.get_player(command.player_index)
    if not player then return end

    if not storage.ghost_combinator then
        player.print("[Ghost Combinator] No data to clear")
        return
    end

    local surface_id = nil
    if command.parameter and command.parameter ~= "" then
        surface_id = tonumber(command.parameter)
        if not surface_id then
            player.print("[Ghost Combinator] Invalid surface_id: " .. command.parameter)
            return
        end
    end

    --- Empty every category on one surface and rewrite its combinators
    --- @param surface_data table The surface record
    --- @return number Number of entries discarded
    local function clear_surface(surface_index, surface_data)
        local cleared = 0

        if surface_data.categories then
            for _, category in pairs(surface_data.categories) do
                for _ in pairs(category.entries) do
                    cleared = cleared + 1
                end
                category.entries = {}
                category.next_slot = 1
                category.slot_high_water = 0
                category.dirty = true
            end
        end

        return cleared
    end

    local total_cleared = 0
    local surfaces_cleared = 0

    if surface_id then
        local surface_data = storage.ghost_combinator[surface_id]
        if not surface_data then
            player.print("[Ghost Combinator] No data for surface " .. surface_id)
            return
        end

        total_cleared = clear_surface(surface_id, surface_data)
        surfaces_cleared = 1

        -- Drop registrations for this surface only
        local cleared_regs = 0
        if storage.ghost_registrations then
            for registration_number, record in pairs(storage.ghost_registrations) do
                if record.surface == surface_id then
                    storage.ghost_registrations[registration_number] = nil
                    cleared_regs = cleared_regs + 1
                end
            end
        end

        -- Emptying storage does not empty the combinators - the incremental pass
        -- has no `changed` entries left to act on. Repaint them now.
        gc_control.full_resync_all()

        player.print(string.format(
            "[Ghost Combinator] Cleared %d entries and %d registrations from surface %d",
            total_cleared, cleared_regs, surface_id))
    else
        for surface_index, surface_data in pairs(storage.ghost_combinator) do
            total_cleared = total_cleared + clear_surface(surface_index, surface_data)
            surfaces_cleared = surfaces_cleared + 1
        end

        local cleared_regs = 0
        if storage.ghost_registrations then
            for _ in pairs(storage.ghost_registrations) do
                cleared_regs = cleared_regs + 1
            end
            storage.ghost_registrations = {}
        end

        gc_control.full_resync_all()

        player.print(string.format(
            "[Ghost Combinator] Cleared %d entries and %d registrations from %d surfaces",
            total_cleared, cleared_regs, surfaces_cleared))
    end
end)
