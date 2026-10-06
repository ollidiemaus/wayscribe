local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local ns = Stubs.LoadAddon()
local RecordTypes = ns.RecordTypes

local def = RecordTypes:Register("TEST_THING", {
    version = 1,
    fields = { id = "number", name = "string?", roster = "table?" },
    render = function(data) return "thing " .. data.id end,
})

describe("registration", function()
    it("rejects duplicates and bad field types", function()
        T.errors(function() RecordTypes:Register("TEST_THING", { version = 1 }) end, "duplicate")
        T.errors(function() RecordTypes:Register("TEST_BAD", { version = 1, fields = { x = "float" } }) end, "unknown field type")
        T.errors(function() RecordTypes:Register("TEST_NOVERSION", {}) end, "version")
    end)
end)

describe("validation", function()
    it("accepts required plus optional fields", function()
        T.truthy(RecordTypes:Validate(def, { id = 1 }))
        T.truthy(RecordTypes:Validate(def, { id = 1, name = "x", roster = { 3, 7 } }))
    end)

    it("rejects missing, mistyped and unknown fields", function()
        local ok, reason = RecordTypes:Validate(def, { name = "x" })
        T.falsy(ok)
        T.truthy(reason:find("missing field id"))
        ok, reason = RecordTypes:Validate(def, { id = "1" })
        T.falsy(ok)
        T.truthy(reason:find("should be a number"))
        ok, reason = RecordTypes:Validate(def, { id = 1, extra = true })
        T.falsy(ok)
        T.truthy(reason:find("unknown field extra"))
    end)

    it("never lets a secret value into the journal", function()
        local ok, reason = RecordTypes:Validate(def, { id = Stubs.SECRET })
        T.falsy(ok)
        T.truthy(reason:find("secret"))
        ok = RecordTypes:Validate(def, { id = 1, roster = { 1, Stubs.SECRET } })
        T.falsy(ok)
    end)

    it("rejects data the client can't save", function()
        T.falsy(RecordTypes:Validate(def, { id = 1, roster = { function() end } }))
        T.falsy(RecordTypes:Validate(def, { id = 1, roster = setmetatable({}, {}) }))
    end)
end)

describe("rendering", function()
    it("renders through the type", function()
        T.eq(RecordTypes:Render({ type = "TEST_THING", v = 1, data = { id = 4 } }), "thing 4")
    end)

    it("shows a placeholder for unknown types and broken renderers", function()
        T.eq(RecordTypes:Render({ type = "GONE", data = {} }), "(unreadable entry: GONE)")
        RecordTypes:Register("TEST_BROKEN", { version = 1, render = function() error("bug") end })
        T.eq(RecordTypes:Render({ type = "TEST_BROKEN", v = 1, data = {} }), "(unreadable entry: TEST_BROKEN)")
    end)

    it("upcasts old records on a copy", function()
        RecordTypes:Register("TEST_V3", {
            version = 3,
            fields = { level = "number" },
            upcast = {
                [1] = function(data) return { lvl = data.l } end,
                [2] = function(data) return { level = data.lvl } end,
            },
            render = function(data) return "level " .. data.level end,
        })
        local old = { type = "TEST_V3", v = 1, data = { l = 12 } }
        T.eq(RecordTypes:Render(old), "level 12")
        T.same(old.data, { l = 12 }, "stored record must not change")
    end)
end)

describe("categories", function()
    it("filters counter lines by category and keeps their order", function()
        local ns = Stubs.LoadAddon()
        local counters = { quests = { [840] = 2 }, skill = { [186] = 5 }, gather = { [2770] = 3 } }
        local lines = ns.RecordTypes:CounterLines(counters, function(category) return category ~= "gathering" end)
        T.eq(#lines, 2)
        T.eq(lines[1].category, "progress")
        T.eq(lines[2].category, "quests")
        T.eq(#ns.RecordTypes:RenderCounters(counters), 3)
    end)

    it("lists every category in use, with misc for unknown types", function()
        local ns = Stubs.LoadAddon()
        local seen = {}
        for _, category in ipairs(ns.RecordTypes:Categories()) do seen[category] = true end
        T.same(seen, { progress = true, adventure = true, quests = true, gathering = true })
        T.eq(ns.RecordTypes:CategoryOf("GONE"), "misc")
        T.eq(ns.RecordTypes:CounterCategory("gone"), "misc")
    end)
end)
