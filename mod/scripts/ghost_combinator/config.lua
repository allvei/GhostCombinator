-- Ghost Combinator - Per-Instance Config Module
-- Owns the combinator's output mode: reading and writing it, and moving it
-- across blueprints, copy-paste, cloning and ghost revival.
--
-- Split out of storage.lua purely for file size (CLAUDE.md caps modules at
-- 750-900 lines); storage.lua owns the demand counters, this owns the
-- per-instance setting. Both are stateful and entity-specific, so both live
-- under scripts/ per docs/module_responsibility_matrix.md.
--
-- WHERE THE SETTING LIVES
--   Real entities -> storage, on the combinator record ({entity, mode})
--   Ghosts        -> entity.tags, under the CONFIG_TAG key
-- Every function below branches on entity_lib.is_ghost for exactly that reason.
--
-- Adapted from FactorioBaseMod's passthrough_combinator storage module. The
-- function shapes, guard order and the ghost-tag complete-replacement idiom are
-- kept identical so this mod stays consistent with its siblings; only the
-- storage lookup differs, because this mod keys combinators per surface rather
-- than in one flat unit_number table.
--
-- The config payload is a single string field, so the base mod's set<->array tag
-- conversion is not needed here.

local entity_lib = require("lib.entity_lib")
local gc_storage = require("scripts.ghost_combinator.storage")

local gc_config = {}

-- Entity name constant
local GHOST_COMBINATOR = "ghost-combinator"

-- Re-exported from storage so callers have one place to look for the tag key
local CONFIG_TAG = gc_storage.CONFIG_TAG
local DEFAULT_MODE = gc_storage.DEFAULT_MODE


--------------------------------------------------------------------------------
-- Combinator Mode (per-instance setting)
--------------------------------------------------------------------------------

--- Get a combinator's output mode
--- Works for both real entities (storage) and ghosts (entity.tags)
--- @param entity LuaEntity The combinator entity or its ghost
--- @return string The mode name, defaulting to DEFAULT_MODE
function gc_config.get_mode(entity)
    if not entity or not entity.valid then
        return DEFAULT_MODE
    end

    -- Ghosts read from tags, never from storage
    if entity_lib.is_ghost(entity) then
        local config = gc_config.get_ghost_config(entity)
        if config and gc_storage.is_valid_mode(config.mode) then
            return config.mode
        end
        return DEFAULT_MODE
    end

    local record = gc_storage.get_combinator_record(entity)
    if record and gc_storage.is_valid_mode(record.mode) then
        return record.mode
    end

    return DEFAULT_MODE
end

--- Set a combinator's output mode
--- Works for both real entities (storage) and ghosts (entity.tags)
--- NOTE: Does NOT rewrite the combinator's logistic section - the caller must
--- clear and repopulate the output, because slot numbering differs per category.
--- @param entity LuaEntity The combinator entity or its ghost
--- @param mode string The new mode
--- @return boolean True if the mode changed, false if unchanged or invalid
function gc_config.set_mode(entity, mode)
    if not entity or not entity.valid then
        return false
    end

    if not gc_storage.is_valid_mode(mode) then
        log("[ghost_combinator] WARNING: set_mode called with invalid mode: " .. tostring(mode))
        return false
    end

    -- Ghosts store config in tags
    if entity_lib.is_ghost(entity) then
        -- Bail on ghosts we don't own: get_ghost_config/save_ghost_config both
        -- silently ignore them, so without this guard we would report "changed"
        -- for an entity we never wrote to, and the caller would rewrite slots
        -- on something that isn't ours.
        if not entity_lib.is_type(entity, GHOST_COMBINATOR) then
            return false
        end

        local config = gc_config.get_ghost_config(entity) or {}
        if config.mode == mode then
            return false
        end
        config.mode = mode
        gc_config.save_ghost_config(entity, config)
        return true
    end

    local record = gc_storage.get_combinator_record(entity)
    if not record then
        -- Not registered yet - register with the requested mode
        record = gc_storage.register_combinator(entity, mode)
        return record ~= nil
    end

    if record.mode == mode then
        return false
    end

    local surface_data = gc_storage.get_surface_data(entity.surface.index)
    record.mode = mode

    -- Dirty the new category so the next tick repopulates this combinator
    if surface_data then
        local category = surface_data.categories[mode]
        if category then
            category.dirty = true
        end
    end

    return true
