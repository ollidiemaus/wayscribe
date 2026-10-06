local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local Codec = Stubs.LoadAddon().Codec

describe("ints", function()
    it("round-trips positives, negatives and large values", function()
        local values = { 0, 1, -1, 15, 16, -16, 31, 32, -32, 1000, -1000, 123456789, -987654321, 2 ^ 40 }
        T.same(Codec.DecodeInts(Codec.EncodeInts(values)), values)
    end)

    it("encodes small numbers in one character", function()
        T.eq(#Codec.EncodeInts({ 0, 1, -1, 7, -8 }), 5)
    end)

    it("handles an empty list", function()
        T.eq(Codec.EncodeInts({}), "")
        T.same(Codec.DecodeInts(""), {})
    end)

    it("only uses characters that need no escaping in SavedVariables", function()
        local text = Codec.EncodeInts({ -5000, 77, 123456, -1, 0, 99999999 })
        T.truthy(text:match("^[A-Za-z0-9_%-]+$"), "unexpected character in " .. text)
    end)

    it("refuses non-integers", function()
        T.errors(function() Codec.EncodeInts({ 1.5 }) end, "integers")
        T.errors(function() Codec.EncodeInts({ "7" }) end, "integers")
    end)

    it("rejects malformed input instead of guessing", function()
        local list, reason = Codec.DecodeInts("ab\"c")
        T.eq(list, nil)
        T.truthy(reason:find("invalid character"))
        -- "g" (32) means "more characters follow" but nothing does
        list, reason = Codec.DecodeInts("g")
        T.eq(list, nil)
        T.truthy(reason:find("truncated"))
    end)
end)

describe("paths", function()
    it("round-trips a trail of x,y points", function()
        local points = { 1200, -3400, 1208, -3396, 1215, -3390, 1215, -3390, 900, -2800 }
        T.same(Codec.DecodePath(Codec.EncodePath(points)), points)
    end)

    it("keeps nearby points short thanks to delta encoding", function()
        local points = {}
        for i = 0, 99 do
            points[#points + 1] = 10000 + i * 6
            points[#points + 1] = -20000 + i * 5
        end
        local text = Codec.EncodePath(points)
        T.same(Codec.DecodePath(text), points)
        -- 100 points: first one is large, the rest take one character per coordinate
        T.truthy(#text < 210, "trail too long: " .. #text)
    end)

    it("requires complete pairs", function()
        T.errors(function() Codec.EncodePath({ 1, 2, 3 }) end, "pairs")
        local points, reason = Codec.DecodePath(Codec.EncodeInts({ 1, 2, 3 }))
        T.eq(points, nil)
        T.truthy(reason:find("odd"))
    end)
end)
