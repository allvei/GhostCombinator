-- Ghost Combinator - Storage Module
-- Manages per-surface, per-category demand counters and combinator registration
-- CRITICAL: Uses Factorio 2.0+ APIs - storage NOT global!
--
-- ============================================================================
-- STORAGE STRUCTURE
-- ============================================================================
-- storage.ghost_combinator = {
--     [surface_index] = {
--         categories = {
--             builds   = CATEGORY,  -- entity-ghost      (default mode)
--             tiles    = CATEGORY,  -- tile-ghost
--             upgrades = CATEGORY,  -- entities marked for upgrade
--         },
--         combinators = {
--             [unit_number] = {
--                 entity         = LuaEntity,
--                 mode           = "builds",
--                 network_filter = true|nil,  -- nil/false = surface-wide (pre-1.2.0)
--                 network_id     = N|nil,     -- cached; owned by networks.lua
--             },
--         },
--         networks = {                         -- owned by networks.lua
--             [network_id] = { categories = { builds = CATEGORY, ... } },
--         },
--         last_compact_tick = 0,
--     }
-- }
--
-- CATEGORY = {
--     entries = {
--         ["<item_name>:<quality>"] = {
--             count     = N,
--             slot      = M,          -- logistic section slot index
--             changed   = true/false, -- dirty flag, drives incremental writes
--             item_name = "iron-chest",
--             quality   = "normal",
--         },
--     },
--     dirty           = false,  -- category-level dirty flag
--     next_slot       = 1,
--     slot_high_water = 0,      -- highest slot ever assigned (bounds orphan clearing)
-- }
--
-- WHY PER-CATEGORY SLOTS: every combinator writes ONE category into its logistic
-- section, numbered 1..N from that category's entries. Two combinators in different
-- modes therefore need independent slot spaces. Only `entries`, `dirty`, `next_slot`
-- and `slot_high_water` are per-category - the combinator list and compaction
-- timestamp stay surface-level, and every function below is parameterized by
-- category rather than duplicated.
--
-- KEYED BY ITEM, NOT ENTITY: entity names don't always match item names
-- (e.g. "straight-rail" -> "rail", tile "stone-path" -> item "stone-brick").
-- Callers resolve the placing item via signal_utils BEFORE calling increment/
-- decrement, so this module performs no prototype lookups on the hot path.
--
-- storage.ghost_registrations = {
--     [registration_number] = {
--         surface   = surface_index,
--         category  = "builds" | "tiles" | "upgrades",
--         item_name = "iron-chest",  -- resolved at register time
--         quality   = "normal",
--         position  = {x, y},        -- set by networks.attach
--         force     = force_index,   -- set by networks.attach
--         networks  = {id, ...}|nil, -- network buckets this object is counted in
--     }
-- }
-- Tracks objects registered with script.register_on_object_destroyed so the
-- decrement knows what to undo without re-resolving prototypes.

local entity_lib = require("lib.entity_lib")

local gc_storage = {}

-- Entity name constant
local GHOST_COMBINATOR = "ghost-combinator"

-- Blueprint/ghost tag key. Follows the FactorioBaseMod convention of
-- "<entity_name>_config" so it cannot collide with other mods' tags.
local CONFIG_TAG = "ghost_combinator_config"
gc_storage.CONFIG_TAG = CONFIG_TAG

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

--- Ordered list of output categories. Order drives GUI dropdown index <-> mode.
--- Bound locally and re-exported, matching the family's constant style - these
--- are read on the increment/decrement hot path, so they must not cost a table
--- indirection through the module table on every call.
local CATEGORIES = {"builds", "tiles", "upgrades"}
gc_storage.CATEGORIES = CATEGORIES

--- Default mode for new and migrated combinators.
--- CRITICAL: must stay "builds" - that reproduces the pre-mode behavior exactly,
--- so updating an existing save never silently changes what a combinator reports.
local DEFAULT_MODE = "builds"
gc_storage.DEFAULT_MODE = DEFAULT_MODE

local VALID_MODES = {builds = true, tiles = true, upgrades = true}

--- Network filter for NEWLY placed combinators. Existing combinators have no
--- `network_filter` field, which reads as off, so an update never changes what
--- an already-built combinator reports.
gc_storage.DEFAULT_NETWORK_FILTER = true

--- Check whether a string is a valid output mode
--- @param mode string|nil The mode to validate
--- @return boolean True if the mode is one of the known categories
function gc_storage.is_valid_mode(mode)
    return mode ~= nil and VALID_MODES[mode] == true
