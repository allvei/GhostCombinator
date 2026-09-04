-- Ghost Combinator Mod - Ghost Combinator GUI
-- This module handles the GUI for ghost combinator entity
-- Shows the selected category's counts as circuit signals, plus a mode selector

local flib_gui = require("__flib__.gui")
local gui_entity = require("lib.gui.gui_entity")
local gui_circuit_inputs = require("lib.gui.gui_circuit_inputs")
local entity_lib = require("lib.entity_lib")
local globals = require("scripts.globals")
local gc_storage = require("scripts.ghost_combinator.storage")
local gc_config = require("scripts.ghost_combinator.config")
-- Safe one-way dependency: control does not require gui, so there is no cycle.
local gc_control = require("scripts.ghost_combinator.control")

local gui = {}

-- Entity name constant
local GHOST_COMBINATOR = "ghost-combinator"

-- GUI element names
local GUI_FRAME_NAME = "ghost_combinator_gui"

-- GUI element name for the output mode selector
local MODE_DROPDOWN_NAME = "ghost_combinator_mode_dropdown"

--- Build the localised captions for the mode dropdown, in CATEGORIES order
--- @return table Array of LocalisedString captions
local function mode_dropdown_items()
    local items = {}
    for _, mode in ipairs(gc_storage.CATEGORIES) do
        items[#items + 1] = {"gui.ghost-combinator-mode-" .. mode}
    end
    return items
end

--- Convert one category's entries to the signal format the grid expects
--- Reads through the storage accessor rather than touching storage directly -
--- see docs/module_responsibility_matrix.md.
--- @param surface_index number The surface index
--- @param category string The category to display
--- @return table Array of signals in format {signal = SignalID, count = int}
local function get_category_signals(surface_index, category)
    local signals = {}

    local entries = gc_storage.get_entries(surface_index, category)
    if not entries then
        return signals
    end

    for _, entry in pairs(entries) do
        if entry and entry.count > 0 and entry.item_name then
            -- Use "item" signal type with the resolved item name
            table.insert(signals, {
                signal = { type = "item", name = entry.item_name, quality = entry.quality },
                count = entry.count
            })
        end
    end

    return signals
end

--- Create signal grid display for the combinator's selected category
--- @param parent LuaGuiElement Parent element to add grid to
--- @param entity LuaEntity The ghost combinator entity
local function create_signal_grid(parent, entity)
    if not entity or not entity.valid then
        return
    end

    local surface_index = entity.surface.index
    local mode = gc_config.get_mode(entity)
    local signals = get_category_signals(surface_index, mode)

    -- Use shared signal sub-grid from gui_circuit_inputs (no wire color for output display)
    return gui_circuit_inputs.create_signal_sub_grid(parent, signals, "none", "ghost_signal_grid")
end

--- Create the GUI for a ghost combinator
--- @param player LuaPlayer
--- @param entity LuaEntity The entity to create GUI for
--- @return table|nil Table of created elements, or nil on failure
function gui.create_gui(player, entity)
    if not player or not player.valid then
        return nil
    end

    if not entity or not entity.valid then
        return nil
    end

    -- Close existing GUI if open
    gui.close_gui(player)

    -- Get power status for entity
    local power_status = gui_entity.get_power_status(entity)

    -- Get surface name for display
    local surface = entity.surface
    local surface_name = surface.name
    if surface.planet then
        surface_name = surface.planet.prototype.localised_name or surface_name
    end

    -- Build GUI structure using flib
    local elems = flib_gui.add(player.gui.screen, {
        type = "frame",
        name = GUI_FRAME_NAME,
        direction = "vertical",
        tags = {
            entity_unit_number = entity.unit_number,
            entity_position = entity.position,
            entity_surface_index = entity.surface.index
        },
        children = {
            -- Titlebar
            {
                type = "flow",
                style = "flib_titlebar_flow",
                drag_target = GUI_FRAME_NAME,
                children = {
                    {
                        type = "label",
                        style = "frame_title",
                        caption = {"", "Ghost Combinator"},
                        ignored_by_interaction = true
                    },
                    { type = "empty-widget", style = "flib_titlebar_drag_handle", ignored_by_interaction = true },
                    {
                        type = "sprite-button",
                        name = "ghost_close_button",
                        style = "frame_action_button",
                        sprite = "utility/close",
                        hovered_sprite = "utility/close_black",
                        clicked_sprite = "utility/close_black",
                        tooltip = {"", "Close"},
                        tags = { action = "close" }
                    }
                }
            },
            -- Content frame
            -- `inside_shallow_frame` has no padding of its own, which left the
            -- status row flush against the frame's top and left edges. The
            -- _with_padding variant is the vanilla style for frame content
            -- (padding = 12) and is what the rest of the mod family uses.
            {
                type = "frame",
                style = "inside_shallow_frame_with_padding",
                direction = "vertical",
                children = {
                    -- Status indicator
                    {
                        type = "flow",
                        direction = "horizontal",
                        style_mods = {
                            vertical_align = "center",
                            bottom_margin = 8
                        },
                        children = {
                            {
                                type = "label",
                                caption = {"", "Status: "},
                                style_mods = {
                                    font = "default-semibold",
                                    right_margin = 4
                                }
                            },
                            {
                                type = "sprite",
                                name = "status_sprite",
                                sprite = power_status.sprite,
                                style_mods = {
                                    width = 16,
                                    height = 16,
                                    right_margin = 4
                                }
                            },
                            {
                                type = "label",
                                name = "status_label",
                                caption = power_status.text
                            }
                        }
                    },
                    -- Surface info
                    {
                        type = "flow",
                        direction = "horizontal",
                        style_mods = {
                            bottom_margin = 8
                        },
                        children = {
                            {
                                type = "label",
                                caption = {"", "Surface: "},
                                style_mods = {
                                    font = "default-semibold",
                                    right_margin = 4
                                }
                            },
                            {
                                type = "label",
                                caption = surface_name
                            }
                        }
                    },
                    -- Output mode selector
                    {
                        type = "flow",
                        direction = "horizontal",
                        style_mods = {
                            vertical_align = "center",
                            bottom_margin = 8
                        },
                        children = {
                            {
                                type = "label",
                                caption = {"gui.ghost-combinator-mode-header"},
                                tooltip = {"gui.ghost-combinator-mode-tooltip"},
                                style_mods = {
                                    font = "default-semibold",
                                    right_margin = 4
                                }
                            },
                            {
                                type = "drop-down",
                                name = MODE_DROPDOWN_NAME,
                                items = mode_dropdown_items(),
                                selected_index = gc_storage.mode_to_index(gc_config.get_mode(entity)),
                                tooltip = {"gui.ghost-combinator-mode-tooltip"},
                                tags = { action = "set_mode" },
                                style_mods = {
                                    minimal_width = 140
                                }
                            }
                        }
                    },
                    -- Signal section header
                    {
                        type = "flow",
                        direction = "horizontal",
                        style_mods = {
                            vertical_align = "center",
                            bottom_margin = 4
                        },
                        children = {
                            {
                                type = "label",
                                caption = {"", "Ghost Signals:"},
                                style_mods = {
                                    font = "default-semibold"
                                }
                            },
                            { type = "empty-widget", style = "flib_horizontal_pusher" },
                            {
                                type = "sprite-button",
                                name = "refresh_button",
                                style = "tool_button",
                                sprite = "utility/refresh",
                                tooltip = {"", "Refresh"},
                                tags = { action = "refresh" }
                            }
                        }
                    },
                    -- Signal grid frame
                    {
                        type = "frame",
                        name = "signal_grid_frame",
                        direction = "vertical",
                        style = "inside_shallow_frame",
                        style_mods = {
                            padding = 8
                        }
                        -- Signal grid will be added here
                    }
                }
            }
        }
    })

    -- Add signal grid
    if elems.signal_grid_frame then
        create_signal_grid(elems.signal_grid_frame, entity)
    end

    -- Center the GUI
    if elems[GUI_FRAME_NAME] then
        elems[GUI_FRAME_NAME].force_auto_center()
    end

    -- Make the GUI respond to ESC key by setting it as the player's opened GUI
    player.opened = elems[GUI_FRAME_NAME]

    -- Store GUI state via globals
    globals.set_player_gui_entity(player.index, entity, "ghost_combinator")

    return elems
end

--- Close the GUI for a player
--- @param player LuaPlayer
function gui.close_gui(player)
    if not player or not player.valid then
        return
    end

    local frame = player.gui.screen[GUI_FRAME_NAME]

    -- Capture BEFORE destroying: once frame.destroy() runs, the engine has
    -- already nulled player.opened and `frame` is invalid, so comparing them
    -- afterwards is always false and the reset below never fires.
    local was_opened = (frame and frame.valid and player.opened == frame)

    if frame and frame.valid then
        frame.destroy()
    end

    -- Clear the opened GUI reference
    if was_opened then
        player.opened = nil
    end

    -- Clear player GUI state via globals
    globals.clear_player_gui_entity(player.index)
end

--- Refresh the GUI display
--- @param player LuaPlayer
function gui.refresh_gui(player)
    if not player or not player.valid then
        return
    end

    local frame = player.gui.screen[GUI_FRAME_NAME]
    if not frame or not frame.valid then
        return
    end

    -- Get entity from stored state via globals
    local player_gui_state = globals.get_player_gui_state(player.index)
    if not player_gui_state then
        gui.close_gui(player)
        return
    end

    local entity = player_gui_state.open_entity

    if not entity or not entity.valid then
        gui.close_gui(player)
        return
    end

    -- Recreate the GUI to update signals
    gui.create_gui(player, entity)
end

-- GUI Event Handlers

--- Handle GUI click events
--- @param event EventData.on_gui_click
function gui.on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    local tags = element.tags
    if not tags or not tags.action then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    local action = tags.action

    if action == "close" then
        gui.close_gui(player)
    elseif action == "refresh" then
        gui.refresh_gui(player)
    end
end

--- Handle GUI opened event
--- @param event EventData.on_gui_opened
function gui.on_gui_opened(event)
    local entity = event.entity
    if not entity_lib.is_type(entity, GHOST_COMBINATOR) then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    -- Close the default entity GUI
    player.opened = nil

    -- Create our custom GUI
    gui.create_gui(player, entity)
end

--- Handle GUI closed event
--- @param event EventData.on_gui_closed
function gui.on_gui_closed(event)
    local element = event.element
    if not element or not element.valid then return end

    -- Check if this is our GUI
    if element.name ~= GUI_FRAME_NAME then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    gui.close_gui(player)
end

--- Handle GUI checkbox state changed event (stub - no checkboxes in this GUI)
--- @param event EventData.on_gui_checked_state_changed
function gui.on_gui_checked_state_changed(event)
    -- Ghost combinator GUI has no checkboxes, this is a no-op
    -- Kept for consistency with event registration in control.lua
end

--- Handle dropdown selection changes - the output mode selector
--- Dispatches on element.tags.action, matching the family's GUI idiom.
--- @param event EventData.on_gui_selection_state_changed
function gui.on_gui_selection_state_changed(event)
    local element = event.element
    if not element or not element.valid then return end

    local tags = element.tags
    if not tags or tags.action ~= "set_mode" then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    local player_gui_state = globals.get_player_gui_state(player.index)
    if not player_gui_state then
        gui.close_gui(player)
        return
    end

    local entity = player_gui_state.open_entity
    if not entity or not entity.valid then
        gui.close_gui(player)
        return
    end

    local mode = gc_storage.index_to_mode(element.selected_index)

    if gc_config.set_mode(entity, mode) then
        -- Slot numbering is per-category, so the combinator's existing output is
        -- meaningless for the new mode. Rebuild it wholesale rather than waiting
        -- for the incremental tick pass, which only writes *changed* entries and
        -- would leave the old category's values sitting in the section.
        if not entity_lib.is_ghost(entity) then
            gc_control.refresh_combinator(entity, mode)
        end
    end

    -- Repaint the signal grid for the newly selected category
    gui.refresh_gui(player)
end

return gui
