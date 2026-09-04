-- gui_utils.lua
-- Purpose: Common GUI creation patterns and helpers for Mission Control mod
-- Dependencies: signal_utils (for signal evaluation type checking in validation)
-- This module provides REUSABLE GUI components used across multiple entity types
-- Does NOT contain entity-specific GUI layouts (those are in scripts/gui_handlers)

local signal_utils = require("lib.signal_utils")

-- ==============================================================================
-- CONSTANTS
-- ==============================================================================

local GUI_CONSTANTS = {
  TITLEBAR_HEIGHT = 28,
  BUTTON_HEIGHT = 28,
  SPACING = 8,
  PADDING = 12,
  MIN_WIDTH = 300,
  MAX_WIDTH = 600
}

-- Operator definitions (index matches dropdown position)
local OPERATORS = {
  {symbol = "<",  display = "<"},
  {symbol = ">",  display = ">"},
  {symbol = "=",  display = "="},
  {symbol = "≠",  display = "≠"},
  {symbol = "≤",  display = "≤"},
  {symbol = "≥",  display = "≥"}
}

-- Icon types for status labels
local STATUS_ICONS = {
  connected = "[img=utility/status_working]",
  disconnected = "[img=utility/status_not_working]",
  warning = "[img=utility/warning_icon]"
}

-- Signal evaluation types (imported from signal_utils for validation)
local SIGNAL_EVAL_TYPE = signal_utils.SIGNAL_EVAL_TYPE

function find_child_recursive(element, name)
    if element.name == name then
        return element
    end
    if element.children then
        for _, child in pairs(element.children) do
            local found = find_child_recursive(child, name)
            if found then return found end
        end
    end
    return nil
end

-- ==============================================================================
-- SIGNAL VALIDATION (for GUI feedback)
-- ==============================================================================

--- Validate a signal for use in LEFT side of conditions
-- All signal types are valid on the left side (NORMAL, EACH, ANYTHING, EVERYTHING)
-- @param signal SignalID: The signal to validate
-- @return string|nil: Locale key for error message, or nil if valid
function validate_condition_signal(signal)
    -- All signal types are now valid on the left side
    return nil
end

--- Validate a signal for use on the RIGHT side of conditions
-- NORMAL signals are always allowed
-- EACH is only allowed if the left side is also EACH
-- ANYTHING and EVERYTHING are never allowed on the right side
-- @param signal SignalID: The signal to validate
-- @param left_signal SignalID: The left side signal (to check if EACH is allowed)
-- @return string|nil: Locale key for error message, or nil if valid
function validate_right_signal(signal, left_signal)
    local eval_type = signal_utils.get_signal_eval_type(signal)

    -- NORMAL signals are always valid on right side
    if eval_type == SIGNAL_EVAL_TYPE.NORMAL then
        return nil
    end

    -- EACH is valid on right side ONLY if left side is also EACH
    if eval_type == SIGNAL_EVAL_TYPE.EACH then
        local left_eval_type = signal_utils.get_signal_eval_type(left_signal)
        if left_eval_type == SIGNAL_EVAL_TYPE.EACH then
            return nil  -- EACH on right is valid when left is EACH
        else
            return "gui.each-right-requires-each-left"
        end
    end

    -- ANYTHING and EVERYTHING are never valid on right side
    return "gui.special-signal-not-allowed-right"
end

-- ==============================================================================
-- GUI COMPONENT CREATION
-- ==============================================================================

--- Create standard titlebar with close button
-- Creates a horizontal flow with title label and close button
-- @param parent LuaGuiElement: Parent container
-- @param title LocalisedString: Window title text
-- @param close_button_name string: Name for close button (for event handling)
-- @return LuaGuiElement: Created titlebar flow
function create_titlebar(parent, title, close_button_name)
  local titlebar = parent.add{
    type = "flow",
    direction = "horizontal"
  }
  titlebar.style.height = GUI_CONSTANTS.TITLEBAR_HEIGHT
  titlebar.style.horizontally_stretchable = true
  titlebar.style.vertical_align = "center"

  -- Title label (takes up most space)
  local title_label = titlebar.add{
    type = "label",
    caption = title,
    style = "frame_title"
  }
  title_label.style.horizontally_stretchable = true

  -- Drag handle (empty filler for window dragging)
  titlebar.add{
    type = "empty-widget",
    style = "draggable_space_header"
  }.style.horizontally_stretchable = true

  -- Close button
  titlebar.add{
    type = "sprite-button",
    name = close_button_name,
    sprite = "utility/close_white",
    style = "frame_action_button",
    tooltip = {"gui.close"}
  }

  return titlebar
