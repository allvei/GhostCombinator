-- Ghost Combinator - Control Module
-- Entity lifecycle, demand tracking, and combinator output writing
-- CRITICAL: Performance-critical tracking paths - must be FAST!
--
-- Lifecycle handlers (on_built / on_removed / blueprint / paste / clone) follow
-- FactorioBaseMod's passthrough_combinator control module so this mod stays
-- consistent with its sibling mods.

local gc_storage = require("scripts.ghost_combinator.storage")
local gc_config = require("scripts.ghost_combinator.config")
local gc_networks = require("scripts.ghost_combinator.networks")
local globals = require("scripts.globals")
local entity_lib = require("lib.entity_lib")
local signal_utils = require("lib.signal_utils")

local control = {}

-- Entity name constant
local GHOST_COMBINATOR = "ghost-combinator"

--- Maps a ghost entity's prototype type to the demand category it feeds.
--- Used as the fast-rejection test on the build hot path: a nil lookup means
--- "not a ghost we track" and costs one hash probe.
local GHOST_TYPE_CATEGORY = {
    ["entity-ghost"] = "builds",
    ["tile-ghost"] = "tiles"
}

local UPGRADE_CATEGORY = "upgrades"

--- Stand-in entries table for a filtered combinator outside every network.
--- Never written to.
local NO_ENTRIES = {}

-----------------------------------------------------------
-- LOCAL HELPERS
-----------------------------------------------------------

--- Pick the CATEGORY a combinator record displays
--- Unfiltered -> the surface-wide category. Filtered -> its network's bucket,
--- or nil when it is outside every network (or nothing was counted there yet),
--- which callers render as "output nothing".
--- @param surface_data table The surface record
--- @param record table The combinator record
--- @return table|nil The CATEGORY table
local function source_category(surface_data, record)
    if record.network_filter then
        return gc_networks.get_category(surface_data, record.network_id, record.mode)
    end
    return surface_data.categories[record.mode]
end

--- Check whether a combinator record displays a given category/bucket
--- @param record table The combinator record
--- @param category_name string The category name
--- @param network_id number|nil The bucket's network id; nil = surface-wide
--- @return boolean True if the combinator shows this category
local function displays(record, category_name, network_id)
    if record.mode ~= category_name then
        return false
    end
    if network_id == nil then
        return not record.network_filter
    end
    return record.network_filter == true and record.network_id == network_id
end

--- Get an entity's quality name, defaulting to "normal"
--- @param entity LuaEntity The entity to read
--- @return string The quality name
local function quality_of(entity)
    return entity.quality and entity.quality.name or "normal"
end

--- Get or create logistic section 1 on a combinator
--- @param combinator LuaEntity The combinator entity
--- @return LuaLogisticSection|nil The section, or nil if unavailable
local function get_section(combinator)
    local cb = combinator.get_control_behavior()
    if not cb then
        log("[ghost_combinator] WARNING: Combinator has no control behavior")
        return nil
    end

    local section = cb.get_section(1)
    if not section then
        section = cb.add_section("")
        if not section then
            log("[ghost_combinator] WARNING: Could not create section for combinator")
            return nil
        end
    end

    return section
end

--- Build the LogisticFilter for an entry
--- CRITICAL: quality must be specified explicitly or Factorio rejects the filter
--- as "non-trivial".
--- @param entry table The category entry
--- @return table A LogisticFilter table
local function filter_for(entry)
    return {
        value = {
            type = "item",
            name = entry.item_name,
            quality = entry.quality or "normal"
        },
        min = entry.count
    }
end

