-- Usage (from the repository root): lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local T = require("testlib")

local SPECS = {
    "codec", "time", "compat", "recordtypes", "module", "store", "index", "schema",
    "session", "level", "lifecycle",
}

for _, name in ipairs(SPECS) do
    T.describe(name, function()
        dofile("tests/" .. name .. "_spec.lua")
    end)
end

os.exit(T.report())
