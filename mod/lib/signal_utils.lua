--[[
  signal_utils.lua
  Mission Control Mod - Pure Signal Manipulation Utilities

  PURPOSE:
  This module provides pure functions for manipulating Factorio circuit signal tables.
  All functions are stateless and do not access global state or entity APIs.

  SIGNAL FORMAT:
  Factorio signals are stored as:
    signals = {
      [signal_id] = count,
      ...
    }

  Where signal_id is a table: {type = "item"|"fluid"|"virtual", name = "signal-name"}

  EXAMPLES:
    {type = "item", name = "iron-plate"}
    {type = "virtual", name = "signal-A"}
    {type = "fluid", name = "water"}

  SCOPE:
  ✓ Signal table operations (add, merge, copy, compare, clear)
  ✓ Signal counting and validation
  ✗ Reading signals from entities (that's circuit_utils)
  ✗ Storing signals in global (that's entity scripts)
  ✗ Evaluating conditions (that's gui_utils)

  DEPENDENCIES: None (pure utility module)

  MODULE RESPONSIBILITY:
  - Pure signal table manipulation
  - No side effects
  - No global state access
  - No entity interactions
--]]

local signal_utils = {}

--[[
  HELPER: Convert signal_id to string key for comparison
  Signal IDs are tables, so we need string keys for equality checks
  In Factorio 2.0, signals also have quality (defaults to "normal")

  @param signal_id table: Signal identifier {type, name, quality?}
  @return string: Unique string key for this signal (format: "type:name:quality")
--]]
local function signal_to_key(signal_id)
  if not signal_id then return nil end
  local signal_type = signal_id.type or "item"
  local quality = signal_id.quality or "normal"
  return signal_type .. ":" .. signal_id.name .. ":" .. quality
end

--[[
  HELPER: Check if two signal_ids are equal
  In Factorio 2.0, signals also have quality (defaults to "normal")

  @param a table: First signal_id {type, name, quality?}
  @param b table: Second signal_id {type, name, quality?}
  @return boolean: True if both represent the same signal (including quality)
--]]
local function signal_ids_equal(a, b)
  if not a or not b then return false end
  local a_quality = a.quality or "normal"
  local b_quality = b.quality or "normal"
  return a.type == b.type and a.name == b.name and a_quality == b_quality
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
  Add source signals into target table (MUTATES target)

  This function performs in-place addition of signal values.
  If a signal exists in both tables, values are summed.
  If a signal only exists in source, it's added to target.

  @param target table: Signal table to add into (modified in place)
  @param source table: Signal table to add from (not modified)

  BEHAVIOR:
  - Mutates target table
  - Does not modify source table
  - Handles nil gracefully (no-op)
  - Skips nil or zero values

  EXAMPLE:
    target = {[iron_signal] = 10, [copper_signal] = 5}
    source = {[iron_signal] = 15, [coal_signal] = 20}
    add_signals(target, source)
    -- Result: target = {[iron_signal] = 25, [copper_signal] = 5, [coal_signal] = 20}
--]]
function signal_utils.add_signals(target, source)
  -- Validate inputs
  if not target then return end
  if not source then return end

  -- Iterate through source signals and add to target
  for signal_id, count in pairs(source) do
    if signal_id and count and count ~= 0 then
      if target[signal_id] then
        target[signal_id] = target[signal_id] + count
      else
        target[signal_id] = count
      end
    end
  end
end

--[[
  Merge red and green wire signals (returns NEW table)

  When both red and green wires have the same signal, values are SUMMED.
  This matches Factorio's vanilla behavior for circuit network evaluation.

  @param red_signals table: Red wire signal table
  @param green_signals table: Green wire signal table
  @return table: New merged signal table (sum value per signal)

  BEHAVIOR:
  - Creates new table (does not modify inputs)
  - SUM values for duplicate signals
  - Handles nil inputs (returns empty table)
  - Preserves signal_id table references

  EXAMPLE:
    red = {[iron_signal] = 10, [copper_signal] = 5}
    green = {[iron_signal] = 15, [coal_signal] = 20}
    merged = merge_signals(red, green)
    -- Result: {[iron_signal] = 25, [copper_signal] = 5, [coal_signal] = 20}
--]]
function signal_utils.merge_signals(red_signals, green_signals)
  local merged = {}

  -- Add all red signals
  if red_signals then
    for signal_id, count in pairs(red_signals) do
      if signal_id and count and count ~= 0 then
        merged[signal_id] = count
      end
    end
  end

  -- Add/merge green signals (sum values)
  if green_signals then
    for signal_id, count in pairs(green_signals) do
      if signal_id and count and count ~= 0 then
        if merged[signal_id] then
          merged[signal_id] = merged[signal_id] + count
        else
          merged[signal_id] = count
        end
      end
    end
  end

  return merged
end

--[[
  Deep copy signal table (returns NEW table)

  Creates an independent copy of the signal table.
  Signal_id tables are used as keys (preserved by reference).

  @param source table: Signal table to copy
  @return table: New independent signal table

  BEHAVIOR:
  - Returns new table
  - Does not modify source
  - Returns empty table if source is nil
  - Signal_id keys are preserved by reference (Factorio pattern)

  EXAMPLE:
    original = {[iron_signal] = 10}
    copy = copy_signals(original)
    copy[iron_signal] = 20
    -- original[iron_signal] is still 10
--]]
function signal_utils.copy_signals(source)
  if not source then return {} end

  local copy = {}
  for signal_id, count in pairs(source) do
    if signal_id and count then
      copy[signal_id] = count
    end
  end

  return copy
end

--[[
  Compare two signal tables for equality

  Returns true if both tables contain exactly the same signals with same values.

  @param a table: First signal table
  @param b table: Second signal table
  @return boolean: True if tables are identical

  BEHAVIOR:
  - Deep comparison of signal values
  - Handles nil (nil == nil is true, nil != table is false)
  - Ignores zero values (treats as absent)
  - Order-independent

  EXAMPLE:
    a = {[iron_signal] = 10, [copper_signal] = 5}
    b = {[copper_signal] = 5, [iron_signal] = 10}
    signals_equal(a, b)  -- true (order doesn't matter)

    c = {[iron_signal] = 10}
    signals_equal(a, c)  -- false (different signals)
--]]
function signal_utils.signals_equal(a, b)
  -- Both nil = equal
  if not a and not b then return true end

  -- One nil, one table = not equal
  if not a or not b then return false end

  -- Build normalized sets (ignore zero values)
  local normalized_a = {}
  local normalized_b = {}

  for signal_id, count in pairs(a) do
    if signal_id and count and count ~= 0 then
      local key = signal_to_key(signal_id)
      normalized_a[key] = count
    end
  end

  for signal_id, count in pairs(b) do
    if signal_id and count and count ~= 0 then
      local key = signal_to_key(signal_id)
      normalized_b[key] = count
    end
  end

  -- Compare counts
  local count_a = 0
  local count_b = 0

  for _ in pairs(normalized_a) do count_a = count_a + 1 end
  for _ in pairs(normalized_b) do count_b = count_b + 1 end

  if count_a ~= count_b then return false end

  -- Compare values
  for key, value_a in pairs(normalized_a) do
    if normalized_b[key] ~= value_a then
      return false
    end
  end

  return true
end

--[[
  Reset signal table to empty (MUTATES table)

  Clears all signals from the table, making it empty.

  @param signals table: Signal table to clear (modified in place)

  BEHAVIOR:
  - Mutates input table
  - Removes all keys
  - Handles nil gracefully (no-op)

  EXAMPLE:
    signals = {[iron_signal] = 10, [copper_signal] = 5}
    clear_signals(signals)
    -- signals is now {}
--]]
function signal_utils.clear_signals(signals)
  if not signals then return end

  -- Clear all keys
  for key in pairs(signals) do
    signals[key] = nil
  end
end

--[[
  Count number of unique signals in table

  Returns the number of non-zero signals present.

  @param signals table: Signal table to count
  @return number: Count of unique signals (0 if nil or empty)

  BEHAVIOR:
  - Returns 0 for nil input
  - Ignores zero values
  - Counts unique signal_ids only

  EXAMPLE:
    signals = {[iron_signal] = 10, [copper_signal] = 5, [coal_signal] = 0}
    count = count_signals(signals)
    -- count = 2 (coal_signal ignored because value is 0)
--]]
function signal_utils.count_signals(signals)
  if not signals then return 0 end

  local count = 0
  for signal_id, value in pairs(signals) do
    if signal_id and value and value ~= 0 then
      count = count + 1
    end
  end

  return count
end

--[[
  Convert signal_id to prototype object

  Gets the actual prototype object from prototypes table for use with
  various APIs (pipette, display, etc).

  @param signal table: Signal identifier {type, name, quality?}
  @return LuaPrototype|nil: Prototype object, or nil if not found

  BEHAVIOR:
  - Returns actual prototype object from prototypes.* tables
  - Defaults to "item" if type is nil
  - Returns prototype for virtual signals (virtual_signal type)
  - Quality is passed through if present on signal

  TYPE MAPPING:
  - "item" → prototypes.item[name]
  - "fluid" → prototypes.fluid[name]
  - "entity" → prototypes.entity[name]
  - "virtual" → prototypes.virtual_signal[name]
  - nil → defaults to prototypes.item[name]

  EXAMPLE:
    signal = {type = "item", name = "iron-plate"}
    prototype = signal_to_prototype(signal)
    -- Returns: LuaItemPrototype["iron-plate"]

    virtual_signal = {type = "virtual", name = "signal-A"}
    prototype = signal_to_prototype(virtual_signal)
    -- Returns: LuaVirtualSignalPrototype["signal-A"]
--]]
function signal_utils.signal_to_prototype(signal)
  if not signal or not signal.name then
    return nil
  end

  -- Default to "item" if type is nil
  local signal_type = signal.type or "item"

  -- Map "virtual" to "virtual_signal" for prototypes table
  if signal_type == "virtual" then
    signal_type = "virtual_signal"
  end

  -- Get the actual prototype object from the game
  if not prototypes[signal_type] then
    return nil
  end

  local prototype = prototypes[signal_type][signal.name]

  return prototype
end

-- Alias for backwards compatibility
signal_utils.signal_to_pipette_prototype = signal_utils.signal_to_prototype

--[[
  Format signal for display in GUI

  Creates a formatted string representation of a signal with its count.
  Uses rich text format for display.

  @param signal_data table: Signal data {signal = SignalID, count = integer}
  @return string: Formatted signal string

  EXAMPLE:
    signal_data = {signal = {type = "item", name = "iron-plate"}, count = 100}
    format_signal_for_display(signal_data)
    -- Returns: "[item=iron-plate] x100"
--]]
function signal_utils.format_signal_for_display(signal_data)
  if not signal_data or not signal_data.signal then
    return "Invalid signal"
  end

  local signal = signal_data.signal
  local signal_type = signal.type or "item"

  return string.format("[%s=%s] x%d", signal_type, signal.name, signal_data.count)
end

--[[
  MEMO: ghost_name -> item_name resolution cache

  Ghost tracking runs on EVERY entity built anywhere on the map, so resolving the
  placement item must not cost a prototype lookup per ghost. The mapping is derived
  purely from prototypes, so it is identical on every peer and deterministic.

  CRITICAL: This is a module-local table, NOT storage. It is derived data and is
  rebuilt lazily after load. Never persist it - prototype names can change between
  mod versions.

  Key is "<kind>:<name>" so entity and tile prototypes sharing a name cannot collide.
--]]
local item_name_memo = {}

--[[
  Look up the item name that places a given entity

  Entity names don't always match item names (e.g., "straight-rail" -> "rail")
  Uses LuaEntityPrototype.items_to_place_this to find the correct item.

  @param entity_name string: The entity prototype name (e.g., ghost_name)
  @return string|nil: The item name that places this entity, or nil if unresolvable

  CRITICAL: Returns nil (not the entity name) when the placing item cannot be
  determined. Falling back to the raw prototype name emits a signal for an item
  that may not exist - e.g. the tile "stone-path" is placed by item "stone-brick",
  so a "stone-path" signal is invalid. Callers must skip nil results.

  EXAMPLE:
    get_item_name_for_entity("straight-rail")
    -- Returns: "rail"

    get_item_name_for_entity("iron-chest")
    -- Returns: "iron-chest"
--]]
function signal_utils.get_item_name_for_entity(entity_name)
  if not entity_name then
    return nil
  end

  local memo_key = "e:" .. entity_name
  local cached = item_name_memo[memo_key]
  if cached ~= nil then
    -- false is the memoized "unresolvable" marker (nil would re-lookup every time)
    if cached == false then return nil end
    return cached
  end

  local resolved = nil
  local entity_proto = prototypes.entity[entity_name]
  if entity_proto then
    -- Construction bots use the first item in this array
    local items_to_place = entity_proto.items_to_place_this
    if items_to_place and #items_to_place > 0 then
      resolved = items_to_place[1].name
    end
  end

  item_name_memo[memo_key] = resolved or false
  return resolved
end

--[[
  Look up the item name that places a given tile

  Tile names often differ from their placing item (e.g., "stone-path" -> "stone-brick").
  Uses LuaTilePrototype.items_to_place_this, which has the same shape as the entity
  version (array of ItemToPlace, each with .name and .count).

  @param tile_name string: The tile prototype name
  @return string|nil: The item name that places this tile, or nil if unresolvable

  EXAMPLE:
    get_item_name_for_tile("stone-path")
    -- Returns: "stone-brick"

    get_item_name_for_tile("refined-concrete")
    -- Returns: "refined-concrete"
--]]
function signal_utils.get_item_name_for_tile(tile_name)
  if not tile_name then
    return nil
  end

  local memo_key = "t:" .. tile_name
  local cached = item_name_memo[memo_key]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end

  local resolved = nil
  local tile_proto = prototypes.tile[tile_name]
  if tile_proto then
    local items_to_place = tile_proto.items_to_place_this
    if items_to_place and #items_to_place > 0 then
      resolved = items_to_place[1].name
    end
  end

  item_name_memo[memo_key] = resolved or false
  return resolved
end

--[[
  Resolve the placing item for ANY ghost - entity-ghost or tile-ghost

  This is the single resolver both ghost kinds should use.

  LuaEntity.ghost_prototype is documented as a union of
  LuaEntityPrototype | LuaTilePrototype, and BOTH expose
  items_to_place_this :: array[ItemToPlace], so one code path covers both.

  We dispatch on entity.type rather than reading ghost_prototype directly so the
  memo above absorbs the cost - ghost_name is a plain string, whereas touching
  ghost_prototype allocates a prototype wrapper on every call.

  @param ghost LuaEntity: A ghost entity (type "entity-ghost" or "tile-ghost")
  @return string|nil: The item name that places it, or nil if unresolvable

  EXAMPLE:
    -- entity-ghost of straight-rail  -> "rail"
    -- tile-ghost of stone-path       -> "stone-brick"
    -- tile-ghost of refined-concrete -> "refined-concrete"
--]]
function signal_utils.get_item_name_for_ghost(ghost)
  if not ghost or not ghost.valid then
    return nil
  end

  local ghost_type = ghost.type
  if ghost_type == "tile-ghost" then
    return signal_utils.get_item_name_for_tile(ghost.ghost_name)
  elseif ghost_type == "entity-ghost" then
    return signal_utils.get_item_name_for_entity(ghost.ghost_name)
  end

  -- Not a ghost at all
  return nil
end

--------------------------------------------------------------------------------
-- INLINE TESTS (for development validation)
--------------------------------------------------------------------------------

--[[
  INLINE TEST SUITE

  Tests removed for production. To test manually, use console:
  /c local su = require("lib.signal_utils"); [add test assertions]
--]]

-- ==============================================================================
-- SIGNAL EVALUATION TYPES
-- ==============================================================================

-- Signal evaluation types for special handling of aggregate signals
local SIGNAL_EVAL_TYPE = {
  NORMAL = "normal",         -- Standard signal comparison
  EACH = "each",             -- Iterate through all signals
  ANYTHING = "anything",     -- TRUE if ANY signal matches condition
  EVERYTHING = "everything"  -- TRUE if ALL signals match condition
}

--- Determine the evaluation type for a signal
-- Returns the appropriate SIGNAL_EVAL_TYPE based on the signal
-- @param signal SignalID: The signal to check {type=string, name=string}
-- @return string: One of SIGNAL_EVAL_TYPE values (NORMAL, EACH, ANYTHING, EVERYTHING)
function signal_utils.get_signal_eval_type(signal)
  if not signal then return SIGNAL_EVAL_TYPE.NORMAL end
  if signal.type ~= "virtual" then return SIGNAL_EVAL_TYPE.NORMAL end

  if signal.name == "signal-each" then
    return SIGNAL_EVAL_TYPE.EACH
  elseif signal.name == "signal-anything" then
    return SIGNAL_EVAL_TYPE.ANYTHING
  elseif signal.name == "signal-everything" then
    return SIGNAL_EVAL_TYPE.EVERYTHING
  end

  return SIGNAL_EVAL_TYPE.NORMAL
end

--- Get signal key for table lookup
-- Converts signal definition to string key for consistent lookups
-- In Factorio 2.0, signals also have quality (defaults to "normal")
-- @param signal table: {type = "item"|"fluid"|"virtual", name = "signal-name", quality? = "normal"|"uncommon"|"rare"|"epic"|"legendary"}
-- @param ignore_quality boolean: If true, exclude quality from key (default: false)
-- @return string: Key for signal table lookup (format: "type:name:quality" or "type:name" if ignore_quality)
function signal_utils.get_signal_key(signal, ignore_quality)
  if not signal or not signal.name then return "" end
  local signal_type = signal.type or "item"  -- Default to "item" if type not specified
  if ignore_quality then
    -- Use type:name format only (ignores quality differences)
    return signal_type .. ":" .. signal.name
  end
  local quality = signal.quality or "normal"  -- Default to "normal" if quality not specified
  -- Use type:name:quality format to distinguish signals with different qualities
  return signal_type .. ":" .. signal.name .. ":" .. quality
end

--- Compare two values with an operator
-- Helper function for condition evaluation
-- @param left number: Left-hand value
-- @param right number: Right-hand value
-- @param operator string: Comparison operator (<, >, =, ≠, ≤, ≥)
-- @return boolean: Result of comparison
function signal_utils.compare_values(left, right, operator)
  if operator == "<" then
    return left < right
  elseif operator == ">" then
    return left > right
  elseif operator == "=" then
    return left == right
  elseif operator == "≠" then
    return left ~= right
  elseif operator == "≤" then
    return left <= right
  elseif operator == "≥" then
    return left >= right
  else
    return false  -- Unknown operator
  end
end

--- Get filtered signals from separate red/green tables
-- Combines signals based on wire filter setting
-- @param red_signals table: Signals from red wire {[signal_id] = count}
-- @param green_signals table: Signals from green wire {[signal_id] = count}
-- @param wire_filter string: "red", "green", "both", or "none"
-- @return table: Filtered signal table with combined values
function signal_utils.get_filtered_signals_from_tables(red_signals, green_signals, wire_filter)
  local result = {}

  -- Default to "both" if wire_filter is nil or invalid (defensive programming)
  if not wire_filter or wire_filter == "" then
    wire_filter = "both"
  end

  -- Handle "none" case explicitly - return empty table (all signals = 0)
  if wire_filter == "none" then
    return result
  end

  if wire_filter == "red" or wire_filter == "both" then
    if red_signals then
      for signal_id, count in pairs(red_signals) do
        result[signal_id] = (result[signal_id] or 0) + count
      end
    end
  end

  if wire_filter == "green" or wire_filter == "both" then
    if green_signals then
      for signal_id, count in pairs(green_signals) do
        result[signal_id] = (result[signal_id] or 0) + count
      end
    end
  end

  return result
end

-- ==============================================================================
-- CONDITION EVALUATION
-- ==============================================================================

--- Evaluate a single condition with aggregate signal support
-- Handles EVERYTHING, ANYTHING, EACH, and NORMAL signal types
-- @param left_signals table: Signals to evaluate {[signal_key] = value}
-- @param left_signal SignalID: The left signal (may be aggregate)
-- @param operator string: Comparison operator
-- @param right_value number: The right-hand value to compare against
-- @param right_signals table: Optional - signals for right side (needed when right is EACH)
-- @param right_signal SignalID: Optional - the right signal (to detect EACH)
-- @return boolean: Result of the condition evaluation
function signal_utils.evaluate_single_condition_with_aggregates(left_signals, left_signal, operator, right_value, right_signals, right_signal)
  local eval_type = signal_utils.get_signal_eval_type(left_signal)
  local right_eval_type = signal_utils.get_signal_eval_type(right_signal)

  -- EACH on left side: iterate through all left signals
  -- TRUE if ANY signal satisfies the condition
  if eval_type == SIGNAL_EVAL_TYPE.EACH then
    for signal_key, left_value in pairs(left_signals) do
      local compare_value
      if right_eval_type == SIGNAL_EVAL_TYPE.EACH then
        -- EACH vs EACH: compare same signal on both sides
        compare_value = (right_signals and right_signals[signal_key]) or 0
      else
        -- EACH vs constant/normal signal: use the provided right_value
        compare_value = right_value
      end

      if signal_utils.compare_values(left_value, compare_value, operator) then
        return true  -- Any match means true
      end
    end
    return false  -- No matches
  end

  -- EVERYTHING: ALL non-zero signals must satisfy condition
  -- Special case: If NO signals exist, treat as everything == 0
  if eval_type == SIGNAL_EVAL_TYPE.EVERYTHING then
    local has_signals = false
    for _, value in pairs(left_signals) do
      has_signals = true
      if not signal_utils.compare_values(value, right_value, operator) then
        return false
      end
    end
    -- If no signals at all, treat as everything == 0 and compare against RHS
    if not has_signals then
      return signal_utils.compare_values(0, right_value, operator)
    end
    return true  -- All signals satisfied the condition
  end

  -- ANYTHING: AT LEAST ONE signal must satisfy condition
  if eval_type == SIGNAL_EVAL_TYPE.ANYTHING then
    for _, value in pairs(left_signals) do
      if signal_utils.compare_values(value, right_value, operator) then
        return true
      end
    end
    return false
  end

  -- NORMAL: Standard single signal comparison
  local left_key = signal_utils.get_signal_key(left_signal)
  local left_value = left_signals[left_key] or 0
  return signal_utils.compare_values(left_value, right_value, operator)
end

--- Evaluate condition results with AND/OR precedence
-- AND has higher precedence than OR (AND operations are performed first)
-- @param evaluated_conditions table: Array of {result=boolean, logical_op=nil|"AND"|"OR"}
-- @return boolean: Final result
--
-- Algorithm:
--   1. Split conditions into groups separated by OR
--   2. Within each group, AND all conditions together
--   3. OR all group results together
function signal_utils.evaluate_with_precedence(evaluated_conditions)
  if #evaluated_conditions == 0 then
    return false
  end

  -- Build groups: each group contains consecutive AND conditions (or standalone conditions)
  local groups = {}
  local current_group = {}

  for i, cond_data in ipairs(evaluated_conditions) do
    if i == 1 then
      -- First condition always starts a group (no logical_op)
      table.insert(current_group, cond_data.result)
    elseif cond_data.logical_op == "OR" then
      -- OR starts a new group (finish current group first)
      table.insert(groups, current_group)
      current_group = {cond_data.result}  -- Start new group with this condition
    else
      -- AND or nil (treat as AND) - add to current group
      table.insert(current_group, cond_data.result)
    end
  end

  -- Don't forget the last group
  if #current_group > 0 then
    table.insert(groups, current_group)
  end

  -- Evaluate each group (AND all conditions within group)
  local group_results = {}
  for _, group in ipairs(groups) do
    local group_result = true
    for _, condition_result in ipairs(group) do
      group_result = group_result and condition_result
      if not group_result then
        break  -- Short-circuit: if any AND fails, whole group is false
      end
    end
    table.insert(group_results, group_result)
  end

  -- OR all group results together
  local final_result = false
  for _, group_result in ipairs(group_results) do
    final_result = final_result or group_result
    if final_result then
      break  -- Short-circuit: if any OR succeeds, whole expression is true
    end
  end

  return final_result
end

--- Evaluate complex conditions with boolean operators and proper precedence
-- Evaluates an array of conditions with per-condition AND/OR operators
-- AND has higher precedence than OR (AND binds tighter)
-- @param conditions table: Array of condition objects with logical_op field
-- @param red_signals table: Signals from red wire {[signal_id] = count}
-- @param green_signals table: Signals from green wire {[signal_id] = count}
-- @return boolean: True if overall condition expression is true
--
-- Condition format:
--   {
--     {
--       logical_op = nil|"AND"|"OR",  -- nil for first, AND/OR for subsequent
--       left_signal = {type="item", name="iron-plate"},
--       left_wire_filter = "red"|"green"|"both",
--       operator = "<"|">"|"="|"≠"|"≤"|"≥",
--       right_type = "constant"|"signal",
--       right_value = 100,  -- If constant
--       right_signal = {...},  -- If signal
--       right_wire_filter = "red"|"green"|"both"
--     },
--     -- ... more conditions
--   }
function signal_utils.evaluate_complex_conditions(conditions, red_signals, green_signals)
  if not conditions or #conditions == 0 then
    return false  -- No conditions = false
  end

  -- Step 1: Evaluate all individual conditions and store results with their operators
  local evaluated_conditions = {}
  for i, cond in ipairs(conditions) do
    -- Get signals for left side based on wire filter
    local left_signals = signal_utils.get_filtered_signals_from_tables(red_signals, green_signals, cond.left_wire_filter)

    -- Get right signal value and signals (needed for EACH on right side)
    local right_value
    local right_signals_filtered = nil
    if cond.right_type == "signal" then
      right_signals_filtered = signal_utils.get_filtered_signals_from_tables(red_signals, green_signals, cond.right_wire_filter)
      local right_key = signal_utils.get_signal_key(cond.right_signal)
      right_value = right_signals_filtered[right_key] or 0
    else
      right_value = cond.right_value or 0
    end

    -- Evaluate this condition using shared helper (handles aggregate signals including EACH)
    local cond_result = signal_utils.evaluate_single_condition_with_aggregates(
      left_signals, cond.left_signal, cond.operator, right_value, right_signals_filtered, cond.right_signal
    )

    table.insert(evaluated_conditions, {
      result = cond_result,
      logical_op = cond.logical_op  -- nil for first, "AND" or "OR" for subsequent
    })
  end

  -- Step 2: Apply AND/OR precedence (AND binds tighter than OR)
  return signal_utils.evaluate_with_precedence(evaluated_conditions)
end

-- Export the SIGNAL_EVAL_TYPE constants for external use
signal_utils.SIGNAL_EVAL_TYPE = SIGNAL_EVAL_TYPE

return signal_utils