end

--- Create row of buttons
-- Creates a horizontal flow with evenly-spaced buttons
-- @param parent LuaGuiElement: Parent container
-- @param buttons array: Array of {name, caption, tooltip} tables
-- @return LuaGuiElement: Created button flow
-- Example: create_button_row(parent, {
--   {name = "select_all", caption = {"gui.select-all"}, tooltip = {"gui.select-all-tooltip"}},
--   {name = "clear_all", caption = {"gui.clear-all"}, tooltip = nil}
-- })
function create_button_row(parent, buttons)
  local button_flow = parent.add{
    type = "flow",
    direction = "horizontal"
  }
  button_flow.style.horizontal_spacing = GUI_CONSTANTS.SPACING
  button_flow.style.vertically_stretchable = false

  for _, button_def in ipairs(buttons) do
    local button = button_flow.add{
      type = "button",
      name = button_def.name,
      caption = button_def.caption,
      tooltip = button_def.tooltip
    }
    button.style.height = GUI_CONSTANTS.BUTTON_HEIGHT
    button.style.minimal_width = 100
  end

  return button_flow
end

--- Create status label with icon
-- Creates a label with an icon prefix indicating status
-- @param parent LuaGuiElement: Parent container
-- @param status_text LocalisedString: Status message
-- @param icon_type string: "connected", "disconnected", or "warning"
-- @return LuaGuiElement: Created label
function create_status_label(parent, status_text, icon_type)
  local icon = STATUS_ICONS[icon_type] or ""
  local label = parent.add{
    type = "label",
    caption = icon .. " " .. status_text
  }
  label.style.single_line = false
  return label
end

--- Create condition selector (signal + operator + value)
-- Creates a horizontal flow with signal chooser, operator dropdown, and value field
-- This is a reusable pattern for circuit condition building
-- @param parent LuaGuiElement: Parent container
-- @param name_prefix string: Prefix for child element names (e.g., "rule_1_")
-- @return table: {signal_chooser, operator_dropdown, value_field, flow}
function create_condition_selector(parent, name_prefix)
  local condition_flow = parent.add{
    type = "flow",
    direction = "horizontal"
  }
  condition_flow.style.horizontal_spacing = GUI_CONSTANTS.SPACING
  condition_flow.style.vertical_align = "center"

  -- Signal chooser
  local signal_chooser = condition_flow.add{
    type = "choose-elem-button",
    name = name_prefix .. "signal",
    elem_type = "signal",
    tooltip = {"gui.condition-signal-tooltip"}
  }

  -- Operator dropdown
  local operator_dropdown = condition_flow.add{
    type = "drop-down",
    name = name_prefix .. "operator",
    items = {},  -- Will be populated with populate_operator_dropdown
    selected_index = 1,
    tooltip = {"gui.condition-operator-tooltip"}
  }
  populate_operator_dropdown(operator_dropdown)

  -- Value field (can be number or signal)
  local value_field = condition_flow.add{
    type = "textfield",
    name = name_prefix .. "value",
    text = "0",
    numeric = true,
    allow_negative = true,
    tooltip = {"gui.condition-value-tooltip"}
  }
  value_field.style.width = 80

  return {
    signal_chooser = signal_chooser,
    operator_dropdown = operator_dropdown,
    value_field = value_field,
    flow = condition_flow
  }
end

-- ==============================================================================
-- GUI UTILITY FUNCTIONS
-- ==============================================================================

--- Close GUI for player by name
-- Safely destroys GUI element if it exists
-- @param player LuaPlayer: Player whose GUI to close
-- @param gui_name string: Name of root GUI element
function close_gui_for_player(player, gui_name)
  if not player or not player.valid then return end

  local gui_element = player.gui.screen[gui_name]
  if gui_element and gui_element.valid then
    gui_element.destroy()
  end
end

-- ==============================================================================
-- OPERATOR UTILITIES
-- ==============================================================================

--- Populate dropdown with standard operators
-- Fills a dropdown element with comparison operators
-- @param dropdown LuaGuiElement: Dropdown element to populate
function populate_operator_dropdown(dropdown)
  if not dropdown or not dropdown.valid then return end

  local items = {}
  for _, op in ipairs(OPERATORS) do
    table.insert(items, op.display)
  end

  dropdown.items = items
  if dropdown.selected_index == 0 then
    dropdown.selected_index = 1  -- Default to "<"
  end
end