end

--- Convert a mode to its index in CATEGORIES (for GUI dropdowns)
--- @param mode string The mode name
--- @return number The 1-based index, defaulting to the DEFAULT_MODE index
function gc_storage.mode_to_index(mode)
    for index, name in ipairs(CATEGORIES) do
        if name == mode then
            return index
        end
    end
    return 1  -- CATEGORIES[1] is DEFAULT_MODE
end

--- Convert a GUI dropdown index back to a mode name
--- @param index number The 1-based dropdown index
--- @return string The mode name, defaulting to DEFAULT_MODE
function gc_storage.index_to_mode(index)
    return CATEGORIES[index] or DEFAULT_MODE
end

--- Build an empty category record
--- @return table A fresh CATEGORY table
local function new_category()
    return {
        entries = {},
        dirty = false,
        next_slot = 1,
        slot_high_water = 0
    }
end
gc_storage.new_category = new_category

--------------------------------------------------------------------------------
-- Storage Initialization
--------------------------------------------------------------------------------

--- Initialize ghost combinator storage tables
--- Called during on_init and on_configuration_changed events
function gc_storage.init_storage()
    storage.ghost_combinator = storage.ghost_combinator or {}
    storage.ghost_registrations = storage.ghost_registrations or {}
    storage.pending_ghost_upgrades = storage.pending_ghost_upgrades or {}
    -- Re-bucket cursor, owned by networks.lua. Initialized here so there is a
    -- single init path reachable from globals.init_storage().
    storage.gc_rebucket = storage.gc_rebucket or {keys = {}, index = 1, next_cycle_tick = 0}
end

--------------------------------------------------------------------------------
-- Pending Ghost Upgrades
--------------------------------------------------------------------------------
-- Upgrading a ghost destroys it and creates a replacement. The destruction is
-- observable (on_object_destroyed), but the replacement may not raise a build
-- event, which would leave it permanently uncounted. We record the position at
-- upgrade time and re-check it on the next tick.

--- Queue a position to re-check for an untracked ghost next tick
--- @param surface_index number The surface index
--- @param position MapPosition Where the upgraded ghost was
function gc_storage.queue_pending_ghost(surface_index, position)
    if not surface_index or not position then
        return
    end

    if not storage.pending_ghost_upgrades then
        storage.pending_ghost_upgrades = {}
    end

    storage.pending_ghost_upgrades[#storage.pending_ghost_upgrades + 1] = {
        surface = surface_index,
        position = {x = position.x, y = position.y}
    }
end

--- Take and clear the pending queue
--- @return table Array of {surface, position} (empty if none)
function gc_storage.take_pending_ghosts()
    local pending = storage.pending_ghost_upgrades
    if not pending or #pending == 0 then
        return {}
    end

    storage.pending_ghost_upgrades = {}
    return pending
end

--------------------------------------------------------------------------------
-- Surface / Category Access
--------------------------------------------------------------------------------

--- Bring a surface record up to the current schema, in place
--- Handles records written by the pre-category version of this mod:
---   * combinators[unit_number] was a bare LuaEntity, now {entity, mode}
---   * counters lived in surface_data.ghosts at surface level
--- CRITICAL: without the combinator conversion, `record.mode` on a bare
--- LuaEntity raises "LuaEntity doesn't contain key mode" - a hard crash the
--- first time an old save opens the GUI or runs cleanup.
--- @param surface_data table The surface record to upgrade
local function ensure_schema(surface_data)
    surface_data.categories = surface_data.categories or {}
    surface_data.combinators = surface_data.combinators or {}

    for _, category in ipairs(CATEGORIES) do
        if not surface_data.categories[category] then
            surface_data.categories[category] = new_category()
        end
    end

    -- Legacy combinator values were bare LuaEntity references
    for unit_number, record in pairs(surface_data.combinators) do
        if type(record) ~= "table" then
            surface_data.combinators[unit_number] = {
                entity = record,
                mode = DEFAULT_MODE
            }
        end
    end

    -- Drop orphaned pre-category fields. The counts they held are rebuilt from
    -- world truth by the rescan, so carrying them forward would only leave two
    -- competing schemas in the save.
    if surface_data.ghosts ~= nil then
        surface_data.ghosts = nil
        surface_data.any_changes = nil
        surface_data.next_slot = nil
        surface_data.slot_high_water = nil
    end
end

