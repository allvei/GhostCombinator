-- Ghost Combinator - Logistic Network Buckets
-- Per-network demand counts, so a combinator can report only what the robots
-- of ITS logistic network can actually build (GitHub issue #5).
--
-- WHY THIS EXISTS
-- Surface-wide counts include demand no robot can reach. Wired into a
-- requester, that produces requests that never clear. A combinator with
-- `network_filter` set reads a bucket holding only the demand inside its
-- network's construction area instead of the surface-wide category.
--
-- MODEL
--   surface_data.networks[network_id].categories[category] = CATEGORY
-- Same CATEGORY shape as the surface-wide counters (see storage.lua), so the
-- write / compaction / resync code in control.lua is shared between them.
--
-- Every tracked object's registration record carries `position`, `force` and
-- `networks` (the ids it is currently counted in). That makes removal exact:
-- detach() undoes precisely what attach() did, regardless of how coverage has
-- changed since.
--
-- COVERAGE CHANGES
-- Roboports being built, removed or losing power change which networks cover a
-- position, and no event reports that. rebucket_step() walks every record in
-- small per-tick batches and moves the ones whose coverage changed. Counts
-- therefore react instantly to demand changing and converge within one cycle
-- to coverage changing.
--
-- Stateful and entity-specific, so it lives under scripts/ per
-- docs/module_responsibility_matrix.md. Split from storage.lua for file size.

local gc_storage = require("scripts.ghost_combinator.storage")

local networks = {}

local CATEGORIES = gc_storage.CATEGORIES

-----------------------------------------------------------
-- INTERNAL
-----------------------------------------------------------

--- Build an empty network bucket with every category
--- @return table A bucket {categories = {[category] = CATEGORY}}
local function new_bucket()
    local categories = {}
    for _, category_name in ipairs(CATEGORIES) do
        categories[category_name] = gc_storage.new_category()
    end
    return {categories = categories}
end

--- Check whether a record's stored ids match a fresh lookup result
--- Both lists are tiny (usually 0-2 entries), so a nested scan beats building
--- a set and allocates nothing.
--- @param ids table|nil The record's current network ids
--- @param found table Array of LuaLogisticNetwork from the lookup
--- @return boolean True if they describe the same set of networks
local function same_networks(ids, found)
    local count = ids and #ids or 0
    if count ~= #found then
        return false
    end

    for i = 1, count do
        local id = found[i].network_id
        local present = false
        for j = 1, count do
            if ids[j] == id then
                present = true
                break
            end
        end
        if not present then
            return false
        end
    end

    return true
end

--- Count a record into every network in `found`
--- The record must not currently be counted in any bucket (detach first).
--- @param record table The registration record (needs surface/category/item_name/quality)
--- @param found table Array of LuaLogisticNetwork covering the record's position
local function assign(record, found)
    local count = #found
    if count == 0 then
        record.networks = nil
        return
    end

    -- Non-creating: a surface without data has no combinators to feed.
    local surface_data = storage.ghost_combinator and storage.ghost_combinator[record.surface]
    if not surface_data then
        record.networks = nil
        return
    end

    local buckets = surface_data.networks
    if not buckets then
        buckets = {}
        surface_data.networks = buckets
    end

    local ids = {}
    for i = 1, count do
        local id = found[i].network_id
        ids[i] = id

        local bucket = buckets[id]
        if not bucket then
            bucket = new_bucket()
            buckets[id] = bucket
        end

        gc_storage.category_add(bucket.categories[record.category], record.item_name, record.quality)
    end

    record.networks = ids
end

-----------------------------------------------------------
-- TRACKING
-----------------------------------------------------------

--- Record an object's position/force and count it into the covering networks
--- Called right after a registration record is created for `entity`.
--- @param record table The registration record returned by register_tracked_object
--- @param entity LuaEntity The ghost or marked entity the record describes
function networks.attach(record, entity)
    local position = entity.position
    local force_index = entity.force.index

    record.position = {x = position.x, y = position.y}
    record.force = force_index

    assign(record, entity.surface.find_logistic_networks_by_construction_area(position, force_index))
end

--- Remove an object from every network bucket it is counted in
--- Safe to call on records with no network data (pre-1.2.0 or uncovered).
--- MUST be called before a record is discarded or overwritten.
--- @param record table The registration record
function networks.detach(record)
    local ids = record.networks
    if not ids then
        return
    end
    record.networks = nil

    local surface_data = storage.ghost_combinator and storage.ghost_combinator[record.surface]
    local buckets = surface_data and surface_data.networks
    if not buckets then
        return
    end

    for i = 1, #ids do
        local bucket = buckets[ids[i]]
        if bucket then
            gc_storage.category_remove(bucket.categories[record.category], record.item_name, record.quality)
        end
    end
end

--- Discard every network bucket on a surface
--- For rescans and /gc-ghost-clear, which rebuild or wipe all counts anyway.
--- @param surface_data table The surface record
function networks.reset_surface(surface_data)
    if surface_data then
        surface_data.networks = {}
    end
end

-----------------------------------------------------------
-- LOOKUPS
-----------------------------------------------------------

--- Check whether a logistic cell is a roboport whose supply area covers a position
--- Mobile cells (personal roboports on characters/vehicles) and non-roboport
--- owners never qualify - they must not anchor a combinator to a network.
--- @param cell LuaLogisticCell|nil The cell to test
--- @param position MapPosition The position to test
--- @return boolean True if a stationary roboport supplies `position`
local function roboport_supplies(cell, position)
    if not cell or cell.mobile or not cell.is_in_logistic_range(position) then
        return false
    end
    local owner = cell.owner
    return owner ~= nil and owner.valid and owner.type == "roboport"
end

--- Find the logistic network a combinator (or its ghost) belongs to
--- The combinator must stand inside the SUPPLY (logistic) area of a roboport;
--- merely being near a network, or covered only by a personal roboport or a
--- non-roboport cell, does not count.
--- @param entity LuaEntity The combinator or combinator ghost
--- @return number|nil The network id, or nil if not supplied by any roboport
function networks.find_combinator_network_id(entity)
    local position = entity.position
    local network = entity.surface.find_logistic_network_by_position(position, entity.force)
    if not network then
        return nil
    end

    -- Fast path: the closest cell is almost always the roboport covering us.
    if roboport_supplies(network.find_cell_closest_to(position), position) then
        return network.network_id
    end

    -- Otherwise any stationary roboport in the network may still supply us
    -- (overlapping supply areas, or a closer mobile cell). Networks never
    -- overlap in supply area - they merge - so this network is the only candidate.
    for _, cell in pairs(network.cells) do
        if roboport_supplies(cell, position) then
            return network.network_id
        end
    end

    return nil
end

--- Get a bucket's category WITHOUT creating it
--- @param surface_data table The surface record
--- @param network_id number|nil The network id
--- @param category string One of CATEGORIES
--- @return table|nil The CATEGORY table, or nil if no demand was ever counted there
function networks.get_category(surface_data, network_id, category)
    local buckets = network_id and surface_data and surface_data.networks
    local bucket = buckets and buckets[network_id]
    return bucket and bucket.categories[category]
end

--- Check whether a bucket has no entries in any category
--- @param bucket table A network bucket
--- @return boolean True if the bucket can be discarded
function networks.is_bucket_empty(bucket)
    for _, category in pairs(bucket.categories) do
        if next(category.entries) ~= nil then
            return false
        end
    end
    return true
end

-----------------------------------------------------------
-- BACKGROUND RE-BUCKET
-----------------------------------------------------------

--- Snapshot every registration number, sorted
--- CRITICAL: sorted, not pairs() order. Moving records between buckets can
--- create entries, and entry slot numbers are game state; processing records
--- in a guaranteed order keeps every peer's slot assignment identical.
--- @return table Array of registration numbers
local function snapshot_keys()
    local keys = {}
    local registrations = storage.ghost_registrations
    if registrations then
        for registration_number in pairs(registrations) do
            keys[#keys + 1] = registration_number
        end
        table.sort(keys)
    end
    return keys
end

--- Re-check a slice of records against current network coverage
--- Called every tick. Processes at most `batch` records; starts a new cycle
--- over all records at most once per `cycle_ticks`.
--- @param batch number Records to process per call
--- @param cycle_ticks number Minimum ticks between cycle starts
--- @param tick number The current game tick
function networks.rebucket_step(batch, cycle_ticks, tick)
    local state = storage.gc_rebucket
    if not state then
        state = {keys = {}, index = 1, next_cycle_tick = 0}
        storage.gc_rebucket = state
    end

    local keys = state.keys
    local key_count = #keys

    if state.index > key_count then
        if tick < state.next_cycle_tick then
            return
        end

        keys = snapshot_keys()
        key_count = #keys
        state.keys = keys
        state.index = 1
        state.next_cycle_tick = tick + cycle_ticks

        if key_count == 0 then
            return
        end
    end

    local registrations = storage.ghost_registrations
    if not registrations then
        return
    end

    local surfaces = game.surfaces
    local first = state.index
    local last = math.min(first + batch - 1, key_count)

    for i = first, last do
        -- The record may have been consumed since the snapshot; that is fine.
        local record = registrations[keys[i]]
        if record and record.position then
            local surface = surfaces[record.surface]
            if surface and surface.valid then
                local found = surface.find_logistic_networks_by_construction_area(record.position, record.force)
                if not same_networks(record.networks, found) then
                    networks.detach(record)
                    assign(record, found)
                end
            end
        end
    end

    state.index = last + 1

    -- Release the snapshot once walked so it is not carried in the save.
    if state.index > key_count then
        state.keys = {}
    end
end

return networks