--- Get operator symbol from dropdown index
-- Converts dropdown selected index to operator symbol
-- @param index number: Dropdown selected index (1-based)
-- @return string: Operator symbol (<, >, =, ≠, ≤, ≥)
function get_operator_from_index(index)
  if index < 1 or index > #OPERATORS then
    return "<"  -- Default fallback
  end
  return OPERATORS[index].symbol
end

--- Get dropdown index from operator symbol
-- Converts operator symbol to dropdown index
-- @param operator string: Operator symbol
-- @return number: Dropdown index (1-based)
function get_index_from_operator(operator)
  for i, op in ipairs(OPERATORS) do
    if op.symbol == operator then
      return i
    end
  end
  return 1  -- Default to first operator
end

-- ==============================================================================
-- WIRE FILTER COMPONENTS
-- ==============================================================================

--- Create wire filter checkboxes (R/G)
-- Creates a pair of checkboxes for filtering red and green wire signals
-- @param parent LuaGuiElement: Parent container
-- @param name_prefix string: Prefix for checkbox names (e.g., "left_", "right_")
-- @return table: {red_checkbox, green_checkbox, flow}
function create_wire_filter_checkboxes(parent, name_prefix)
  local filter_flow = parent.add{
    type = "flow",
    name = name_prefix,
    direction = "vertical",
    visible = true
  }
  filter_flow.style.vertical_spacing = 0
  filter_flow.style.horizontal_align = "center"

  local checkbox_panel = filter_flow.add{
    type = "flow",
    direction = "horizontal"
  }
  checkbox_panel.style.horizontal_spacing = 2
  checkbox_panel.style.vertical_align = "center"

  -- Red checkbox
  local red_checkbox = checkbox_panel.add{
    type = "checkbox",
    name = name_prefix .. "red",
    state = true,  -- Default: both enabled
    tooltip = {"gui.wire-filter-red-tooltip"}
  }
  red_checkbox.style.width = 20
  red_checkbox.style.height = 20

  -- Red label
  checkbox_panel.add{
    type = "label",
    caption = "[color=red]R[/color]",
    tooltip = {"gui.wire-filter-red-tooltip"}
  }


  checkbox_panel = filter_flow.add{
    type = "flow",
    direction = "horizontal"
  }
  checkbox_panel.style.horizontal_spacing = 2
  checkbox_panel.style.vertical_align = "center"

  -- Green checkbox
  local green_checkbox = checkbox_panel.add{
    type = "checkbox",
    name = name_prefix .. "green",
    state = true,  -- Default: both enabled
    tooltip = {"gui.wire-filter-green-tooltip"}
  }
  green_checkbox.style.width = 20
  green_checkbox.style.height = 20

  -- Green label
  checkbox_panel.add{
    type = "label",
    caption = "[color=green]G[/color]",
    tooltip = {"gui.wire-filter-green-tooltip"}
  }

  return {
    red_checkbox = red_checkbox,
    green_checkbox = green_checkbox,
    flow = filter_flow
  }
end