--- Look up surface data WITHOUT creating it
--- Read paths must use this: creating on read would resurrect records for
--- deleted surfaces (a destroyed space platform still has queued
--- on_object_destroyed events), and inserting a new key while a caller iterates
--- storage.ghost_combinator raises "invalid key to 'next'".
--- @param surface_index number The surface index
--- @return table|nil Surface data table, or nil if it does not exist
local function peek_surface_data(surface_index)
    if not surface_index or not storage.ghost_combinator then
        return nil
    end

    local surface_data = storage.ghost_combinator[surface_index]
    if not surface_data then
        return nil
    end

    ensure_schema(surface_data)
    return surface_data
end

--- Get or create surface data, ensuring all categories exist
--- Only write paths (increment, register_combinator) should create.
--- @param surface_index number The surface index
--- @return table|nil Surface data table, or nil if surface_index is missing
function gc_storage.get_surface_data(surface_index)
    if not surface_index then
        log("[ghost_combinator] ERROR: get_surface_data called with nil surface_index")
        return nil
    end

    if not storage.ghost_combinator then
        gc_storage.init_storage()
    end

    local surface_data = storage.ghost_combinator[surface_index]

    if not surface_data then
        surface_data = {
            categories = {},
            combinators = {},
            last_compact_tick = 0
        }
        storage.ghost_combinator[surface_index] = surface_data
    end

    ensure_schema(surface_data)

    return surface_data
end

--- Discard a surface's data entirely (surface deleted/cleared)
--- @param surface_index number The surface index
function gc_storage.drop_surface(surface_index)
    if not surface_index or not storage.ghost_combinator then
        return
    end

    storage.ghost_combinator[surface_index] = nil

    -- Purge registrations pointing at the dead surface so they cannot decrement
    -- into a resurrected record later.
    if storage.ghost_registrations then
        for registration_number, record in pairs(storage.ghost_registrations) do
            if record.surface == surface_index then
                storage.ghost_registrations[registration_number] = nil
            end
        end
    end
end

--- Get a specific category record for a surface, WITHOUT creating it
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
--- @return table|nil The CATEGORY table, or nil if it does not exist
function gc_storage.get_category(surface_index, category)
    if not VALID_MODES[category] then
        return nil
    end

    local surface_data = peek_surface_data(surface_index)
    if not surface_data then
        return nil
    end

    return surface_data.categories[category]
end

--------------------------------------------------------------------------------
-- Combinator Registration
--------------------------------------------------------------------------------

--- Register a ghost combinator entity in storage
--- CRITICAL: Only register real entities, NEVER ghosts! Ghosts carry their config
--- in entity.tags instead (see save_ghost_config).
--- @param entity LuaEntity The combinator entity to register
--- @param mode string|nil Output mode; defaults to DEFAULT_MODE
--- @param network_filter boolean|nil Network filter; nil keeps the existing value,
---        or DEFAULT_NETWORK_FILTER for a combinator not registered before
--- @return table|nil The combinator record, or nil if registration failed
function gc_storage.register_combinator(entity, mode, network_filter)
    if not entity or not entity.valid then
        log("[ghost_combinator] ERROR: Attempted to register invalid ghost combinator")
        return nil
    end

    if entity_lib.is_ghost(entity) then
        log("[ghost_combinator] ERROR: Attempted to register ghost entity - ghosts use entity.tags, not storage!")
        return nil
    end

    if not entity_lib.is_type(entity, GHOST_COMBINATOR) then
        log("[ghost_combinator] ERROR: Attempted to register non-ghost-combinator entity: " .. tostring(entity.name))
        return nil
    end

    local unit_number = entity.unit_number
    if not unit_number then
        log("[ghost_combinator] ERROR: Ghost combinator has no unit_number")
        return nil
    end

    local surface_index = entity.surface.index
    local surface_data = gc_storage.get_surface_data(surface_index)
    if not surface_data then
        return nil
    end

    local existing = surface_data.combinators[unit_number]

    if not gc_storage.is_valid_mode(mode) then
        -- No explicit mode: keep whatever this combinator already had. Build-ish
        -- events can fire more than once for one entity (another mod raising
        -- script_raised_built, or a re-register after restore_config), and
        -- defaulting here would silently revert a player-configured combinator
        -- back to "builds".
        mode = (existing and existing.mode) or DEFAULT_MODE
    end

    -- Same reasoning as mode: a re-register must not flip the player's choice.
    if network_filter == nil then
        if existing then
            network_filter = existing.network_filter == true
        else
            network_filter = gc_storage.DEFAULT_NETWORK_FILTER
        end
    end

    local record = {
        entity = entity,
        mode = mode,
        network_filter = network_filter or nil,
        network_id = existing and existing.network_id or nil
    }
    surface_data.combinators[unit_number] = record

    -- Mark the combinator's category dirty so the next tick populates it.
    local category = surface_data.categories[mode]
    if category then
        category.dirty = true
    end

    return record
