-- Technology Definitions for Mission Control Mod
-- Defines all technologies and their unlocks for the Ghost Combinator
--
-- This file extends the data phase with technology prototypes that gate access
-- to the mod's features behind research progression.
--
-- Factorio 2.0 API Reference: https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html

data:extend({
    {
        -- Technology type identifier (Factorio 2.0 prototype type)
        type = "technology",

        -- Internal name used for references and prerequisites
        -- Must match the name used in recipe unlocks and other references
        name = "ghost-combinator",

        -- Technology icon displayed in the research queue
        -- Custom ghost combinator icon
        -- icon_size MUST be specified when using icon (Factorio 2.0 requirement)
        icon = "__ghost-combinator__/graphics/entities/ghost-combinator-icon.png",
        icon_size = 64,  -- Standard icon size for technologies

        -- Technologies that must be researched before this one becomes available
        -- construction-robotics: ghosts only become a meaningful concept once
        --   construction bots exist, so this is the true functional gate
        -- circuit-network: the combinator's output is useless without wires
        -- Deliberately NOT logistic-system: overhaul mods (Pyanodons in particular)
        --   push it behind utility science, stranding this mod in the very late game
        prerequisites = {
            "construction-robotics",
            "circuit-network"
        },

        -- Research cost configuration.
        -- Derived from the two prerequisites: the union of their science pack
        -- types, each at the higher of the two amounts, and likewise for count
        -- and time.
        --
        -- These literals are the VANILLA result and act as the fallback. They are
        -- recomputed from the prerequisites' actual final values in
        -- `prototypes/technology/derive_cost.lua` (data-final-fixes), so overhaul
        -- mods that re-cost `construction-robotics` / `circuit-network` carry this
        -- technology along with them. Edit the rule there, not just here.
        --
        -- Verified against Factorio 2.1 base (data/base/prototypes/technology.lua):
        --   construction-robotics = 100 x 30s, automation/logistic/chemical 1 each
        --   circuit-network       = 100 x 15s, automation/logistic 1 each
        unit = {
            -- Number of research cycles required
            -- max(100, 100)
            count = 100,

            -- Science packs required per research cycle
            -- Each cycle consumes 1 of each pack listed below
            -- Factorio 2.0: Use full science pack names (not abbreviated)
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1}
            },

            -- Time in seconds for each research cycle
            -- max(30, 15)
            time = 30
        },

        -- Effects applied when technology is researched
        -- This unlocks the recipe for the ghost-combinator entity
        effects = {
            {
                type = "unlock-recipe",
                -- Recipe name must match the recipe prototype defined in prototypes/recipe/
                recipe = "ghost-combinator"
            }
        },

        -- Optional fields not used but available in Factorio 2.0:
        -- order: Controls sort order in technology tree (default: alphabetical)
        -- max_level: For infinite research (default: 1 for finite research)
        -- upgrade: Boolean for whether this is an upgrade tech (default: false)
        -- visible_when_disabled: Whether to show in tree before prerequisites (default: false)
    }
})
