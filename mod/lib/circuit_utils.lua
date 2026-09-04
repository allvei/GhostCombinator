--------------------------------------------------------------------------------
-- circuit_utils.lua
-- Pure utility functions for circuit network operations
--
-- PURPOSE:
--   Provides low-level access to Factorio's circuit network API without
--   knowledge of mod-specific entities or global state. All functions are
--   pure (no side effects except reading/writing circuit signals).
--
-- RESPONSIBILITIES:
--   - Reading signals from entity circuit connectors
--   - Writing signals to entity circuit outputs
--   - Checking circuit connection status
--   - Finding entities on circuit networks
--   - Entity circuit capability validation
--
-- DOES NOT OWN:
--   - Signal table manipulation (see signal_utils.lua)
--   - Entity placement validation (see validation.lua)
--   - Global state access (pure library)
--   - Mod-specific entity logic
--
-- DEPENDENCIES: None (pure utility module)
--
-- COMPLEXITY: ~200 lines
--------------------------------------------------------------------------------

-- No external dependencies - pure utility module

local circuit_utils = {}

--------------------------------------------------------------------------------
-- ENTITY VALIDATION
--------------------------------------------------------------------------------

--- Validate entity can be used for circuit operations
--- @param entity LuaEntity: Entity to validate
--- @return boolean: True if valid and has circuit connectors
---
--- EDGE CASES:
---   - Returns false if entity is nil
---   - Returns false if entity.valid is false
---   - Returns false if entity doesn't support circuit connections
---
--- TEST CASES:
---   is_valid_circuit_entity(nil) => false
---   is_valid_circuit_entity(destroyed_entity) => false
---   is_valid_circuit_entity(combinator) => true
---   is_valid_circuit_entity(chest) => false (if no circuit connection)
function circuit_utils.is_valid_circuit_entity(entity)
  if not entity then return false end
  if not entity.valid then return false end

  -- Check if entity supports circuit connections
  -- Entities with circuit capability have get_circuit_network method
  return entity.get_circuit_network ~= nil
end

--------------------------------------------------------------------------------
-- SIGNAL READING
--------------------------------------------------------------------------------

--- Read signals from entity circuit connector (Factorio 2.0 API)
--- @param entity LuaEntity: Entity to read from
--- @param wire_connector_id defines.wire_connector_id: Which wire connector to read
--- @return table|nil: Signal table {[signal_id] = count} or nil if no connection
---
--- FACTORIO 2.0 API CHANGES:
---   - Use defines.wire_connector_id (not defines.circuit_connector_id)
---   - get_circuit_network() takes single parameter (wire_connector_id)
---   - Available connectors: combinator_input_red, combinator_input_green, etc.
---
--- EDGE CASES:
---   - Returns nil if entity is invalid
---   - Returns nil if no circuit network on specified wire
---   - Returns empty table if network exists but has no signals
---   - Handles multi-connector entities (combinators, power switches, etc.)
---
--- SIGNAL TABLE FORMAT:
---   {
---     [{type="item", name="iron-plate"}] = 100,
---     [{type="virtual", name="signal-A"}] = 50
---   }
---
--- TEST CASES:
---   get_circuit_signals(nil, combinator_input_red) => nil
---   get_circuit_signals(unwired_combinator, combinator_input_red) => nil
---   get_circuit_signals(wired_combinator, combinator_input_red) => {...}
function circuit_utils.get_circuit_signals(entity, wire_connector_id)
  if not circuit_utils.is_valid_circuit_entity(entity) then
    return nil
  end

  -- Default to combinator input red if not specified
  wire_connector_id = wire_connector_id or defines.wire_connector_id.combinator_input_red

  -- Get the circuit network for this wire connector (Factorio 2.0 API)
  local circuit_network = entity.get_circuit_network(wire_connector_id)

  if not circuit_network then
    return nil
  end

  -- Get signals from the network
  local signals = circuit_network.signals

  if not signals then
    return {} -- Network exists but no signals
  end

  -- Convert signals array to lookup table
  -- Factorio API returns signals as: {{signal={type="item", name="..."}, count=N}, ...}
  local signal_table = {}
  for _, signal_data in pairs(signals) do
    if signal_data.signal and signal_data.count then
      signal_table[signal_data.signal] = signal_data.count
    end
  end

  return signal_table
end