end

--- Unregister a ghost combinator from storage
--- @param unit_number number The unit_number of the entity to unregister
--- @param surface_index number The surface index
function gc_storage.unregister_combinator(unit_number, surface_index)
    if not unit_number or not surface_index then
        log("[ghost_combinator] ERROR: unregister_combinator called with nil unit_number or surface_index")
        return
    end

    if not storage.ghost_combinator then
        return
    end

    local surface_data = storage.ghost_combinator[surface_index]
    if not surface_data or not surface_data.combinators then
        return
    end

    surface_data.combinators[unit_number] = nil
end

--- Get the combinator record for a real entity
--- @param entity LuaEntity The combinator entity
--- @return table|nil The {entity, mode} record, or nil if not registered
function gc_storage.get_combinator_record(entity)
    if not entity or not entity.valid or entity_lib.is_ghost(entity) then
        return nil
    end

    local unit_number = entity.unit_number
    if not unit_number then
        return nil
    end

    if not storage.ghost_combinator then
        return nil
    end

    local surface_data = storage.ghost_combinator[entity.surface.index]
    if not surface_data or not surface_data.combinators then
        return nil
    end

    return surface_data.combinators[unit_number]
end

--- Get all combinator records for a surface
--- @param surface_index number The surface index
--- @return table Table of unit_number -> {entity, mode} (empty table if none)
function gc_storage.get_combinators(surface_index)
    if not surface_index or not storage.ghost_combinator then
        return {}
    end

    local surface_data = storage.ghost_combinator[surface_index]
    if not surface_data or not surface_data.combinators then
        return {}
    end

    return surface_data.combinators
end
--------------------------------------------------------------------------------
-- Demand Counters
--------------------------------------------------------------------------------

--- Build the storage key for an item/quality pair
--- @param item_name string The placing item name
--- @param quality_name string The quality name
--- @return string The entry key
local function entry_key(item_name, quality_name)
    return item_name .. ":" .. quality_name
end

--- Add one to an item's count in a CATEGORY table, assigning a slot if new
--- Shared by the surface-wide categories and the per-network buckets.
--- CRITICAL: hot path - no validation beyond what the caller cannot guarantee.
--- @param cat table A CATEGORY table
--- @param item_name string The resolved placing item name
--- @param quality_name string|nil The quality name (defaults to "normal")
function gc_storage.category_add(cat, item_name, quality_name)
    quality_name = quality_name or "normal"
    local key = entry_key(item_name, quality_name)
    local entry = cat.entries[key]

    if entry then
        entry.count = entry.count + 1
        entry.changed = true
    else
        local slot = cat.next_slot
        cat.entries[key] = {
            count = 1,
            slot = slot,
            changed = true,
            item_name = item_name,
            quality = quality_name
        }
        cat.next_slot = slot + 1

        if slot > cat.slot_high_water then
            cat.slot_high_water = slot
        end
    end

    cat.dirty = true
end

--- Subtract one from an item's count in a CATEGORY table (floored at zero)
--- Zero-count entries are left for compaction to remove.
--- @param cat table A CATEGORY table
--- @param item_name string The resolved placing item name
--- @param quality_name string|nil The quality name (defaults to "normal")
function gc_storage.category_remove(cat, item_name, quality_name)
    local entry = cat.entries[entry_key(item_name, quality_name or "normal")]

    if entry then
        entry.count = math.max(0, entry.count - 1)
        entry.changed = true
        cat.dirty = true
    end
end