--- Write every entry of a category into a combinator, clearing stale slots
--- Used when a combinator is first placed, when its mode changes, and on resync -
--- all cases where the per-entry `changed` flag cannot be trusted because the
--- combinator's current contents bear no relation to the category's entries.
--- @param combinator LuaEntity The combinator entity
--- @param entries table The category's entries table
--- @return boolean True if the write succeeded
local function write_all_slots(combinator, entries)
    if not combinator or not combinator.valid then
        return false
    end

    local section = get_section(combinator)
    if not section then
        return false
    end

    -- Wipe first: slot numbering differs per category, so anything already
    -- present is meaningless for the category we are about to write. This is why
    -- no slot ceiling needs to be tracked or passed in - the whole section goes.
    section.filters = {}

    for _, entry in pairs(entries) do
        if entry.count > 0 and entry.item_name then
            section.set_slot(entry.slot, filter_for(entry))
        end
    end

    return true
end

-----------------------------------------------------------
-- DEMAND TRACKING - GHOSTS AND TILE GHOSTS
-- CRITICAL: Called for ALL entity build events - must be FAST!
-----------------------------------------------------------

--- Count and register a ghost, unless it is already tracked
--- IDEMPOTENT: register_on_object_destroyed returns the SAME number for an
--- already-registered object, so an existing record proves we already counted
--- this ghost and we do nothing. That makes it safe to call from both the build
--- event and the deferred upgrade re-check without risking a double count.
--- @param entity LuaEntity The ghost entity
--- @return boolean True if the ghost was newly counted
local function track_ghost(entity)
    local category = entity and GHOST_TYPE_CATEGORY[entity.type]
    if not category then
        return false
    end

    -- Resolve the item that places this ghost. Handles both entity ghosts
    -- (straight-rail -> rail) and tile ghosts (stone-path -> stone-brick).
    local item_name = signal_utils.get_item_name_for_ghost(entity)
    if not item_name then
        -- No placing item (e.g. a script-created ghost for an item-less
        -- prototype). Skip entirely - do NOT register for destruction, or we
        -- would leave a registration record that can never be balanced.
        return false
    end

    -- Register for on_object_destroyed. This fires for ALL destruction reasons
    -- including revive (ghost built into a real entity), which is the most common
    -- way a ghost disappears and is NOT covered by the mined/died events.
    local registration_number = script.register_on_object_destroyed(entity)

    if gc_storage.get_tracked_object(registration_number) then
        return false  -- already counted
    end

    local surface_index = entity.surface.index
    local quality_name = quality_of(entity)

    gc_storage.increment(surface_index, category, item_name, quality_name)
    local record = gc_storage.register_tracked_object(
        registration_number, surface_index, category, item_name, quality_name)
    if record then
        gc_networks.attach(record, entity)
    end

    return true
end

--- Handle a ghost (entity-ghost or tile-ghost) being built
--- CRITICAL: This runs for EVERY entity built anywhere on the map. The category
--- lookup MUST be the first thing that happens so non-ghosts cost one hash probe.
--- @param event EventData Event data containing entity
function control.on_ghost_built(event)
    local entity = event.entity

    -- FAST rejection - single hash probe for the overwhelmingly common case
    if not entity or not GHOST_TYPE_CATEGORY[entity.type] then
        return
    end

    track_ghost(entity)
end

