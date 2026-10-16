-- Ghost Combinator Item Prototype
-- Factorio 2.0 API

data:extend({
    {
        type = "item",
        name = "ghost-combinator",
        -- Custom ghost combinator icon
        icon = "__updated-ghost-combinator__/graphics/entities/ghost-combinator-icon.png",
        icon_size = 64,
        -- Place in circuit network category
        subgroup = "circuit-network",
        order = "c[combinators]-g[ghost-combinator]",
        -- Link to entity prototype
        place_result = "ghost-combinator",
        -- Stack size (standard for combinators)
        stack_size = 50
    }
})