--- Increment the demand count for an item in a category
--- CRITICAL: Called for EVERY ghost built - must be FAST!
--- The caller must have already resolved item_name via signal_utils; this
--- function performs no prototype lookups.
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
--- @param item_name string The resolved placing item name
--- @param quality_name string|nil The quality name (defaults to "normal")
function gc_storage.increment(surface_index, category, item_name, quality_name)
    if not surface_index or not item_name then
        return
    end

    -- FAST PATH: one table index, no validation, no category loop. This runs for
    -- every ghost built anywhere on the map (a 10k-entity blueprint means 10k
    -- calls), so it must not funnel through get_surface_data's ensure logic.
    local surface_data = storage.ghost_combinator and storage.ghost_combinator[surface_index]
    local cat = surface_data and surface_data.categories and surface_data.categories[category]

    if not cat then
        -- Slow path only when the record or category is genuinely missing
        if not VALID_MODES[category] then
            return
        end
        surface_data = gc_storage.get_surface_data(surface_index)
        cat = surface_data and surface_data.categories[category]
        if not cat then
            return
        end
    end

    gc_storage.category_add(cat, item_name, quality_name)
end

--- Decrement the demand count for an item in a category
--- CRITICAL: Called for EVERY ghost removed - must be FAST!
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
--- @param item_name string The resolved placing item name
--- @param quality_name string|nil The quality name (defaults to "normal")
function gc_storage.decrement(surface_index, category, item_name, quality_name)
    if not surface_index or not item_name then
        return
    end

    -- FAST PATH, and deliberately non-creating: a decrement for a surface with
    -- no record (e.g. a deleted space platform whose destroy events are still
    -- queued) has nothing to undo and must not resurrect the record.
    local surface_data = storage.ghost_combinator and storage.ghost_combinator[surface_index]
    local cat = surface_data and surface_data.categories and surface_data.categories[category]
    if not cat then
        return
    end

    gc_storage.category_remove(cat, item_name, quality_name)
end

--- Get all entries for a category (for GUI display and output writing)
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
--- @return table Table of key -> entry (empty table if none)
function gc_storage.get_entries(surface_index, category)
    local cat = gc_storage.get_category(surface_index, category)
    if not cat then
        return {}
    end
    return cat.entries
end

--- Check whether a category has pending changes
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
--- @return boolean True if there are pending changes
function gc_storage.is_dirty(surface_index, category)
    local cat = gc_storage.get_category(surface_index, category)
    return cat ~= nil and cat.dirty == true
end

--- Clear the dirty flag for a category
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
function gc_storage.clear_dirty(surface_index, category)
    local cat = gc_storage.get_category(surface_index, category)
    if cat then
        cat.dirty = false
    end
end

--- Clear the changed flag for a single entry
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
--- @param key string The entry key ("item_name:quality")
function gc_storage.clear_entry_changed(surface_index, category, key)
    local cat = gc_storage.get_category(surface_index, category)
    if not cat or not key then
        return
    end

    local entry = cat.entries[key]
    if entry then
        entry.changed = false
    end
end

--- Reset a CATEGORY table's slot high-water mark after a full resync
--- Takes the table itself so it serves surface categories and network buckets.
--- @param cat table A CATEGORY table
function gc_storage.reset_category_high_water(cat)
    cat.slot_high_water = math.max(0, cat.next_slot - 1)
end

--------------------------------------------------------------------------------
-- Slot Compaction
--------------------------------------------------------------------------------

