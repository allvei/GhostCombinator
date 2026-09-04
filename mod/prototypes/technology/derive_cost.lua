-- Ghost Combinator — derive research cost from prerequisites
--
-- Runs in data-final-fixes so it observes the FINAL state of this technology's
-- prerequisites, after every other mod's data.lua and data-updates.lua have had
-- their say. Overhaul mods routinely re-cost vanilla technologies; this keeps the
-- Ghost Combinator in step with whatever they decided rather than shipping a
-- fixed, vanilla-only number.
--
-- Rule (reproduces the literal values in technologies.lua on vanilla):
--   ingredients = union of the prerequisites' science pack types,
--                 each at the HIGHER of the amounts seen
--   count       = the higher of the prerequisites' counts
--   time        = the higher of the prerequisites' times
--
-- The prerequisite LIST is read as it stands at final fixes rather than from a
-- hardcoded copy. technologies.lua declares construction-robotics and
-- circuit-network, but if another mod re-parented this technology, that is
-- honoured instead of being overwritten. Entries naming a technology that no
-- longer exists are dropped, because a dangling prerequisite is a hard load error.
--
-- Factorio 2.0 API: https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html

local TECH_NAME = "ghost-combinator"

--- Normalize one technology unit's ingredient list into name -> amount.
--- Handles both accepted shapes: the array shorthand `{"pack-name", 1}` used by
--- vanilla, and the explicit `{name = "pack-name", amount = 1}` form some mods use.
--- A pack listed twice in one unit collapses to the higher amount.
---@param ingredients table|nil Raw `unit.ingredients` from a technology prototype
---@return table<string, number> amounts Science pack name -> amount per cycle
---@return string[] order Pack names in the order first encountered
local function normalize_ingredients(ingredients)
    local amounts, order = {}, {}
    if type(ingredients) ~= "table" then return amounts, order end

    for _, ingredient in ipairs(ingredients) do
        local name, amount
        if type(ingredient) == "table" then
            name = ingredient[1] or ingredient.name
            amount = ingredient[2] or ingredient.amount
        end
        if type(name) == "string" then
            amount = tonumber(amount) or 1
            if not amounts[name] then
                order[#order + 1] = name
                amounts[name] = amount
            elseif amount > amounts[name] then
                amounts[name] = amount
            end
        end
    end

    return amounts, order
end

--- Recompute the Ghost Combinator technology's cost from its prerequisites.
--- Every failure path leaves the prototype's shipped values in place, so the mod
--- always loads with a valid cost.
local function derive_cost()
    local tech = data.raw.technology[TECH_NAME]
    if not tech then return end

    -- A trigger-researched technology has no `unit`, and declaring both `unit`
    -- and `research_trigger` is invalid. If another mod converted this
    -- technology, there is no cost to derive.
    if tech.research_trigger then
        log("[ghost-combinator] technology uses research_trigger; leaving it alone.")
        return
    end

    -- Preserve the prerequisite list as it stands — including anything another
    -- mod added — minus entries whose technology no longer exists.
    local prereqs = {}
    for _, name in ipairs(tech.prerequisites or {}) do
        if data.raw.technology[name] then
            prereqs[#prereqs + 1] = name
        else
            log("[ghost-combinator] prerequisite technology '" .. tostring(name) ..
                "' does not exist; dropping it from prerequisites.")
        end
    end
    tech.prerequisites = prereqs

    local amounts, order, seen = {}, {}, {}
    local count, time = 0, 0
    local saw_count_formula = false

    for _, name in ipairs(prereqs) do
        local unit = data.raw.technology[name].unit
        if unit then
            -- Infinite / formula-costed technologies have no plain `count`. There
            -- is no meaningful max against a formula, so their count is skipped
            -- while their ingredients and time still contribute.
            if type(unit.count) == "number" then
                if unit.count > count then count = unit.count end
            elseif unit.count_formula then
                saw_count_formula = true
            end

            if type(unit.time) == "number" and unit.time > time then
                time = unit.time
            end

            local src_amounts, src_order = normalize_ingredients(unit.ingredients)
            for _, pack in ipairs(src_order) do
                if not seen[pack] then
                    seen[pack] = true
                    order[#order + 1] = pack
                end
                if src_amounts[pack] > (amounts[pack] or 0) then
                    amounts[pack] = src_amounts[pack]
                end
            end
        end
    end

    -- Nothing to derive from: no prerequisites left, or every one of them is
    -- trigger-researched. Re-validate what the prototype already ships instead,
    -- leaving count and time at zero so its own values survive below.
    if #order == 0 then
        log("[ghost-combinator] prerequisites yielded no science packs; " ..
            "validating the prototype's own ingredients instead.")
        amounts, order = normalize_ingredients(tech.unit and tech.unit.ingredients)
    end

    -- Technology ingredients must name `tool` prototypes. A modset that removed a
    -- vanilla science pack would otherwise fail the load on a stale entry.
    local ingredients = {}
    for _, pack in ipairs(order) do
        if data.raw.tool and data.raw.tool[pack] then
            ingredients[#ingredients + 1] = { pack, amounts[pack] }
        else
            log("[ghost-combinator] '" .. pack .. "' is not a tool prototype; " ..
                "omitting it from the research cost.")
        end
    end

    if #ingredients == 0 then
        log("[ghost-combinator] no valid science packs available; leaving the " ..
            "technology's cost untouched.")
        return
    end

    tech.unit = tech.unit or {}
    tech.unit.ingredients = ingredients
    -- Never write a zero count/time — that is an invalid prototype. If every
    -- source was formula-costed or timeless, keep whatever the prototype shipped.
    if count > 0 then
        tech.unit.count = count
        tech.unit.count_formula = nil
    end
    if time > 0 then
        tech.unit.time = time
    end

    if saw_count_formula then
        log("[ghost-combinator] a prerequisite uses count_formula; its count was " ..
            "excluded from the max.")
    end

    local summary = {}
    for _, entry in ipairs(ingredients) do
        summary[#summary + 1] = entry[1] .. " x" .. entry[2]
    end
    log("[ghost-combinator] research cost derived from {" ..
        table.concat(prereqs, ", ") .. "}: " ..
        tostring(tech.unit.count) .. " x " .. tostring(tech.unit.time) .. "s, " ..
        table.concat(summary, ", "))
end

derive_cost()
