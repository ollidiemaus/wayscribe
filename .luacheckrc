std = "lua51"
max_line_length = 140
self = false -- methods often ignore self (event handlers, mixin-style APIs)
exclude_files = { ".git/", ".release/" }

-- Globals the addon defines.
globals = {
    "WayscribeDB",
    "WayscribeCharDB",
    "SLASH_WAYSCRIBE1",
    "SLASH_WAYSCRIBE2",
    "SlashCmdList",
}

-- WoW API the addon reads. Keep this list explicit: an unexpected global is usually a typo.
read_globals = {
    -- Lua extensions in the WoW client
    "date", "time", "tinsert", "issecretvalue", "geterrorhandler",
    -- Frames and UI
    "CreateFrame", "UIParent", "UISpecialFrames", "DEFAULT_CHAT_FRAME",
    "CreateScrollBoxListLinearView", "ScrollUtil", "Settings", "AddonCompartmentFrame",
    -- Client and player info
    "GetBuildInfo", "GetLocale", "GetRealmName", "WOW_PROJECT_ID",
    "UnitGUID", "UnitFullName", "UnitClass", "UnitLevel", "UnitPosition",
    "GetInstanceInfo", "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
    "GetLootSourceInfo", "GetAddOnMetadata",
    -- Namespaces
    "C_AddOns", "C_EventUtils", "C_Map", "C_QuestLine", "C_Timer",
}

files["Locales/"] = { max_line_length = false }

-- Tests replace the WoW API with stubs through _G.
files["tests/"] = {
    std = "max",
    ignore = { "111", "112", "113", "122", "142", "143" },
}
