-- Ghost Combinator Entity Prototype
-- A combinator that outputs signals based on ghost entity counts on the surface
-- Factorio 2.0 API

local flib_data_util = require("__flib__.data-util")

-- Copy constant combinator as base (1x1 size, read-only output)
local ghost_combinator = flib_data_util.copy_prototype(
    data.raw["constant-combinator"]["constant-combinator"],
    "ghost-combinator"
)

-- Basic properties
ghost_combinator.max_health = 150

-- NOTE: constant-combinator type does NOT support energy_source or active_energy_usage.
-- These properties are only valid on CombinatorPrototype (arithmetic/decider combinators)
-- and CraftingMachinePrototype descendants. Setting them here would be silently ignored
-- or cause the entity to be stuck in a permanent no_power status with no way to satisfy it.
-- The ghost combinator operates without power, consistent with vanilla constant combinators.

-- Minable configuration
ghost_combinator.minable = {
    mining_time = 0.1,
    result = "ghost-combinator"
}

-- Corpse configuration (reuse constant combinator remnants)
ghost_combinator.corpse = "constant-combinator-remnants"

-- Fast replaceable group
ghost_combinator.fast_replaceable_group = "ghost-combinator"

-- Ensure proper flags for player interaction
ghost_combinator.flags = {
    "placeable-player",
    "player-creation"
}

-- Custom sprites using ghost-combinator graphics
-- Uses same structure as constant combinator: 4-way spritesheet with base shadow
-- make_4way_animation_from_spritesheet is a global function defined by base in entities.lua
ghost_combinator.sprites = make_4way_animation_from_spritesheet({
    layers = {
        -- Main sprite layer (custom ghost combinator graphics)
        {
            scale = 0.5,
            filename = "__updated-ghost-combinator__/graphics/entities/ghost-combinator.png",
            width = 114,
            height = 102,
            shift = util.by_pixel(0, 5)
        },
        -- Shadow layer (reuse base constant combinator shadow)
        {
            scale = 0.5,
            filename = "__base__/graphics/entity/combinator/constant-combinator-shadow.png",
            width = 98,
            height = 66,
            shift = util.by_pixel(8.5, 5.5),
            draw_as_shadow = true
        }
    }
})

-- Add to data
data:extend({ghost_combinator})