--- Create complete condition row for complex conditions
-- Creates a full condition row matching decider combinator style
-- @param parent LuaGuiElement: Parent container
-- @param rule_index number: Index of this condition (for naming)
-- @param condition table: Optional existing condition data to populate
-- @param is_first boolean: True if this is the first condition (no AND/OR button)
-- @param show_delete_button boolean: Optional, defaults to true. Set to false to omit delete button
-- @return table: {flow, and_or_button, left_wire_filter, left_signal, operator, right_type_toggle, right_value, right_signal, right_wire_filter, delete_button}
function create_condition_row(parent, rule_index, condition, is_first, show_delete_button)
  condition = condition or {}
  is_first = is_first or (rule_index == 1)
  if show_delete_button == nil then show_delete_button = true end  -- Default to true

  local row_flow = parent.add{
    type = "flow",
    name = "condition_row_" .. rule_index,
    direction = "horizontal"
  }
  row_flow.style.horizontal_spacing = 4
  row_flow.style.vertical_align = "center"
  row_flow.style.bottom_margin = 4

  -- AND/OR toggle button (only for non-first conditions)
  local and_or_button = nil
  if not is_first then
    -- Determine current logical operator (default to AND)
    local logical_op = condition.logical_op or "AND"
    local is_or = (logical_op == "OR")

    -- Create toggle button
    and_or_button = row_flow.add{
      type = "button",
      name = "cond_" .. rule_index .. "_and_or_toggle",
      caption = logical_op,
      tooltip = is_or and {"gui.switch-to-and"} or {"gui.switch-to-or"},
      style = "button",
      style_mods = {
        minimal_width = 50,
        height = 28
      }
    }

    -- Apply left padding for OR conditions (visual precedence indicator)
    if is_or then
      row_flow.style.left_padding = 20  -- Left-shift OR rows
    end
  end

  -- Left wire filter checkboxes (R/G)
  local left_wire_filter = create_wire_filter_checkboxes(row_flow, "cond_" .. rule_index .. "_left_wire_")

  local states = get_checkboxes_from_wire_filter(condition.left_wire_filter)
  left_wire_filter.red_checkbox.state = states.red
  left_wire_filter.green_checkbox.state = states.green

  -- Left signal selector
  local left_signal = row_flow.add{
    type = "choose-elem-button",
    name = "cond_" .. rule_index .. "_left_signal",
    elem_type = "signal",
    signal = condition.left_signal,  -- Use 'signal' parameter during creation, not 'elem_value'
    tooltip = {"gui.condition-left-signal-tooltip"}
  }
  left_signal.style.width = 40
  left_signal.style.height = 40

  -- Operator dropdown
  local operator_dropdown = row_flow.add{
    type = "drop-down",
    name = "cond_" .. rule_index .. "_operator",
    tooltip = {"gui.condition-operator-tooltip"}
  }
  populate_operator_dropdown(operator_dropdown)
  if condition.operator then
    operator_dropdown.selected_index = get_index_from_operator(condition.operator)
  end
  operator_dropdown.style.width = 60

  -- Right type toggle (constant vs signal)
  local right_type_toggle = row_flow.add{
    type = "sprite-button",
    name = "cond_" .. rule_index .. "_right_type_toggle",
    sprite = (condition.right_type == "signal") and "utility/custom_tag_icon" or "utility/slot",
    tooltip = (condition.right_type == "signal") and {"gui.switch-to-constant"} or {"gui.switch-to-signal"},
    style = "slot_button"
  }
  right_type_toggle.style.width = 28
  right_type_toggle.style.height = 28

  -- Right value container (for constant)
  local right_value = row_flow.add{
    type = "textfield",
    name = "cond_" .. rule_index .. "_right_value",
    text = tostring(condition.right_value or 0),
    numeric = true,
    allow_negative = true,
    visible = (condition.right_type ~= "signal"),  -- Hidden when signal mode
    tooltip = {"gui.condition-value-tooltip"}
  }
  right_value.style.width = 80

  -- Right signal selector (for signal comparison)
  local right_signal = row_flow.add{
    type = "choose-elem-button",
    name = "cond_" .. rule_index .. "_right_signal",
    elem_type = "signal",
    signal = condition.right_signal,
    visible = (condition.right_type == "signal"),  -- Visible only in signal mode
    tooltip = {"gui.condition-right-signal-tooltip"}
  }
  right_signal.style.width = 40
  right_signal.style.height = 40

  -- Right wire filter (only for signal mode)
  local right_wire_filter = create_wire_filter_checkboxes(row_flow, "cond_" .. rule_index .. "_right_wire_")
  right_wire_filter.flow.visible = (condition.right_type == "signal")

  -- Set checkbox states from existing condition

  local states = get_checkboxes_from_wire_filter(condition.right_wire_filter)
  right_wire_filter.red_checkbox.state = states.red
  right_wire_filter.green_checkbox.state = states.green

  -- Delete button (optional, based on parameter)
  local delete_button = nil
  if show_delete_button then
    delete_button = row_flow.add{
      type = "sprite-button",
      name = "cond_" .. rule_index .. "_delete",
      sprite = "utility/close",
      tooltip = {"gui.delete-condition"},
      style = "tool_button_red"
    }
    delete_button.style.width = 28
    delete_button.style.height = 28
  end

  return {
    flow = row_flow,
    and_or_button = and_or_button,
    left_wire_filter = left_wire_filter,
    left_signal = left_signal,
    operator = operator_dropdown,
    right_type_toggle = right_type_toggle,
    right_value = right_value,
    right_signal = right_signal,
    right_wire_filter = right_wire_filter,
    delete_button = delete_button
  }
end

--- Get wire filter from checkbox states
-- Converts checkbox states to wire filter string
-- @param red_enabled boolean: Red checkbox state
-- @param green_enabled boolean: Green checkbox state
-- @return string: "red", "green", "both", or "none"
function get_wire_filter_from_checkboxes(red_enabled, green_enabled)
  if red_enabled and green_enabled then
    return "both"
  elseif red_enabled then
    return "red"
  elseif green_enabled then
    return "green"
  else
    return "none"  -- Invalid state, but handle it
  end