--- Handle an entity dying - count the ghost it left behind, if any
--- A ghost created by death raises NO build event, so without this every
--- entity destroyed by asteroids or biters is invisible (GitHub issue #4).
--- Runs for every death on the map: the ghost check is the first line.
--- @param event EventData.on_post_entity_died
function control.on_post_entity_died(event)
    local ghost = event.ghost
    if not ghost or not ghost.valid then
        return
    end

    track_ghost(ghost)
end

--- Handle a ghost being upgraded (upgrade planner dragged over ghosts)
--- The engine destroys the old ghost and creates a replacement. The destruction
--- balances itself via on_object_destroyed, but the replacement may not raise a
--- build event, which would leave it uncounted forever. Record the position and
--- re-check it next tick; track_ghost's idempotency makes this safe even if a
--- build event DID fire.
--- @param event EventData.on_pre_ghost_upgraded
function control.on_pre_ghost_upgraded(event)
    local ghost = event.ghost
    if not ghost or not ghost.valid then
        return
    end

    if not GHOST_TYPE_CATEGORY[ghost.type] then
        return
    end

    gc_storage.queue_pending_ghost(ghost.surface.index, ghost.position)
end

--- Re-check positions where a ghost was upgraded last tick
--- Called at the top of on_tick.
function control.process_pending_ghosts()
    local pending = gc_storage.take_pending_ghosts()

    for _, item in ipairs(pending) do
        local surface = game.surfaces[item.surface]
        if surface and surface.valid then
            local found = surface.find_entities_filtered{
                position = item.position,
                type = {"entity-ghost", "tile-ghost"}
            }
            for _, ghost in pairs(found) do
                if ghost.valid then
                    track_ghost(ghost)
                end
            end
        end
    end
end

--- Handle a tracked object being destroyed
--- Balances whatever the registration record says this object contributed.
--- @param event EventData.on_object_destroyed
function control.on_object_destroyed(event)
    local registration_number = event.registration_number

    local record = gc_storage.get_tracked_object(registration_number)
    if not record then
        return
    end

    -- Consume the record BEFORE decrementing. This is what makes the decrement
    -- idempotent across the overlapping upgrade paths (cancel / complete / mine):
    -- whichever fires first takes the record, and any later path finds nothing.
    gc_storage.unregister_tracked_object(registration_number)

    gc_storage.decrement(record.surface, record.category, record.item_name, record.quality)
    gc_networks.detach(record)
end

-----------------------------------------------------------
-- DEMAND TRACKING - UPGRADE REQUESTS
-----------------------------------------------------------

--- Handle an entity being marked for upgrade
--- @param event EventData.on_marked_for_upgrade
function control.on_marked_for_upgrade(event)
    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    -- Ghosts marked for upgrade go through on_pre_ghost_upgraded instead, which
    -- replaces the ghost rather than marking it. Counting them here would
    -- double-count against the "builds" entry the ghost already owns, and both
    -- would share one registration number.
    if entity_lib.is_ghost(entity) then
        return
    end

    local surface_index = entity.surface.index

    -- Take the registration number up front. Registering an already-registered
    -- object returns the SAME number, so this both identifies an existing record
    -- and creates one we can attach to.
    local registration_number = script.register_on_object_destroyed(entity)

    -- A re-mark overwrites this entity's record below. Pull the old demand out
    -- of its network buckets first, or those buckets would leak one count.
    local existing = gc_storage.get_tracked_object(registration_number)
    if existing then
        gc_networks.detach(existing)
    end

    -- previous_target/previous_quality are set when the entity was ALREADY
    -- marked and is being re-marked at a different target. Undo the old demand
    -- before adding the new one, or the counts drift upward on every re-mark.
    -- NOTE: these two fields are Factorio 2.1+ only (absent through 2.0.60).
    local previous_target = event.previous_target
    if previous_target then
        local previous_item = signal_utils.get_item_name_for_entity(previous_target.name)
        if previous_item then
            local previous_quality = event.previous_quality and event.previous_quality.name or "normal"
            gc_storage.decrement(surface_index, UPGRADE_CATEGORY, previous_item, previous_quality)
        end
    end

    -- CRITICAL: every bail-out below must drop the record. We may have just
    -- decremented the previous target; leaving the old record in place would let
    -- on_object_destroyed decrement it a SECOND time when the entity dies,
    -- drifting that item's count down permanently.
    local target = event.target
    if not target then
        gc_storage.unregister_tracked_object(registration_number)
        return
    end

    local item_name = signal_utils.get_item_name_for_entity(target.name)
    if not item_name then
        gc_storage.unregister_tracked_object(registration_number)
        return
    end

    local quality_name = event.quality and event.quality.name or "normal"
    gc_storage.increment(surface_index, UPGRADE_CATEGORY, item_name, quality_name)

    -- Overwrites this entity's own record in place rather than creating a second.
    local record = gc_storage.register_tracked_object(
        registration_number, surface_index, UPGRADE_CATEGORY, item_name, quality_name)
    if record then
        gc_networks.attach(record, entity)
    end
end

--- Handle an upgrade order being cancelled
--- @param event EventData.on_cancelled_upgrade
function control.on_cancelled_upgrade(event)
    local entity = event.entity
    if not entity or not entity.valid then
        return
    end

    if entity_lib.is_ghost(entity) then
        return
    end

    -- We need this entity's registration number to consume its record. Calling
    -- register_on_object_destroyed again is documented to return the SAME number
    -- for an already-registered object, so this is a lookup, not a new
    -- registration, for every entity we actually marked.
    local registration_number = script.register_on_object_destroyed(entity)

    local record = gc_storage.get_tracked_object(registration_number)
    if not record or record.category ~= UPGRADE_CATEGORY then
        -- Never tracked (e.g. marked before this mod was installed and not yet
        -- rescanned), or the record belongs to a different category. Nothing to
        -- undo - decrementing from the event's target here would corrupt counts.
        return
    end

    gc_storage.unregister_tracked_object(registration_number)
    gc_storage.decrement(record.surface, record.category, record.item_name, record.quality)
    gc_networks.detach(record)
end

-----------------------------------------------------------
-- COMBINATOR LIFECYCLE
-- Follows FactorioBaseMod's on_built / on_removed shape
-----------------------------------------------------------

--- Shared handler for combinator build events
--- Handles both real entities and ghosts, with blueprint tag support
--- @param event EventData Event data containing entity and optional tags
function control.on_combinator_built(event)
    local entity = event.entity
    local tags = event.tags

    if not entity or not entity.valid then
        return
    end

    -- Ghosts carry their config in tags, never in storage
    if entity_lib.is_ghost(entity) then
        if entity_lib.is_type(entity, GHOST_COMBINATOR) then
            if tags and tags[gc_storage.CONFIG_TAG] then
                gc_config.save_ghost_config(entity, tags[gc_storage.CONFIG_TAG])
            end
        end
        return
    end

    -- Only handle our entity
    if entity.name ~= GHOST_COMBINATOR then
        return
    end

    -- Restore the config from blueprint tags if the ghost carried one
    local tagged = tags and tags[gc_storage.CONFIG_TAG]
    local mode = gc_storage.DEFAULT_MODE
    if tagged and gc_storage.is_valid_mode(tagged.mode) then
        mode = tagged.mode
    end

    local record = gc_storage.register_combinator(entity, mode, gc_config.network_filter_from_config(tagged))
    if not record then
        log("[ghost_combinator] ERROR: Failed to register combinator")
        return
    end

    -- Populate immediately with the full category contents. A dirty flag alone
    -- is not enough: the tick loop only writes entries whose `changed` flag is
    -- set, and a surface whose counts are all settled has none - a newly placed
    -- combinator would stay blank until the next resync.
    control.refresh_combinator(entity, mode)
end

--- Shared handler for combinator removal events
--- @param event EventData Event data containing entity
function control.on_combinator_removed(event)
    local entity = event.entity

    if not entity or not entity.valid then
        return
    end

    if not entity_lib.is_type(entity, GHOST_COMBINATOR) then
        return
    end

    -- Ghost destruction needs no storage cleanup - ghosts never registered
    if entity_lib.is_ghost(entity) then
        return
    end

    local unit_number = entity.unit_number
    if not unit_number then
        return
    end

    -- Close any open GUIs for this entity
    globals.cleanup_player_gui_states_for_entity(entity, "ghost_combinator_gui")

    gc_storage.unregister_combinator(unit_number, entity.surface.index)
end

--- Re-resolve a filtered combinator's network, caching it on the record
--- @param record table The combinator record
--- @return boolean True if the cached network id changed
local function update_network_id(record)
    if not record.network_filter then
        return false
    end

    local network_id = gc_networks.find_combinator_network_id(record.entity)
    if network_id == record.network_id then
        return false
    end

    record.network_id = network_id
    return true
end

--- Rewrite one combinator's output from scratch
--- Called on placement and whenever the mode or network filter changes.
--- @param entity LuaEntity The combinator entity
--- @param mode string|nil Unused; the record's mode is authoritative. Kept for callers.
--- @return boolean True if the write succeeded
function control.refresh_combinator(entity, mode)
    if not entity or not entity.valid then
        return false
    end

    local surface_data = gc_storage.get_surface_data(entity.surface.index)
    local record = gc_storage.get_combinator_record(entity)
    if not surface_data or not record then
        return false
    end

    update_network_id(record)

    local category = source_category(surface_data, record)
    return write_all_slots(entity, category and category.entries or NO_ENTRIES)
end

--- Get the entries a combinator (or its ghost) currently displays
--- For the GUI. Mirrors source_category, but also works for ghosts and for
--- combinators whose storage record is missing, by reading config directly.
--- @param entity LuaEntity The combinator or combinator ghost
--- @return table Entries table (key -> entry); empty if nothing to show
function control.get_display_entries(entity)
    if not entity or not entity.valid then
        return NO_ENTRIES
    end

    local surface_data = gc_storage.get_surface_data(entity.surface.index)
    if not surface_data then
        return NO_ENTRIES
    end

    local mode = gc_config.get_mode(entity)
    local category
    if gc_config.get_network_filter(entity) then
        local network_id = gc_networks.find_combinator_network_id(entity)
        category = gc_networks.get_category(surface_data, network_id, mode)
    else
        category = surface_data.categories[mode]
    end

    return category and category.entries or NO_ENTRIES
end

-----------------------------------------------------------
-- TICK HANDLERS
-----------------------------------------------------------

--- Clear a category's per-entry and category-level dirty flags
--- @param category table A CATEGORY table
local function clear_changed(category)
    for _, entry in pairs(category.entries) do
        entry.changed = false
    end
    category.dirty = false
end

--- Push a dirty category (surface-wide or network bucket) to its combinators
--- Only clears flags when EVERY combinator took the update. If one failed,
--- they stay set so the next tick retries.
--- @param surface_data table The surface record
--- @param category_name string The category name
--- @param category table The CATEGORY table
--- @param network_id number|nil The bucket's network id; nil = surface-wide
local function flush_category(surface_data, category_name, category, network_id)
    if category.dirty
        and control.update_combinators_for_category(surface_data, category_name, category, network_id) then
        clear_changed(category)
    end
end

--- Per-tick incremental update
--- Walks each surface's categories and network buckets and writes only the
--- entries that changed, and only to the combinators displaying them.
--- @param event EventData.on_tick
function control.on_tick(event)
    -- Pick up replacement ghosts created by an upgrade last tick
    control.process_pending_ghosts()

    if not storage.ghost_combinator then
        return
    end

    for _, surface_data in pairs(storage.ghost_combinator) do
        local categories = surface_data.categories
        if categories then
            for category_name, category in pairs(categories) do
                flush_category(surface_data, category_name, category, nil)
            end
        end

        local buckets = surface_data.networks
        if buckets then
            for network_id, bucket in pairs(buckets) do
                for category_name, category in pairs(bucket.categories) do
                    flush_category(surface_data, category_name, category, network_id)
                end
            end
        end
    end
end

--- Push changed entries of one category to the combinators displaying it
--- @param surface_data table The surface data table
--- @param category_name string The category being updated
--- @param category table The category record
--- @param network_id number|nil The bucket's network id; nil = surface-wide
--- @return boolean True if all matching combinators were updated
function control.update_combinators_for_category(surface_data, category_name, category, network_id)
    local combinators = surface_data.combinators
    if not combinators then
        return true
    end

    local all_succeeded = true

    for unit_number, record in pairs(combinators) do
        local entity = record and record.entity

        if not entity or not entity.valid then
            combinators[unit_number] = nil
        elseif displays(record, category_name, network_id) then
            if not control.write_changed_slots(entity, category.entries) then
                all_succeeded = false
            end
        end
    end

    return all_succeeded
end

--- Write only the changed entries of a category into one combinator
--- @param combinator LuaEntity The combinator entity
--- @param entries table The category's entries
--- @return boolean True if the write succeeded
function control.write_changed_slots(combinator, entries)
    if not combinator or not combinator.valid then
        return false
    end

    local section = get_section(combinator)
    if not section then
        return false
    end

    for _, entry in pairs(entries) do
        if entry.changed then
            if entry.count > 0 and entry.item_name then
                section.set_slot(entry.slot, filter_for(entry))
            else
                section.clear_slot(entry.slot)
            end
        end
    end

    return true
end

-----------------------------------------------------------
-- PERIODIC COMPACTION
-----------------------------------------------------------

--- Compact one category (surface-wide or bucket) and rewrite its combinators
--- @param surface_data table The surface record
--- @param category_name string The category name
--- @param category table The CATEGORY table
--- @param network_id number|nil The bucket's network id; nil = surface-wide
local function compact_and_rewrite(surface_data, category_name, category, network_id)
    local removed = gc_storage.compact_category(category)

    -- Compaction renumbers slots, so every combinator on this category must be
    -- rewritten wholesale, not incrementally.
    if removed == 0 then
        return
    end

    local all_succeeded = true

    for unit_number, record in pairs(surface_data.combinators) do
        local entity = record and record.entity
        if not entity or not entity.valid then
            surface_data.combinators[unit_number] = nil
        elseif displays(record, category_name, network_id) then
            if not write_all_slots(entity, category.entries) then
                all_succeeded = false
            end
        end
    end

    -- Clear the flags only if EVERY combinator took the rewrite, matching
    -- on_tick. Clearing them after a partial failure would strand that
    -- combinator with nothing left to re-mark it, leaving it stale until the
    -- next full resync.
    if all_succeeded then
        clear_changed(category)
    end

    gc_storage.reset_category_high_water(category)
end

--- Remove zero-count entries and close slot gaps, per category and bucket
--- Also drops network buckets left with no entries (networks that merged,
--- split or were torn down).
--- @param event EventData.on_nth_tick
function control.compact_ghost_slots(event)
    if not storage.ghost_combinator then
        return
    end

    for surface_index, surface_data in pairs(storage.ghost_combinator) do
        gc_storage.set_last_compact_tick(surface_index, event.tick)

        local categories = surface_data.categories
        if categories then
            for category_name, category in pairs(categories) do
                compact_and_rewrite(surface_data, category_name, category, nil)
            end
        end

        local buckets = surface_data.networks
        if buckets then
            for network_id, bucket in pairs(buckets) do
                for category_name, category in pairs(bucket.categories) do
                    compact_and_rewrite(surface_data, category_name, category, network_id)
                end
                -- Assigning nil to the current key is legal during pairs().
                if gc_networks.is_bucket_empty(bucket) then
                    buckets[network_id] = nil
                end
            end
        end
    end
end

-----------------------------------------------------------
-- PERIODIC FULL RESYNC
-- Safety net: rewrites every combinator from storage truth, catching any
-- desync left by a failed incremental write.
-----------------------------------------------------------

--- Rewrite all combinators on one surface from storage
--- @param surface_index number The surface index
--- @param surface_data table The surface data table
function control.full_resync_surface(surface_index, surface_data)
    local combinators = surface_data.combinators
    local categories = surface_data.categories
    if not combinators or not categories then
        return
    end

    local all_succeeded = true

    for unit_number, record in pairs(combinators) do
        local entity = record and record.entity

        if not entity or not entity.valid then
            combinators[unit_number] = nil
        else
            -- Resync is also where filtered combinators notice their network
            -- changed id (roboports built/removed, networks merged or split).
            update_network_id(record)

            local category = source_category(surface_data, record)
            if not write_all_slots(entity, category and category.entries or NO_ENTRIES) then
                all_succeeded = false
            end
        end
    end

    -- A successful resync IS a sync point: every combinator now matches storage
    -- exactly, so nothing needs rewriting on the next tick. Leaving the flags set
    -- would make the tick pass redundantly rewrite everything we just wrote.
    -- On partial failure the flags stay, so the next tick retries.
    local buckets = surface_data.networks

    if all_succeeded then
        for _, category in pairs(categories) do
            clear_changed(category)
        end
        if buckets then
            for _, bucket in pairs(buckets) do
                for _, category in pairs(bucket.categories) do
                    clear_changed(category)
                end
            end
        end
    end

    for _, category in pairs(categories) do
        gc_storage.reset_category_high_water(category)
    end
    if buckets then
        for _, bucket in pairs(buckets) do
            for _, category in pairs(bucket.categories) do
                gc_storage.reset_category_high_water(category)
            end
        end
    end
end

--- Full resync of every surface - entry point for the on_nth_tick handler
--- @param event EventData.on_nth_tick
function control.full_resync_all(event)
    if not storage.ghost_combinator then
        return
    end

    for surface_index, surface_data in pairs(storage.ghost_combinator) do
        control.full_resync_surface(surface_index, surface_data)
    end
end

-----------------------------------------------------------
-- BLUEPRINT AND COPY-PASTE
-- Taken from FactorioBaseMod's passthrough_combinator control module
-----------------------------------------------------------

--- Handle entity settings pasted (Shift+Right Click / Shift+Left Click)
--- @param event EventData.on_entity_settings_pasted
function control.on_entity_settings_pasted(event)
    local source = event.source
    local destination = event.destination

    if not source or not source.valid then return end
    if not destination or not destination.valid then return end

    if not entity_lib.is_type(source, GHOST_COMBINATOR) then return end
    if not entity_lib.is_type(destination, GHOST_COMBINATOR) then return end

    local source_config = gc_config.serialize_config(source)
    if not source_config then
        log("[ghost_combinator] WARNING: Could not serialize source config")
        return
    end

    gc_config.restore_config(destination, source_config)

    -- Slot numbering differs per category, so the destination's output must be
    -- rebuilt rather than incrementally patched.
    if not entity_lib.is_ghost(destination) then
        control.refresh_combinator(destination)
    end
end

--- Handle entity cloned (editor, or another mod)
--- @param event EventData.on_entity_cloned
function control.on_entity_cloned(event)
    local source = event.source
    local destination = event.destination

    if not source or not source.valid then return end
    if not destination or not destination.valid then return end

    if not entity_lib.is_type(source, GHOST_COMBINATOR) then return end
    if not entity_lib.is_type(destination, GHOST_COMBINATOR) then return end

    local source_config = gc_config.serialize_config(source)
    if not source_config then
        log("[ghost_combinator] WARNING: Could not get source config for cloning")
        return
    end

    gc_config.restore_config(destination, source_config)

    if not entity_lib.is_ghost(destination) then
        control.refresh_combinator(destination)
    end
end

--- Handle blueprint creation - save each combinator's mode into blueprint tags
--- @param event EventData.on_player_setup_blueprint
function control.on_player_setup_blueprint(event)
    -- record is the blueprint-library case and is writable; stack is the
    -- held-item case. Handling only `stack` silently drops the config for
    -- library blueprints.
    local bp = event.record or event.stack
    if not bp then return end

    local entities = bp.get_blueprint_entities()
    if not entities then return end

    local mapping = event.mapping
    if not mapping then return end

    local mapped_entities = mapping.get()
    if not mapped_entities then return end

    for bp_index, bp_entity in ipairs(entities) do
        if bp_entity.name == GHOST_COMBINATOR then
            local real_entity = mapped_entities[bp_index]

            if real_entity and real_entity.valid then
                local config = gc_config.serialize_config(real_entity)
                if config then
                    bp.set_blueprint_entity_tags(bp_index, {[gc_storage.CONFIG_TAG] = config})
                end
            end
        end
    end
end

return control
