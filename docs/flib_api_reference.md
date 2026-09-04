# FLib API Reference
## Ghost Combinator Mod - Quick Reference Guide

Documented against: flib 0.16.5 (`flib_0.16.5/`)

> ⚠️ `mod/info.json` declares `flib >= 0.17.2`. This reference was written against 0.16.5, so
> verify any signature here against the installed flib before relying on it.

This document provides a comprehensive reference for all FLib (Factorio Library) functions used in the Ghost Combinator mod. FLib is a collection of common utilities and helpers for Factorio mod development.

---

## Table of Contents

1. [GUI Module](#gui-module)
2. [GUI Templates Module](#gui-templates-module)
3. [On-Tick-N Module](#on-tick-n-module)
4. [Table Module](#table-module)
5. [Format Module](#format-module)
6. [Math Module](#math-module)
7. [Position Module](#position-module)
8. [Queue Module](#queue-module)
9. [Data Util Module](#data-util-module)
10. [Reverse Defines Module](#reverse-defines-module)
11. [Style Module](#style-module)

---

## GUI Module

**Import:** `local flib_gui = require("__flib__.gui")`

The GUI module provides utilities for building GUIs declaratively and handling GUI events.

### Core Functions

#### `flib_gui.add(parent, def, elems)`
Add a new child or children to the given GUI element.

**Parameters:**
- `parent` (LuaGuiElement): The parent GUI element
- `def` (table|array): The element definition or array of definitions
- `elems` (table, optional): Optional initial elems table

**Returns:**
- `elems` (table): Elements with names collected into this table
- `first` (LuaGuiElement): The first element created

**Example:**
```lua
local elems = flib_gui.add(player.gui.screen, {
  type = "frame",
  name = "my_frame",
  direction = "vertical",
  children = {
    {type = "label", caption = "Hello World"},
    {type = "button", name = "my_button", caption = "Click me"}
  }
})
-- Access elements by name
elems.my_frame.visible = true
elems.my_button.enabled = false
```

### GUI Element Definition Extensions

FLib extends the standard LuaGuiElement.add_param with these additional fields:

- **`children`** (array): Array of child element definitions
- **`style_mods`** (table): Modifications to make to the element's style
- **`elem_mods`** (table): Modifications to make to the element itself
- **`drag_target`** (string): Name of element to set as drag target
- **`handler`** (function|table): Event handler(s) to assign

**Example with extensions:**
```lua
{
  type = "button",
  name = "close_button",
  caption = "Close",
  style_mods = {
    width = 100,
    height = 30
  },
  elem_mods = {
    enabled = false
  },
  handler = on_close_clicked
}
```

### Event Handling

#### `flib_gui.add_handlers(new_handlers, wrapper, prefix)`
Add handler functions to the registry for use with `flib_gui.add`.

**Parameters:**
- `new_handlers` (table): Table of handler functions keyed by name
- `wrapper` (function, optional): Wrapper function called before handler
- `prefix` (string, optional): Prefix for handler names

**Example:**
```lua
local handlers = {
  on_close = function(e)
    e.element.parent.destroy()
  end,
  on_confirm = function(e)
    game.print("Confirmed!")
  end
}

flib_gui.add_handlers(handlers)
```

#### `flib_gui.dispatch(e)`
Dispatch the handler associated with this event and GUI element.

**Parameters:**
- `e` (EventData): GUI event data

**Returns:**
- `handled` (boolean): True if an event handler was called

**Example:**
```lua
script.on_event(defines.events.on_gui_click, function(e)
  flib_gui.dispatch(e)
end)
```

#### `flib_gui.handle_events()`
Handle all GUI events with `flib_gui.dispatch`. Will not overwrite existing handlers.

**Example:**
```lua
-- In control.lua
flib_gui.handle_events()
```

#### `flib_gui.format_handlers(input, existing)`
Format the given handlers for use in a GUI element's tags.

**Parameters:**
- `input` (function|table): Handler function or table of handlers
- `existing` (Tags, optional): Existing tags to merge with

**Returns:**
- `tags` (Tags): Tags table with handler information

**Example:**
```lua
player.gui.screen.add({
  type = "button",
  caption = "Click me!",
  tags = flib_gui.format_handlers({
    [defines.events.on_gui_click] = on_button_clicked
  })
})
```

---

## GUI Templates Module

**Import:** `local flib_gui_templates = require("__flib__.gui-templates")`

Provides pre-built GUI component templates.

### Functions

#### `flib_gui_templates.technology_slot(parent, technology, level, research_state, on_click, tags, index)`
Create and return a technology slot button.

**Parameters:**
- `parent` (LuaGuiElement): Parent element
- `technology` (LuaTechnology): Technology to display
- `level` (uint): Technology level
- `research_state` (TechnologyResearchState): Research state
- `on_click` (function, optional): Click handler
- `tags` (Tags, optional): Additional tags
- `index` (uint, optional): Index for insertion

**Returns:**
- `element` (LuaGuiElement): The created technology slot

---

## On-Tick-N Module

**Import:** `local flib_on_tick_n = require("__flib__.on-tick-n")`

Schedule tasks to be executed on specific future ticks.

### Functions

#### `flib_on_tick_n.init()`
Initialize the module's storage table. **Must be called in `on_init`.**

**Example:**
```lua
script.on_init(function()
  flib_on_tick_n.init()
end)
```

#### `flib_on_tick_n.add(tick, task)`
Add a task to execute on the given tick.

**Parameters:**
- `tick` (number): The tick to execute on
- `task` (any): Data representing this task (cannot be a function)

**Returns:**
- `ident` (table): Identifier for the task `{index, tick}`

**Example:**
```lua
-- Schedule a task for 5 seconds from now
local ident = flib_on_tick_n.add(game.tick + 300, {
  type = "rebuild_platform",
  platform_id = 123
})
```

#### `flib_on_tick_n.retrieve(tick)`
Retrieve the tasks for the given tick, if any. **Must be called during `on_tick`.**

**Parameters:**
- `tick` (number): The current tick

**Returns:**
- `tasks` (table|nil): Table of tasks (may have gaps, use `pairs`)

**Example:**
```lua
script.on_event(defines.events.on_tick, function(e)
  local tasks = flib_on_tick_n.retrieve(e.tick)
  if tasks then
    for _, task in pairs(tasks) do
      if task.type == "rebuild_platform" then
        handle_platform_rebuild(task.platform_id)
      end
    end
  end
end)
```

#### `flib_on_tick_n.remove(ident)`
Remove a scheduled task.

**Parameters:**
- `ident` (table): The identifier returned from `add()`

**Returns:**
- `success` (boolean): True if task was removed

---

## Table Module

**Import:** `local flib_table = require("__flib__.table")`

Extension of the Lua 5.2 table library with array and table utilities.

### Array Functions

#### `flib_table.array_copy(arr)`
Shallow copy an array's values into a new array (optimized for arrays).

**Example:**
```lua
local original = {1, 2, 3, 4}
local copy = flib_table.array_copy(original)
```

#### `flib_table.array_merge(arrays)`
Merge all of the given arrays into a single array.

**Parameters:**
- `arrays` (array): An array of arrays to merge

**Returns:**
- `output` (array): Merged array

**Example:**
```lua
local merged = flib_table.array_merge({
  {1, 2, 3},
  {4, 5, 6},
  {7, 8, 9}
})
-- Result: {1, 2, 3, 4, 5, 6, 7, 8, 9}
```

#### `flib_table.binary_search(array, comparator)`
Perform a binary search of the array using the given comparator function.

**Parameters:**
- `array` (array): Sorted array to search
- `comparator` (function): Function returning 0 (match), negative (before), or positive (after)

**Returns:**
- `index` (number|nil): Index of matched element
- `elem` (any|nil): The matched element

**Example:**
```lua
local nums = {1, 3, 4, 8, 20, 69}
local looking_for = 20
local i, match = flib_table.binary_search(nums, function(elem)
  return looking_for - elem
end)
-- i = 5, match = 20
```

### Table Functions

#### `flib_table.deep_copy(tbl)`
Recursively copy the contents of a table into a new table.

**Example:**
```lua
local original = {a = 1, b = {c = 2, d = 3}}
local copy = flib_table.deep_copy(original)
copy.b.c = 99  -- Does not affect original
```

#### `flib_table.deep_compare(tbl1, tbl2)`
Recursively compare two tables for inner equality.

**Returns:**
- `equal` (boolean): True if tables are equal

#### `flib_table.deep_merge(tables)`
Recursively merge two or more tables.

**Parameters:**
- `tables` (array): Array of tables to merge

**Returns:**
- `output` (table): Merged table

**Example:**
```lua
local tbl = flib_table.deep_merge({
  {foo = "bar", nested = {a = 1}},
  {foo = "baz", nested = {b = 2}},
  {set = 3}
})
-- Result: {foo = "baz", nested = {a = 1, b = 2}, set = 3}
```

#### `flib_table.find(tbl, value)`
Find and return the first key containing the given value.

**Returns:**
- `key` (any|nil): The first key corresponding to value

**Example:**
```lua
local tbl = {"foo", "bar", "baz"}
local key = flib_table.find(tbl, "bar")  -- Returns 2
```

#### `flib_table.for_each(tbl, callback)`
Call the given function for each item in the table.

**Parameters:**
- `tbl` (table): Table to iterate
- `callback` (function): Function receiving `(value, key)`, return truthy to halt

**Returns:**
- `halted` (boolean): True if callback returned truthy for any item

**Example:**
```lua
local has_even = flib_table.for_each({1, 2, 3, 4}, function(v)
  return v % 2 == 0
end)
```

#### `flib_table.filter(tbl, filter, array_insert)`
Create a filtered version of a table.

**Parameters:**
- `tbl` (table): Table to filter
- `filter` (function): Function receiving `(value, key)`, return truthy to include
- `array_insert` (boolean, optional): If true, result is an array of values

**Example:**
```lua
local tbl = {1, 2, 3, 4, 5, 6}
local evens = flib_table.filter(tbl, function(v) return v % 2 == 0 end, true)
-- Result: {2, 4, 6}
```

#### `flib_table.map(tbl, mapper)`
Create a transformed table using the output of a mapper function.

**Parameters:**
- `tbl` (table): Table to transform
- `mapper` (function): Function receiving `(value, key)`, returns new value

**Example:**
```lua
local tbl = {1, 2, 3, 4, 5}
local times_ten = flib_table.map(tbl, function(v) return v * 10 end)
-- Result: {10, 20, 30, 40, 50}
```

#### `flib_table.reduce(tbl, reducer, initial_value)`
"Reduce" a table's values into a single output value.

**Parameters:**
- `tbl` (table): Table to reduce
- `reducer` (function): Function receiving `(accumulator, value, key)`, returns new accumulator
- `initial_value` (any, optional): Initial accumulator value

**Example:**
```lua
local tbl = {10, 20, 30, 40, 50}
local sum = flib_table.reduce(tbl, function(acc, v) return acc + v end, 0)
-- Result: 150
```

#### `flib_table.shallow_copy(tbl, use_rawset)`
Shallowly copy the contents of a table into a new table.

#### `flib_table.shallow_merge(tables)`
Shallowly merge two or more tables.

#### `flib_table.invert(tbl)`
Invert the given table such that `[value] = key`.

**Example:**
```lua
local tbl = {"foo", "bar", "baz"}
local inverted = flib_table.invert(tbl)
-- Result: {foo = 1, bar = 2, baz = 3}
```

#### `flib_table.size(tbl)`
Retrieve the size of a table (uses Factorio's built-in `table_size`).

#### `flib_table.slice(arr, start, stop)`
Retrieve a shallow copy of a portion of an array (does not modify original).

**Example:**
```lua
local arr = {10, 20, 30, 40, 50, 60, 70, 80, 90}
local sliced = flib_table.slice(arr, 3, 7)
-- Result: {30, 40, 50, 60, 70}
```

#### `flib_table.splice(arr, start, stop)`
Extract a portion of an array (modifies original).

---

## Format Module

**Import:** `local flib_format = require("__flib__.format")`

Various string formatting functions.

### Functions

#### `flib_format.number(amount, append_suffix, fixed_precision)`
Format a number for display, adding commas and an optional SI suffix.

**Parameters:**
- `amount` (number): Number to format
- `append_suffix` (boolean, optional): Add SI suffix (k, M, G, T, etc.)
- `fixed_precision` (number, optional): Display with given width

**Returns:**
- `formatted` (string): Formatted number string

**Example:**
```lua
flib_format.number(1234567)           -- "1,234,567"
flib_format.number(1234567, true)     -- "1.2 M"
flib_format.number(1234567, true, 5)  -- "1.235 M"
```

**SI Suffixes:**
- k (kilo) = 1,000
- M (mega) = 1,000,000
- G (giga) = 1,000,000,000
- T (tera) = 1,000,000,000,000
- P, E, Z, Y, R, Q for larger values

#### `flib_format.time(tick, include_leading_zeroes)`
Convert the given tick (or game.tick) into "[hh:]mm:ss" format.

**Parameters:**
- `tick` (uint, optional): Tick to format (defaults to game.ticks_played)
- `include_leading_zeroes` (boolean, optional): Include leading zeroes

**Returns:**
- `formatted` (string): Time string

**Example:**
```lua
flib_format.time(3600 * 60)              -- "1:00:00"
flib_format.time(3600 * 60, true)        -- "01:00:00"
flib_format.time(1800 * 60)              -- "30:00"
```

---

## Math Module

**Import:** `local flib_math = require("__flib__.math")`

Extension of the Lua 5.2 math library.

### Constants

```lua
flib_math.deg_to_rad  -- π / 180 (multiply degrees to get radians)
flib_math.rad_to_deg  -- 180 / π (multiply radians to get degrees)
flib_math.radian      -- 2π (one full radian)

-- Integer limits
flib_math.max_int8    -- 127
flib_math.max_uint8   -- 255
flib_math.max_int16   -- 32,767
flib_math.max_uint16  -- 65,535
flib_math.max_int     -- 2,147,483,647
flib_math.max_uint    -- 4,294,967,295
flib_math.max_int53   -- 9,007,199,254,740,991
```

### Functions

#### `flib_math.round(num, divisor)`
Round a number to the nearest multiple of divisor.

**Parameters:**
- `num` (number): Number to round
- `divisor` (number, optional): Round to nearest multiple (default: 1)

**Example:**
```lua
flib_math.round(3.7)      -- 4
flib_math.round(3.2)      -- 3
flib_math.round(12, 5)    -- 10
flib_math.round(13, 5)    -- 15
```

#### `flib_math.clamp(x, min, max)`
Clamp a number between minimum and maximum values.

**Parameters:**
- `x` (number): Number to clamp
- `min` (number, optional): Minimum value (default: 0)
- `max` (number, optional): Maximum value (default: 1)

**Example:**
```lua
flib_math.clamp(5, 0, 10)   -- 5
flib_math.clamp(-5, 0, 10)  -- 0
flib_math.clamp(15, 0, 10)  -- 10
```

#### `flib_math.lerp(num1, num2, amount)`
Linearly interpolate between two numbers.

**Parameters:**
- `num1` (number): Start value
- `num2` (number): End value
- `amount` (number): Interpolation amount (clamped 0-1)

**Returns:**
- `result` (number): Interpolated value

**Example:**
```lua
flib_math.lerp(0, 100, 0.0)   -- 0
flib_math.lerp(0, 100, 0.5)   -- 50
flib_math.lerp(0, 100, 1.0)   -- 100
```

#### `flib_math.sum(set)`
Calculate the sum of a set of numbers.

**Example:**
```lua
flib_math.sum({1, 2, 3, 4, 5})  -- 15
```

#### `flib_math.mean(set)`
Calculate the mean (average) of a set of numbers.

**Example:**
```lua
flib_math.mean({1, 2, 3, 4, 5})  -- 3
```

#### `flib_math.maximum(set)` / `flib_math.minimum(set)`
Returns the maximum/minimum value from a set.

---

## Position Module

**Import:** `local flib_position = require("__flib__.position")`

Utilities for manipulating positions. All functions support both shorthand `{x, y}` and explicit `{x = x, y = y}` syntax.

### Arithmetic Functions

#### `flib_position.add(pos1, pos2)`
Add two positions.

**Example:**
```lua
local result = flib_position.add({x = 5, y = 10}, {x = 3, y = 2})
-- Result: {x = 8, y = 12}
```

#### `flib_position.sub(pos1, pos2)`
Subtract two positions.

#### `flib_position.mul(pos1, pos2)`
Multiply two positions.

#### `flib_position.div(pos1, pos2)`
Divide two positions.

### Comparison Functions

#### `flib_position.eq(pos1, pos2)`
Test if two positions are equal.

#### `flib_position.lt(pos1, pos2)` / `flib_position.le(pos1, pos2)`
Test if pos1 is less than / less than or equal to pos2.

#### `flib_position.gt(pos1, pos2)` / `flib_position.ge(pos1, pos2)`
Test if pos1 is greater than / greater than or equal to pos2.

### Utility Functions

#### `flib_position.distance(pos1, pos2)`
Calculate the distance between two positions.

**Example:**
```lua
local dist = flib_position.distance({x = 0, y = 0}, {x = 3, y = 4})
-- Result: 5
```

#### `flib_position.distance_squared(pos1, pos2)`
Calculate the squared distance (faster, useful for comparisons).

#### `flib_position.floor(pos)` / `flib_position.ceil(pos)`
Floor/ceil the position coordinates.

#### `flib_position.abs(pos)`
Return absolute value of coordinates.

#### `flib_position.lerp(pos1, pos2, amount)`
Linearly interpolate between two positions.

**Example:**
```lua
local midpoint = flib_position.lerp({x = 0, y = 0}, {x = 10, y = 10}, 0.5)
-- Result: {x = 5, y = 5}
```

### Conversion Functions

#### `flib_position.to_tile(pos)`
Convert a MapPosition to TilePosition by flooring.

#### `flib_position.to_chunk(pos)`
Convert a MapPosition/TilePosition to ChunkPosition by dividing by 32 and flooring.

#### `flib_position.from_chunk(pos)`
Convert a ChunkPosition to TilePosition by multiplying by 32.

---

## Queue Module

**Import:** `local flib_queue = require("__flib__.queue")`

Lua queue (double-ended queue) implementation.

### Functions

#### `flib_queue.new()`
Create a new queue.

**Returns:**
- `queue` (table): New queue object

**Example:**
```lua
local my_queue = flib_queue.new()
```

#### `flib_queue.push_back(queue, value)`
Push an element into the back of the queue.

#### `flib_queue.push_front(queue, value)`
Push an element into the front of the queue.

#### `flib_queue.pop_back(queue)`
Retrieve and remove an element from the back of the queue.

**Returns:**
- `value` (any|nil): The element, or nil if queue is empty

#### `flib_queue.pop_front(queue)`
Retrieve and remove an element from the front of the queue.

**Example:**
```lua
local queue = flib_queue.new()
flib_queue.push_back(queue, "first")
flib_queue.push_back(queue, "second")
flib_queue.push_back(queue, "third")

local val = flib_queue.pop_front(queue)  -- "first"
val = flib_queue.pop_front(queue)        -- "second"
```

#### `flib_queue.iter(queue)`
Iterate over a queue's elements from beginning to end.

**Example:**
```lua
for i, value in flib_queue.iter(my_queue) do
  game.print(value)
end
```

#### `flib_queue.iter_rev(queue)`
Iterate over a queue's elements from end to beginning.

#### `flib_queue.length(queue)`
Get the length of the queue.

---

## Data Util Module

**Import:** `local flib_data_util = require("__flib__.data-util")`

**Note:** This module is for **data stage** only (data.lua, prototypes).

### Functions

#### `flib_data_util.copy_prototype(prototype, new_name, remove_icon)`
Copy a prototype, assigning a new name and minable properties.

**Parameters:**
- `prototype` (table): Prototype to copy
- `new_name` (string): New name for the copy
- `remove_icon` (boolean, optional): Remove icon fields

**Returns:**
- `copy` (table): Copied prototype

**Example:**
```lua
local my_item = flib_data_util.copy_prototype(
  data.raw["item"]["iron-plate"],
  "my-special-iron-plate"
)
```

#### `flib_data_util.create_icons(prototype, new_layers)`
Copy prototype.icon/icons to a new fully defined icons array, optionally adding layers.

**Parameters:**
- `prototype` (table): Prototype with icon/icons
- `new_layers` (array, optional): Additional icon layers to add

**Returns:**
- `icons` (array|nil): Icons array, or nil if incorrectly defined

#### `flib_data_util.get_energy_value(energy_string)`
Convert an energy string to base unit value + suffix.

**Parameters:**
- `energy_string` (string): Energy string like "300kW" or "1.5MJ"

**Returns:**
- `value` (number|nil): Base energy value
- `unit` (string|nil): Unit ("W" or "J")

**Example:**
```lua
local value, unit = flib_data_util.get_energy_value("300kW")
-- value = 300000, unit = "W"
```

#### `flib_data_util.build_sprite(name, position, filename, size, mods)`
Build a sprite prototype from constituent parts.

### Constants

```lua
flib_data_util.empty_image         -- "__flib__/graphics/empty.png" (8x8)
flib_data_util.black_image         -- "__flib__/graphics/black.png" (1x1)
flib_data_util.planner_base_image  -- "__flib__/graphics/planner.png"
flib_data_util.dark_red_button_tileset  -- "__flib__/graphics/dark-red-button.png"
```

---

## Reverse Defines Module

**Import:** `local flib_reverse_defines = require("__flib__.reverse-defines")`

Provides reverse lookup for `defines` values (number → string name).

**Example:**
```lua
local controller_name = flib_reverse_defines.controllers[player.controller_type]
-- If controller_type = 0, returns "ghost"
```

**Note:** Type intellisense does not work for this module. Use sparingly.

---

## Style Module

**Location:** `flib_0.16.5/prototypes/style.lua`

**Note:** This module is for **data stage** only. It extends `data.raw["gui-style"].default` with custom FLib styles.

### Available Styles

#### Slot Button Styles
- `flib_slot_<color>` - Slot styles in various colors
- `flib_selected_slot_<color>` - Selected slot styles
- `flib_slot_button_<color>` - Slot button with glow
- `flib_standalone_slot_button_<color>` - Standalone slot button

**Colors:** default, grey, red, orange, yellow, green, cyan, blue, purple, pink

#### Button Styles
- `flib_selected_frame_action_button` - Selected frame action button
- `flib_selected_tool_button` - Selected tool button
- `flib_tool_button_light_green` - Light green tool button
- `flib_tool_button_dark_red` - Dark red tool button

#### Empty Widget Styles
- `flib_dialog_footer_drag_handle` - Drag handle for dialog footers
- `flib_dialog_titlebar_drag_handle` - Drag handle for titlebars
- `flib_titlebar_drag_handle` - Generic titlebar drag handle
- `flib_horizontal_pusher` - Horizontally stretchable spacer
- `flib_vertical_pusher` - Vertically stretchable spacer

#### Flow Styles
- `flib_indicator_flow` - Horizontal flow with vertical centering
- `flib_titlebar_flow` - Horizontal flow with 8px spacing

#### Frame Styles
- `flib_shallow_frame_in_shallow_frame` - Shallow nested frame

#### Image Styles
- `flib_indicator` - 16x16 stretched image

#### Label Styles
- `flib_frame_title` - Frame title label with adjusted padding

#### Line Styles
- `flib_subheader_horizontal_line` - Subheader separator line
- `flib_titlebar_separator_line` - Titlebar separator line

#### Scroll Pane Styles
- `flib_naked_scroll_pane` - Scroll pane with no border
- `flib_naked_scroll_pane_under_tabs` - For use under tabbed panes
- `flib_naked_scroll_pane_no_padding` - No padding variant
- `flib_shallow_scroll_pane` - Shallow border scroll pane

#### Tabbed Pane Styles
- `flib_tabbed_pane_with_no_padding` - Tabbed pane with no padding

#### Textfield Styles
- `flib_widthless_textfield` - Textfield with width = 0
- `flib_widthless_invalid_textfield` - Invalid variant
- `flib_titlebar_search_textfield` - Search field for titlebar

---

## Usage Examples

### Creating a GUI with Event Handlers

```lua
local flib_gui = require("__flib__.gui")

-- Define handlers
local gui_handlers = {
  close_window = function(e)
    e.element.parent.parent.destroy()
  end,
  confirm_action = function(e)
    local player = game.get_player(e.player_index)
    player.print("Action confirmed!")
  end
}

-- Register handlers
flib_gui.add_handlers(gui_handlers)

-- Create GUI
local function create_my_gui(player)
  local elems = flib_gui.add(player.gui.screen, {
    type = "frame",
    name = "my_window",
    direction = "vertical",
    children = {
      -- Titlebar
      {
        type = "flow",
        style = "flib_titlebar_flow",
        drag_target = "my_window",
        children = {
          {type = "label", style = "frame_title", caption = "My Window"},
          {type = "empty-widget", style = "flib_titlebar_drag_handle"},
          {
            type = "sprite-button",
            style = "frame_action_button",
            sprite = "utility/close_white",
            handler = gui_handlers.close_window
          }
        }
      },
      -- Content
      {
        type = "frame",
        style = "inside_shallow_frame",
        direction = "vertical",
        children = {
          {type = "label", caption = "Are you sure?"},
          {
            type = "button",
            name = "confirm_button",
            caption = "Confirm",
            handler = gui_handlers.confirm_action
          }
        }
      }
    }
  })

  elems.my_window.force_auto_center()
  return elems
end

-- Set up event handling
flib_gui.handle_events()
```

### Using On-Tick-N for Delayed Actions

```lua
local flib_on_tick_n = require("__flib__.on-tick-n")

script.on_init(function()
  flib_on_tick_n.init()
end)

-- Schedule something for 5 seconds from now
local function schedule_delayed_action()
  flib_on_tick_n.add(game.tick + 300, {
    type = "platform_check",
    platform_id = 123
  })
end

-- Process scheduled tasks
script.on_event(defines.events.on_tick, function(e)
  local tasks = flib_on_tick_n.retrieve(e.tick)
  if tasks then
    for _, task in pairs(tasks) do
      if task.type == "platform_check" then
        check_platform_status(task.platform_id)
      end
    end
  end
end)
```

### Table Utilities

```lua
local flib_table = require("__flib__.table")

-- Deep merge configurations
local default_config = {
  signals = {red = {}, green = {}},
  timeout = 60
}

local user_config = {
  signals = {red = {iron = 100}},
  custom_field = "value"
}

local final_config = flib_table.deep_merge({default_config, user_config})
-- Result: {
--   signals = {red = {iron = 100}, green = {}},
--   timeout = 60,
--   custom_field = "value"
-- }

-- Filter and map
local numbers = {1, 2, 3, 4, 5, 6}
local even_numbers = flib_table.filter(numbers, function(v) return v % 2 == 0 end, true)
local doubled = flib_table.map(even_numbers, function(v) return v * 2 end)
-- Result: {4, 8, 12}
```

---

## Module Selection Guide

**When building GUIs:**
- Use `flib_gui` for declarative GUI construction
- Use `flib_gui.add_handlers()` for event handling
- Use FLib styles from `prototypes/style.lua` for consistent appearance

**When working with tables:**
- Use `flib_table` for array/table operations
- Use `deep_copy` when you need to clone nested structures
- Use `filter`, `map`, `reduce` for functional-style transformations

**When formatting output:**
- Use `flib_format.number()` for readable number display
- Use `flib_format.time()` for tick-to-time conversion

**When scheduling tasks:**
- Use `flib_on_tick_n` instead of maintaining your own tick-based scheduler
- Avoid `on_tick` polling when possible

**When working with positions:**
- Use `flib_position` for position arithmetic and conversions
- Useful for platform/surface coordinate calculations

**When creating prototypes:**
- Use `flib_data_util` to copy and modify existing prototypes
- Use FLib style definitions for consistent GUI appearance

---

## Best Practices

1. **Initialize on_tick_n early:** Always call `flib_on_tick_n.init()` in `on_init`
2. **Register handlers once:** Call `flib_gui.add_handlers()` at the module level, not per-GUI
3. **Use deep_copy for configs:** When storing player-specific data that might be modified
4. **Prefer FLib styles:** Use predefined styles for consistency with vanilla UI
5. **Cache flib_table functions:** Store frequently-used functions in locals for performance
6. **Use storage, not global:** FLib uses `storage` (Factorio 2.0) instead of `global`

---

## Migration Notes (Factorio 2.0)

FLib 0.16.5 uses `storage` instead of `global` internally. When upgrading:
- `on_tick_n` stores data in `storage.__flib.on_tick_n`
- Your mod should also use `storage` for compatibility
- Migration module is deprecated; use Lua migration files instead

---

**End of FLib API Reference**

For complete documentation and examples, see the official FLib repository.