end

--- Set checkbox states from wire filter
-- Converts wire filter string to checkbox states
-- @param wire_filter string: "red", "green", or "both"
-- @return table: {red = boolean, green = boolean}
function get_checkboxes_from_wire_filter(wire_filter)
  if wire_filter == "both" then
    return {red = true, green = true}
  elseif wire_filter == "red" then
    return {red = true, green = false}
  elseif wire_filter == "green" then
    return {red = false, green = true}
  else
    -- Default to both if unknown
    return {red = true, green = true}
  end
end

--- Update visual layout of condition rows based on AND/OR mix
-- Applies left-shift to OR condition rows when mixed with AND conditions
-- @param parent LuaGuiElement: Parent element containing condition rows
-- @param conditions table: Array of conditions with logical_op fields
function update_condition_row_styles(parent, conditions)
  if not parent or not parent.valid or not conditions then return end

  -- Check if we have mixed AND/OR operators
  local has_and = false
  local has_or = false

  for i, cond in ipairs(conditions) do
    if i > 1 then  -- Skip first condition (no logical_op)
      if cond.logical_op == "AND" then
        has_and = true
      elseif cond.logical_op == "OR" then
        has_or = true
      end
    end
  end

  local is_mixed = has_and and has_or

  -- Update each row's style
  for i, cond in ipairs(conditions) do
    local row_flow = parent["condition_row_" .. i]
    if row_flow and row_flow.valid then
      -- Apply left-shift only to OR rows when mixed
      if i > 1 and cond.logical_op == "OR" and is_mixed then
        row_flow.style.left_padding = 20
      else
        row_flow.style.left_padding = 0
      end
    end
  end
end

--- Create condition result indicator
-- Creates a status indicator showing true/false for condition evaluation
-- @param parent LuaGuiElement: Parent container
-- @param name string: Name for the indicator element
-- @return table: {flow, sprite, label}
function create_condition_indicator(parent, name)
  local indicator_flow = parent.add{
    type = "flow",
    name = name .. "_flow",
    direction = "horizontal"
  }
  indicator_flow.style.horizontal_spacing = 4
  indicator_flow.style.vertical_align = "center"

  indicator_flow.add{
    type = "label",
    caption = "Condition: "
  }

  local sprite = indicator_flow.add{
    type = "sprite",
    name = name .. "_sprite",
    sprite = "utility/status_not_working"  -- Default: false (red X)
  }

  local label = indicator_flow.add{
    type = "label",
    name = name .. "_label",
    caption = "False"
  }

  return {
    flow = indicator_flow,
    sprite = sprite,
    label = label
  }
end

--- Update condition indicator state
-- Updates the visual state of a condition indicator
-- @param sprite LuaGuiElement: Sprite element
-- @param label LuaGuiElement: Label element
-- @param state boolean: True/false state to display
function update_condition_indicator(sprite, label, state)
  if sprite and sprite.valid then
    sprite.sprite = state and "utility/status_working" or "utility/status_not_working"
  end

  if label and label.valid then
    label.caption = state and "[color=green]True[/color]" or "[color=red]False[/color]"
  end
end

-- ==============================================================================
-- EXPORTS
-- ==============================================================================

return {
  -- Constants
  GUI_CONSTANTS = GUI_CONSTANTS,

  -- Component creation
  create_titlebar = create_titlebar,
  create_button_row = create_button_row,
  create_status_label = create_status_label,
  create_condition_selector = create_condition_selector,
  create_wire_filter_checkboxes = create_wire_filter_checkboxes,
  create_condition_row = create_condition_row,
  create_condition_indicator = create_condition_indicator,

  -- Utility functions
  find_child_recursive = find_child_recursive,
  close_gui_for_player = close_gui_for_player,
  update_condition_indicator = update_condition_indicator,
  update_condition_row_styles = update_condition_row_styles,

  -- Wire filter utilities
  get_wire_filter_from_checkboxes = get_wire_filter_from_checkboxes,
  get_checkboxes_from_wire_filter = get_checkboxes_from_wire_filter,

  -- Operator utilities
  populate_operator_dropdown = populate_operator_dropdown,
  get_operator_from_index = get_operator_from_index,
  get_index_from_operator = get_index_from_operator,

  -- Signal validation (for GUI feedback)
  validate_condition_signal = validate_condition_signal,
  validate_right_signal = validate_right_signal
}