--[[
  REMOVED FUNCTION: get_merged_input_signals

  This function duplicated Factorio's native API: entity.get_merged_signals()

  Migration guide:
  OLD: local signals = circuit_utils.get_merged_input_signals(entity)

  NEW: Use native Factorio API:
  local merged = entity.get_merged_signals(defines.circuit_connector_id.combinator_input)
  -- Convert format if needed (native returns array, not lookup table):
  local signals = {}
  if merged then
    for _, signal_data in pairs(merged) do
      signals[signal_data.signal] = signal_data.count
    end
  end
--]]

--------------------------------------------------------------------------------
-- CONNECTION STATUS
--------------------------------------------------------------------------------

--- Check if entity has circuit connection on specified wire
--- @param entity LuaEntity: Entity to check
--- @param wire_type defines.wire_type: RED or GREEN
--- @return boolean: True if connected
---
--- EDGE CASES:
---   - Returns false if entity is invalid
---   - Returns false if entity doesn't support circuits
---   - Returns true only if network exists and is connected
---
--- TEST CASES:
---   has_circuit_connection(nil, red) => false
---   has_circuit_connection(unwired_entity, red) => false
---   has_circuit_connection(wired_entity, red) => true
function circuit_utils.has_circuit_connection(entity, wire_type)
  if not circuit_utils.is_valid_circuit_entity(entity) then
    return false
  end

  -- Check all possible connector IDs (some entities have multiple)
  -- Most entities use combinator_input/output, but check common ones
  local connector_ids = {
    defines.circuit_connector_id.combinator_input,
    defines.circuit_connector_id.combinator_output,
    defines.circuit_connector_id.constant_combinator,
    defines.circuit_connector_id.container,
    defines.circuit_connector_id.inserter,
  }

  for _, connector_id in pairs(connector_ids) do
    local circuit_network = entity.get_circuit_network(wire_type, connector_id)
    if circuit_network then
      return true
    end
  end

  return false
end

--[[
  REMOVED FUNCTION: get_connected_entities

  This function was non-functional (returned empty array).
  LuaCircuitNetwork does not have a connected_entities property.

  Migration guide:
  OLD: local entities = circuit_utils.get_connected_entities(network)

  NEW: Use native Factorio API on entities:
  local connected = entity.circuit_connected_entities
  -- Returns: {red = {array of entities}, green = {array of entities}}

  for _, e in pairs(connected.red or {}) do
    -- Process red wire connected entities
  end
  for _, e in pairs(connected.green or {}) do
    -- Process green wire connected entities
  end
--]]

--------------------------------------------------------------------------------
-- UTILITY HELPERS
--------------------------------------------------------------------------------

--- Get number of unique signals on entity's circuit network
--- @param entity LuaEntity: Entity to check
--- @param wire_type defines.wire_type: RED or GREEN
--- @return number: Count of unique signals
---
--- EDGE CASES:
---   - Returns 0 if entity is invalid
---   - Returns 0 if no circuit connection
---
--- TEST CASES:
---   get_unique_signal_count(nil, red) => 0
---   get_unique_signal_count(combinator, red) => 5 (if 5 signals present)
function circuit_utils.get_unique_signal_count(entity, wire_type)
  local signals = circuit_utils.get_circuit_signals(entity, wire_type)
  if not signals then return 0 end

  local count = 0
  for _ in pairs(signals) do
    count = count + 1
  end

  return count
end

--- Check if entity has any circuit connections (red or green)
--- @param entity LuaEntity: Entity to check
--- @return boolean: True if has any circuit connection
---
--- TEST CASES:
---   has_any_circuit_connection(nil) => false
---   has_any_circuit_connection(unwired) => false
---   has_any_circuit_connection(red_wired) => true
---   has_any_circuit_connection(green_wired) => true
function circuit_utils.has_any_circuit_connection(entity)
  return circuit_utils.has_circuit_connection(entity, defines.wire_type.red) or
         circuit_utils.has_circuit_connection(entity, defines.wire_type.green)
end

--- Check if entity has any circuit connections on specified connector (Factorio 2.0 API)
--- This is the preferred method for checking connections - uses wire_connector_id directly
--- @param entity LuaEntity
--- @param connector_id defines.wire_connector_id|nil Optional connector to check (defaults to checking all combinator connectors)
--- @return boolean
function circuit_utils.has_circuit_connections(entity, connector_id)
  if not entity or not entity.valid then
    return false
  end

  -- If specific connector requested, check only that one
  if connector_id then
    local network = entity.get_circuit_network(connector_id)
    return network ~= nil
  end

  -- Check all possible wire connectors for combinators
  local connectors = {
    defines.wire_connector_id.combinator_input_red,
    defines.wire_connector_id.combinator_input_green,
    defines.wire_connector_id.combinator_output_red,
    defines.wire_connector_id.combinator_output_green
  }

  for _, conn_id in ipairs(connectors) do
    local network = entity.get_circuit_network(conn_id)
    if network then
      return true
    end
  end

  return false
