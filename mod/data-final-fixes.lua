-- Ghost Combinator Mod - Data Final Fixes Stage
--
-- Runs after every other mod's data.lua and data-updates.lua, so anything here
-- sees final prototype values rather than vanilla ones.

-- Re-derive the technology's research cost from its (possibly re-costed)
-- prerequisites, and prune prerequisites that another mod removed.
require("prototypes.technology.derive_cost")