end


--------------------------------------------------------------------------------
-- Blueprint / Copy-Paste Config
--------------------------------------------------------------------------------
-- Adapted from FactorioBaseMod's passthrough_combinator storage. The function
-- shapes and the ghost-tag idiom are kept identical so the family stays
-- consistent; only the storage lookup differs, because this mod keys combinators
-- per surface rather than in one flat unit_number table.
--
-- The config payload is a single string field, so the base mod's set<->array
-- tag conversion is not needed here.

--- Serialize a combinator's configuration for blueprints/copy-paste
--- Works for both ghosts and real entities
--- @param entity LuaEntity The entity to serialize
--- @return table|nil Blueprint-compatible config table
function gc_config.serialize_config(entity)
    if not entity or not entity.valid then
        return nil
    end

    if not entity_lib.is_type(entity, GHOST_COMBINATOR) then
        return nil
    end

    return {
        mode = gc_config.get_mode(entity)
    }
end

--- Restore a combinator's configuration from a blueprint/copy-paste
--- Works for both ghosts and real entities
--- @param entity LuaEntity The entity to configure
--- @param config table The config table
function gc_config.restore_config(entity, config)
    if not entity or not entity.valid then
        log("[ghost_combinator] ERROR: Attempted to restore config to invalid entity")
        return
    end

    if not config then
        return  -- No config to restore
    end

    if not entity_lib.is_type(entity, GHOST_COMBINATOR) then
        return
    end

    local mode = config.mode
    if not gc_storage.is_valid_mode(mode) then
        mode = DEFAULT_MODE
    end

    -- Handle ghosts - config lives in tags
    if entity_lib.is_ghost(entity) then
        gc_config.save_ghost_config(entity, {mode = mode})
        return
    end

    -- Real entity - ensure it is registered, then set the mode
    if not gc_storage.get_combinator_record(entity) then
        gc_storage.register_combinator(entity, mode)
        return
    end

    gc_config.set_mode(entity, mode)
end

--------------------------------------------------------------------------------
-- Ghost Entity Support
--------------------------------------------------------------------------------

--- Get configuration from a ghost entity's tags
--- Ghosts store their configuration in entity.tags, NOT in storage
--- @param ghost_entity LuaEntity The ghost entity
--- @return table|nil Configuration table, or nil if not applicable
function gc_config.get_ghost_config(ghost_entity)
    if not ghost_entity or not ghost_entity.valid then
        return nil
    end

    if not entity_lib.is_ghost(ghost_entity) then
        log("[ghost_combinator] ERROR: get_ghost_config called on non-ghost entity")
        return nil
    end

    if not entity_lib.is_type(ghost_entity, GHOST_COMBINATOR) then
        return nil
    end

    local tags = ghost_entity.tags
    local stored = tags and tags[CONFIG_TAG]
    if not stored then
        -- Default config
        return {mode = DEFAULT_MODE}
    end

    local mode = stored.mode
    if not gc_storage.is_valid_mode(mode) then
        mode = DEFAULT_MODE
    end

    return {mode = mode}
end

--- Save configuration to a ghost entity's tags
--- CRITICAL: Uses the complete table replacement pattern. Mutating
--- `ghost_entity.tags.foo` directly does NOT persist - `tags` returns a copy,
--- so the whole table must be reassigned.
--- @param ghost_entity LuaEntity The ghost entity
--- @param config table Configuration to save
function gc_config.save_ghost_config(ghost_entity, config)
    if not ghost_entity or not ghost_entity.valid then
        log("[ghost_combinator] ERROR: Attempted to save config to invalid ghost")
        return
    end

    if not entity_lib.is_ghost(ghost_entity) then
        log("[ghost_combinator] ERROR: save_ghost_config called on non-ghost entity")
        return
    end

    if not entity_lib.is_type(ghost_entity, GHOST_COMBINATOR) then
        return
    end

    local mode = config and config.mode
    if not gc_storage.is_valid_mode(mode) then
        mode = DEFAULT_MODE
    end

    -- Complete table replacement pattern for ghost tags
    local new_tags = ghost_entity.tags or {}
    new_tags[CONFIG_TAG] = {mode = mode}
    ghost_entity.tags = new_tags
end

return gc_config