end

--- Get all input signals from an entity's circuit connections (raw API format)
--- Returns direct references to the API's signal arrays. Treat as read-only.
--- Signal format: {signal = SignalID, count = int}
--- @param entity LuaEntity The entity to read signals from
--- @param wire_type defines.wire_type|nil Optional wire type filter (red or green)
--- @return table {red = array of Signal, green = array of Signal}
---
--- This is the PREFERRED method for reading signals as it uses the raw Factorio format
--- without transformation, making it more efficient and simpler.
function circuit_utils.get_input_signals_raw(entity, wire_type)
  local empty = {}
  local result = {
    red = empty,
    green = empty
  }

  if not entity or not entity.valid then
    return result
  end

  -- Get red wire signals (if not filtered to green only)
  if not wire_type or wire_type == defines.wire_type.red then
    local red_signals = entity.get_signals(defines.wire_connector_id.combinator_input_red)
    if red_signals then
      result.red = red_signals
    end
  end

  -- Get green wire signals (if not filtered to red only)
  if not wire_type or wire_type == defines.wire_type.green then
    local green_signals = entity.get_signals(defines.wire_connector_id.combinator_input_green)
    if green_signals then
      result.green = green_signals
    end
  end

  return result
end

--- Get the total count of a specific signal from input wires
--- @param entity LuaEntity
--- @param signal_id SignalID The signal to count {type, name, quality?}
--- @param wire_type defines.wire_type|nil Optional wire type filter
--- @return integer Total count of the signal
---
--- This searches for a specific signal across input wires and returns its summed count.
--- Different from get_unique_signal_count which counts how many different signals exist.
--- In Factorio 2.0, signals also have quality (defaults to "normal")
function circuit_utils.get_signal_count(entity, signal_id, wire_type)
  if not entity or not entity.valid or not signal_id then
    return 0
  end

  local total = 0
  local signals = circuit_utils.get_input_signals_raw(entity, wire_type)
  local target_quality = signal_id.quality or "normal"

  -- Sum from red wire
  if not wire_type or wire_type == defines.wire_type.red then
    for _, signal_data in ipairs(signals.red) do
      local sig_quality = signal_data.signal.quality or "normal"
      if signal_data.signal.type == signal_id.type and signal_data.signal.name == signal_id.name and sig_quality == target_quality then
        total = total + signal_data.count
      end
    end
  end

  -- Sum from green wire
  if not wire_type or wire_type == defines.wire_type.green then
    for _, signal_data in ipairs(signals.green) do
      local sig_quality = signal_data.signal.quality or "normal"
      if signal_data.signal.type == signal_id.type and signal_data.signal.name == signal_id.name and sig_quality == target_quality then
        total = total + signal_data.count
      end
    end
  end

  return total
end

--- Get count of signals on a specific wire connector
--- @param entity LuaEntity
--- @param connector_id defines.wire_connector_id (must include color, e.g., combinator_input_red)
--- @return integer Number of unique signals
function circuit_utils.get_signal_count_for_wire(entity, connector_id)
  if not entity or not entity.valid then
    return 0
  end

  local network = entity.get_circuit_network(connector_id)
  if not network or not network.signals then
    return 0
  end

  local count = 0
  for _ in pairs(network.signals) do
    count = count + 1
  end

  return count
end

