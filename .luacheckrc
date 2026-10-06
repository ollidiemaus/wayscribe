std = "lua51"
max_line_length = 140
self = false -- methods often ignore self (event handlers, mixin-style APIs)
-- .lua/, .luarocks/ and .install/ are the toolchains the CI actions install into the workspace.
exclude_files = { ".git/", ".release/", "Libs/", ".lua/", ".luarocks/", ".install/" }

-- Globals the addon defines.
globals = {
    "WayscribeDB",
    "WayscribeCharDB",
    "SLASH_WAYSCRIBE1",
    "SLASH_WAYSCRIBE2",
    "SlashCmdList",
    "StaticPopupDialogs",
    "BINDING_HEADER_WAYSCRIBE",
    "BINDING_NAME_WAYSCRIBE_TOGGLE",
    "Wayscribe_OnAddonCompartmentClick",
    "Wayscribe_ToggleJournal",
}

-- WoW API the addon reads. Keep this list explicit: an unexpected global is usually a typo.
read_globals = {
    -- Lua extensions in the WoW client
    "date", "time", "tinsert", "issecretvalue", "geterrorhandler",
    -- Frames and UI
    "CreateFrame", "UIParent", "UISpecialFrames", "DEFAULT_CHAT_FRAME",
    "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil", "ScrollBoxConstants",
    "Settings", "AddonCompartmentFrame",
    "CreateSettingsListSectionHeaderInitializer", "CreateSettingsButtonInitializer",
    "StaticPopup_Show", "ReloadUI", "PlaySound", "SOUNDKIT", "GameTooltip",
    "SPELLBOOK_FONT_COLOR", "PAGE_NUMBER_WITH_MAX",
    -- Client and player info
    "GetBuildInfo", "GetLocale", "GetRealmName", "WOW_PROJECT_ID",
    "UnitGUID", "UnitFullName", "UnitClass", "UnitLevel", "UnitPosition",
    "IsInRaid", "GetNumGroupMembers", "GetNumSubgroupMembers",
    "GetInstanceInfo", "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
    "GetSpellInfo", "GetAddOnMetadata", "GetCVar",
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo",
    -- Namespaces
    "C_AddOns", "C_CVar", "C_EventUtils", "C_Item", "C_Map", "C_QuestLine", "C_QuestLog", "C_Spell", "C_Texture",
    "C_Timer", "C_TradeSkillUI", "C_XMLUtil",
    -- Libraries (optional, see embeds.xml)
    "LibStub",
}

files["Locales/"] = { max_line_length = false }

-- Tests replace the WoW API with stubs through _G.
files["tests/"] = {
    std = "max",
    ignore = { "111", "112", "113", "122", "142", "143" },
}