--- Compact a category's slots - remove zero-count entries and close slot gaps
--- Called periodically to prevent slot fragmentation. Takes the table itself so
--- it serves surface categories and network buckets alike.
--- @param cat table A CATEGORY table
--- @return number removed_count Number of entries removed
--- @return number old_max_slot Maximum slot index before compaction
--- @return number new_max_slot Maximum slot index after compaction
function gc_storage.compact_category(cat)
    local old_max_slot = cat.next_slot - 1

    -- Collect zero-count entries (cannot remove while iterating)
    local to_remove = {}
    for key, entry in pairs(cat.entries) do
        if entry.count <= 0 then
            to_remove[#to_remove + 1] = key
        end
    end

    local removed_count = #to_remove
    for _, key in ipairs(to_remove) do
        cat.entries[key] = nil
    end

    -- Reassign slots to eliminate gaps.
    --
    -- CRITICAL: iterate a SORTED array, never pairs(). Slot assignment is game
    -- state, and Lua's hash iteration order is not guaranteed to match between
    -- the host and a client that rebuilt this table from the save file - using
    -- pairs() here would assign different slots on different peers and desync
    -- the game. Sorting by existing slot also preserves the current display
    -- order and keeps the number of entries marked `changed` to a minimum.
    if removed_count > 0 then
        local survivors = {}
        for key, entry in pairs(cat.entries) do
            survivors[#survivors + 1] = {key = key, entry = entry}
        end

        table.sort(survivors, function(a, b)
            if a.entry.slot ~= b.entry.slot then
                return a.entry.slot < b.entry.slot
            end
            return a.key < b.key  -- deterministic tiebreak
        end)

        local new_slot = 1
        for _, item in ipairs(survivors) do
            if item.entry.slot ~= new_slot then
                item.entry.slot = new_slot
                item.entry.changed = true
            end
            new_slot = new_slot + 1
        end

        cat.next_slot = new_slot
        cat.dirty = true
    end

    return removed_count, old_max_slot, cat.next_slot - 1
end

--- Record the tick at which a surface was last compacted
--- @param surface_index number The surface index
--- @param current_tick number The current game tick
function gc_storage.set_last_compact_tick(surface_index, current_tick)
    local surface_data = gc_storage.get_surface_data(surface_index)
    if surface_data then
        surface_data.last_compact_tick = current_tick
    end
end
--------------------------------------------------------------------------------
-- Tracked Object Registrations (for on_object_destroyed)
--------------------------------------------------------------------------------

--- Record what a registered object contributes, so it can be undone on destroy
--- @param registration_number uint64 From script.register_on_object_destroyed
--- @param surface_index number The surface index
--- @param category string One of CATEGORIES
--- @param item_name string The resolved placing item name
--- @param quality_name string|nil The quality name
--- @return table|nil The new record (callers attach network data to it), or nil if rejected
function gc_storage.register_tracked_object(registration_number, surface_index, category, item_name, quality_name)
    if not registration_number or not item_name then
        return nil
    end

    -- Reject malformed records. A record with a bad category stores fine but its
    -- eventual decrement silently no-ops, so the increment that already happened
    -- never comes back down - invisible, permanent upward drift.
    if not surface_index or not VALID_MODES[category] then
        log("[ghost_combinator] ERROR: register_tracked_object with invalid surface/category: "
            .. tostring(surface_index) .. "/" .. tostring(category))
        return nil
    end

    if not storage.ghost_registrations then
        storage.ghost_registrations = {}
    end

    -- register_on_object_destroyed returns the SAME number for an object that is
    -- already registered, so one number maps to one object. If a record already
    -- exists under a DIFFERENT category, two categories are tracking one object
    -- and only one of them can be undone on destroy - the other would leak.
    local existing = storage.ghost_registrations[registration_number]
    if existing and existing.category ~= category then
        log(string.format(
            "[ghost_combinator] WARNING: registration %s re-categorised %s -> %s; %s count may drift",
            tostring(registration_number), tostring(existing.category), tostring(category),
            tostring(existing.category)))
    end

    local record = {
        surface = surface_index,
        category = category,
        item_name = item_name,
        quality = quality_name or "normal"
    }
    storage.ghost_registrations[registration_number] = record
    return record
end

--- Look up a tracked object's registration record
--- @param registration_number uint64 The registration number
--- @return table|nil {surface, category, item_name, quality} or nil
function gc_storage.get_tracked_object(registration_number)
    if not registration_number or not storage.ghost_registrations then
        return nil
    end

    return storage.ghost_registrations[registration_number]
end

--- Remove a tracked object's registration record
--- CRITICAL: Removing the record is what makes decrement idempotent - whichever
--- code path fires first (cancel, destroy, mine) consumes the record, and any
--- later path finds nothing and safely does nothing.
--- @param registration_number uint64 The registration number
function gc_storage.unregister_tracked_object(registration_number)
    if not registration_number or not storage.ghost_registrations then
        return
    end

    storage.ghost_registrations[registration_number] = nil
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

--- Remove invalid combinator references from storage
--- @param surface_index number|nil Optional surface to clean (all surfaces if nil)
--- @return number Number of invalid entries removed
function gc_storage.validate_and_cleanup(surface_index)
    if not storage.ghost_combinator then
        return 0
    end

    local surfaces = {}
    if surface_index then
        surfaces[surface_index] = storage.ghost_combinator[surface_index]
    else
        surfaces = storage.ghost_combinator
    end

    local removed = 0

    for _, surface_data in pairs(surfaces) do
        if surface_data and surface_data.combinators then
            local invalid = {}
            for unit_number, record in pairs(surface_data.combinators) do
                if not record or not record.entity or not record.entity.valid then
                    invalid[#invalid + 1] = unit_number
                end
            end

            for _, unit_number in ipairs(invalid) do
                surface_data.combinators[unit_number] = nil
                removed = removed + 1
            end
        end
    end

    return removed
end

return gc_storage