--- Get all input signals from both red and green wires with metadata (Factorio 2.0 API)
--- @param entity LuaEntity: Entity to read from
--- @param connector_type string: Connector type prefix (default: "combinator_input")
--- @return table: Array of signal display data {signal_id, count, wire_color}
---
--- FACTORIO 2.0 API:
---   - Uses wire_connector_id for both red and green wires
---   - connector_type options: "combinator_input", "combinator_output", "circuit", etc.
---
--- EDGE CASES:
---   - Returns empty array if entity is invalid
---   - Returns empty array if no connections
---   - Combines signals present on both wires (sums values, marks as "both")
---   - Sorted by type then name for consistent display
---
--- WIRE_COLOR VALUES:
---   - "red" - Signal only on red wire
---   - "green" - Signal only on green wire
---   - "both" - Signal present on both wires (count is summed)
---
--- RETURN FORMAT:
---   {
---     {signal_id = {type="item", name="iron-plate"}, count = 100, wire_color = "red"},
---     {signal_id = {type="virtual", name="signal-A"}, count = 50, wire_color = "green"},
---     ...
---   }
---
--- TEST CASES:
---   get_input_signals(nil) => {}
---   get_input_signals(unwired) => {}
---   get_input_signals(red_only) => {{signal_id, count, wire_color="red"}, ...}
---   get_input_signals(both_wires) => signals from both, merged where overlap
function circuit_utils.get_input_signals(entity, connector_type)
  if not circuit_utils.is_valid_circuit_entity(entity) then
    return {}
  end

  -- Default to combinator input if not specified
  connector_type = connector_type or "combinator_input"

  -- Build wire connector IDs for red and green wires (Factorio 2.0 API)
  local red_connector_id = defines.wire_connector_id[connector_type .. "_red"]
  local green_connector_id = defines.wire_connector_id[connector_type .. "_green"]

  local signals_display = { red = {}, green = {}, both = {} }

  -- Read red wire signals
  local red_signals = circuit_utils.get_circuit_signals(entity, red_connector_id)
  if red_signals then
    for signal_id, count in pairs(red_signals) do
      table.insert(signals_display.red, {
        signal_id = signal_id,
        count = count,
        wire_color = "red"
      })
    end
  end

  -- Read green wire signals
  local green_signals = circuit_utils.get_circuit_signals(entity, green_connector_id)
  if green_signals then
  for signal_id, count in pairs(green_signals) do
      table.insert(signals_display.green, {
        signal_id = signal_id,
        count = count,
        wire_color = "green"
      })
    end
  end

  return signals_display
end

--- Get filtered signals based on wire color (Factorio 2.0 API)
--- Used by complex condition system to read signals from specific wires
--- @param entity LuaEntity: Entity to read from
--- @param wire_filter string: "red", "green", or "both"
--- @param connector_type string: Connector type prefix (default: "combinator_input")
--- @return table: Signal lookup table {[signal_id] = count}
---
--- FACTORIO 2.0 API:
---   - Uses wire_connector_id for accessing specific wires
---   - Signal values are summed when wire_filter is "both"
---
--- WIRE_FILTER VALUES:
---   - "red" - Only signals from red wire
---   - "green" - Only signals from green wire
---   - "both" - Signals from both wires (values summed)
---
--- EDGE CASES:
---   - Returns empty table if entity is invalid
---   - Returns empty table if wire not connected
---   - When "both", signals present on only one wire return that wire's value
---   - When "both", signals present on both wires have values summed
---
--- RETURN FORMAT:
---   {
---     [{type="item", name="iron-plate"}] = 100,
---     [{type="virtual", name="signal-A"}] = 50
---   }
---
--- TEST CASES:
---   get_filtered_signals(nil, "red") => {}
---   get_filtered_signals(entity, "red") => {signals from red wire only}
---   get_filtered_signals(entity, "both") => {signals from both, summed}
function circuit_utils.get_filtered_signals(entity, wire_filter, connector_type)
  if not circuit_utils.is_valid_circuit_entity(entity) then
    return {}
  end

  -- Default to combinator input if not specified
  connector_type = connector_type or "combinator_input"
  wire_filter = wire_filter or "both"

  -- Build wire connector IDs (Factorio 2.0 API)
  local red_connector_id = defines.wire_connector_id[connector_type .. "_red"]
  local green_connector_id = defines.wire_connector_id[connector_type .. "_green"]

  local result = {}

  -- Read signals based on filter
  if wire_filter == "red" or wire_filter == "both" then
    local red_signals = circuit_utils.get_circuit_signals(entity, red_connector_id)
    if red_signals then
      for signal_id, count in pairs(red_signals) do
        result[signal_id] = (result[signal_id] or 0) + count
      end
    end
  end

  if wire_filter == "green" or wire_filter == "both" then
    local green_signals = circuit_utils.get_circuit_signals(entity, green_connector_id)
    if green_signals then
      for signal_id, count in pairs(green_signals) do
        result[signal_id] = (result[signal_id] or 0) + count
      end
    end
  end

  return result
end

--------------------------------------------------------------------------------
-- EXPORT MODULE
--------------------------------------------------------------------------------

return circuit_utils
