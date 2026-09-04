--[[----------------------------------------------------------------------------
    .luacheckrc for the Ghost Combinator mod (Factorio 2.1)

    Adapted from the shared config used across the mod family, with three
    deliberate differences:

      1. `global` is BANNED, not whitelisted. It is the Factorio 1.1 name for
         what 2.0 calls `storage`, and CLAUDE.md makes avoiding 1.1-isms the
         project's top rule. Listing it in not_globals turns a silent 1.1-ism
         into a lint error. The 2.0 names -- storage, prototypes, helpers --
         are declared instead.

      2. Undefined-global detection (111/112/113) is ENABLED. The family config
         ignores those codes, which makes its own globals lists decorative.
         Leaving them on is the only way a typo'd API name gets caught.

      3. `mod/lib/` may not touch `storage`, enforcing the stateless-lib rule in
         docs/module_responsibility_matrix.md as a lint rule rather than a
         convention. Verified true of the current tree.

    NOTE: no luacheck binary exists on the current dev machine, so this config
    has never actually been executed. Expect to tune it on first run.
----------------------------------------------------------------------------]]

std = "lua52c"
quiet = 1                       -- Only report warnings and errors
codes = true                    -- Show warning codes
max_line_length = false         -- Managed in code review, not by the linter
max_code_line_length = false
max_string_line_length = false
max_comment_line_length = false
max_cyclomatic_complexity = false

-- Style-only codes that produce noise without catching defects.
ignore = {
    "211",        -- Unused local variable
    "212",        -- Unused argument
    "213",        -- Unused loop variable
    "21./^_",     -- Anything intentionally named with a leading underscore
    "43.",        -- Shadowing an upvalue
    "542",        -- Empty if branch (sometimes intentional)
}

-- Not available in the Factorio sandbox, or forbidden by project rules.
not_globals = {
    "global",     -- Factorio 1.1. Use `storage`.
    "coroutine",
    "io",
    "os",
    "socket",
    "dofile",
    "loadfile",
}

-- Baseline: the Factorio API surface this mod may touch anywhere.
globals = {
    -- Data stage
    "data",
    -- Runtime stage (Factorio 2.0 names)
    "game",
    "script",
    "storage",
    "commands",
    "remote",
    "rcon",
    "rendering",
}

read_globals = {
    "defines",
    "prototypes",     -- 2.0 replacement for game.entity_prototypes et al.
    "helpers",
    "mods",
    "settings",
    "util",
    "log",
    "serpent",
    "table_size",
    "localised_print",
}

files = {}

-- Data stage: prototype definitions only. No runtime API at all.
-- Matches mod/data.lua and mod/data-final-fixes.lua.
files["mod/data*.lua"] = {
    globals = { "data" },
    read_globals = { "util", "mods", "settings", "defines", "log", "serpent" },
}

files["mod/settings*.lua"] = {
    globals = { "data" },
    read_globals = { "util", "mods", "settings", "defines", "log" },
}

-- prototypes/ includes derive_cost.lua, which reads data.raw and calls log().
files["mod/prototypes/"] = {
    globals = { "data" },
    read_globals = { "util", "mods", "settings", "defines", "log", "serpent" },
    max_line_length = 200,   -- Prototype data tables run long
}

-- Runtime entry point: owns event registration and console commands.
files["mod/control.lua"] = {
    globals = { "game", "script", "storage", "commands", "remote", "rcon", "rendering" },
    read_globals = { "defines", "prototypes", "helpers", "settings", "util",
                     "log", "serpent", "table_size", "localised_print" },
}

-- Stateful modules: these own `storage`.
files["mod/scripts/"] = {
    globals = { "game", "script", "storage", "remote", "rendering" },
    read_globals = { "defines", "prototypes", "helpers", "settings", "util",
                     "log", "serpent", "table_size", "localised_print" },
}

-- Stateless libraries. `storage` is deliberately absent: per
-- docs/module_responsibility_matrix.md, lib/ never touches it.
files["mod/lib/"] = {
    globals = {},
    read_globals = { "defines", "prototypes", "helpers", "game", "script",
                     "util", "log", "serpent", "table_size" },
}

-- KNOWN DEBT: gui_utils.lua declares 18 top-level functions as globals rather
-- than locals. Tracked in docs/todo.md as an upstream fix for ../FactorioBaseMod,
-- since the file is shared byte-identically across the mod family. Exempted here
-- so lint passes today; delete this block once the base mod is fixed and re-synced.
files["mod/lib/gui_utils.lua"] = {
    globals = { "helpers" },
    ignore = { "111", "112", "113" },
}

files["mod/migrations/"] = {
    globals = { "game", "script", "storage" },
    read_globals = { "defines", "prototypes", "helpers", "util", "log" },
    ignore = { "212", "213", "432" },
}

files["**/test*.lua"] = {
    std = "+busted",
    globals = { "describe", "it", "before_each", "after_each", "setup", "teardown" },
}

exclude_files = {
    "**/.git/",
    "**/.trash/",
    "**/.history/",
    "**/node_modules/",
    "**/dist/",
    "**/.vscode/",
    "**/docs/",
    "**/*_nolint*",
}
