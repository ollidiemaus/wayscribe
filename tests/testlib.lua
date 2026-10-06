-- Minimal test framework: no dependencies, runs on Lua 5.1 (WoW, CI) and newer.
local T = { passed = 0, failed = 0, failures = {}, path = {} }

function T.describe(name, fn)
    T.path[#T.path + 1] = name
    fn()
    T.path[#T.path] = nil
end

function T.it(name, fn)
    local fullName = table.concat(T.path, " > ") .. " > " .. name
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = fullName .. "\n    " .. tostring(err):gsub("\n", "\n    ")
    end
end

local function show(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

function T.eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
    end
end

function T.truthy(value, message)
    if not value then
        error((message or "expected a truthy value") .. ", got " .. show(value), 2)
    end
end

function T.falsy(value, message)
    if value then
        error((message or "expected a falsy value") .. ", got " .. show(value), 2)
    end
end

local function deepEqual(a, b, path)
    if type(a) ~= type(b) then
        return false, path .. ": " .. type(a) .. " vs " .. type(b)
    end
    if type(a) ~= "table" then
        if a == b then return true end
        return false, path .. ": " .. show(a) .. " vs " .. show(b)
    end
    for key, value in pairs(a) do
        local ok, where = deepEqual(value, b[key], path .. "." .. tostring(key))
        if not ok then return false, where end
    end
    for key in pairs(b) do
        if a[key] == nil then return false, path .. "." .. tostring(key) .. ": missing on the left" end
    end
    return true
end

function T.same(actual, expected, message)
    local ok, where = deepEqual(actual, expected, "value")
    if not ok then
        error((message or "tables differ") .. " at " .. where, 2)
    end
end

function T.errors(fn, pattern)
    local ok, err = pcall(fn)
    if ok then error("expected an error", 2) end
    if pattern and not tostring(err):find(pattern) then
        error("error " .. show(tostring(err)) .. " does not match " .. show(pattern), 2)
    end
end

function T.report()
    for _, failure in ipairs(T.failures) do
        print("FAIL " .. failure)
    end
    print(string.format("%d passed, %d failed", T.passed, T.failed))
    return T.failed == 0 and 0 or 1
end

return T
