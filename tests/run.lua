-- Usage (from the repository root): lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local T = require("testlib")

local SPECS = {
    "codec", "geometry", "time", "compat", "recordtypes", "module", "store", "index", "schema",
    "session", "level", "professions", "gathering", "bosses", "dungeons", "questchains", "heropath",
    "journal", "footstepsmap", "loginrecap", "settings", "lifecycle",
}

for _, name in ipairs(SPECS) do
    T.describe(name, function()
        dofile("tests/" .. name .. "_spec.lua")
    end)
end

os.exit(T.report())
