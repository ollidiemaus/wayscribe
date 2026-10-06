local _, ns = ...

-- Missing keys fall back to the key itself, so a forgotten translation shows up as
-- readable text instead of a Lua error.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- Dates: DD, MM and YYYY are replaced; everything else is kept as-is.
L.DATE_FORMAT = "YYYY-MM-DD"
-- Long dates: {weekday}, {day}, {month} and {year} are replaced.
L.DATE_LONG = "{weekday}, {month} {day}, {year}"
L.DATE_LIST = "{weekday} {day}"
L.DATE_MONTH = "{month} {year}"
L.WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
L.MONTHS = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}
L.TODAY = "Today"
L.YESTERDAY = "Yesterday"
-- The game's 24-hour clock setting wins; this is the default without one.
L.CLOCK_24H = false
L.CLOCK_AM = "AM"
L.CLOCK_PM = "PM"
L.DURATION_UNDER_MINUTE = "under a minute"
L.DURATION_MINUTES = "%d min"
L.DURATION_HOURS = "%d h %d min"

-- Lists: "A, B and C"
L.LIST_SEPARATOR = ", "
L.LIST_AND = "%s and %s"
L.LIST_OTHERS = "%d others"
L.LIST_MORE = "%d more"
L.IN_PARENTHESES = "(%s)"

L.ADDON_TITLE = "Wayscribe"
L.CLOSE = "Close"
L.CANCEL = "Cancel"

-- Journal
L.JOURNAL_TITLE = "Wayscribe"
L.JOURNAL_EMPTY = "Your journal is still empty. Go on an adventure!"
L.JOURNAL_NOTHING_SHOWN = "Nothing to show with these filters."
L.ENTRY_UNREADABLE = "(unreadable entry: %s)"
L.ENTRY_SIMULATED = "[sim]"
L.PAGE_PLAYED = "played %s"
L.PAGE_SESSIONS = "Sessions: %s"
L.PAGE_SESSION_RANGE = "%s - %s"
L.PAGE_NOW = "now"
L.PAGE_EMPTY = "Nothing on this page with these filters."
L.PAGE_OLDER = "< Older"
L.PAGE_NEWER = "Newer >"

-- Journal filters
L.CATEGORY_PROGRESS = "Progress"
L.CATEGORY_ADVENTURE = "Adventure"
L.CATEGORY_QUESTS = "Quests"
L.CATEGORY_GATHERING = "Gathering"

-- Trackers and record types
L.TRACKER_LEVEL = "Level ups"
L.TRACKER_LEVEL_TIP = "Every level you reach."
L.LEVEL_UP = "Reached level %d"

L.TRACKER_PROFESSIONS = "Professions"
L.TRACKER_PROFESSIONS_TIP = "Professions you learn, skill points per day and the ranks 75, 150, 225 and 300."
L.PROFESSION_LEARNED = "Learned %s"
L.PROFESSION_RANK = "%s reached %d"
L.COUNTER_SKILL = "Skill gains: %s"
L.SKILL_GAIN = "%s +%d"
L.UNKNOWN_SKILL = "Skill %d"

L.TRACKER_GATHERING = "Gathering"
L.TRACKER_GATHERING_TIP = "Ore, herbs and skins you gather, summed per day."
L.COUNTER_GATHER = "Gathered %s"
L.GATHER_ITEM = "%d× %s"
L.NODES_MINING = "Ore deposits mined: %d"
L.NODES_HERBALISM = "Herbs picked: %d"
L.NODES_SKINNING = "Creatures skinned: %d"
L.UNKNOWN_ITEM = "item %d"

L.TRACKER_BOSSES = "Boss kills"
L.TRACKER_BOSSES_TIP = "Every boss you defeat, in dungeons, raids and the open world."
L.BOSS_KILLED = "Defeated %s"
L.BOSS_KILLED_FIRST = "Defeated %s for the first time"
L.UNKNOWN_BOSS = "boss %d"

L.TRACKER_QUESTS = "Quests and quest chains"
L.TRACKER_QUESTS_TIP = "Quests you turn in, counted per day, and the well-known quest chains you complete."
L.COUNTER_QUESTS = "Quests turned in: %d"
L.QUEST_CHAIN_COMPLETED = "Completed the quest chain: %s"
L.UNKNOWN_CHAIN = "quest %d"
L.CHAINS_BACKFILLED = "%d quest chains you completed earlier were added to your journal."
L.CHAIN_ONYXIA = "Onyxia's Lair attunement"
L.CHAIN_UBRS = "Key to Upper Blackrock Spire"
L.CHAIN_SCHOLOMANCE = "The Key to Scholomance"
L.CHAIN_AHNQIRAJ = "Opening the gates of Ahn'Qiraj"
L.CHAIN_DEFIAS = "The Defias Brotherhood"
L.CHAIN_MISSING_DIPLOMAT = "The Missing Diplomat"
L.CHAIN_TIRION = "The redemption of Tirion Fordring"
L.CHAIN_BEAR_FORM = "The druid's bear form"
L.CHAIN_DREADSTEED = "The warlock's dreadsteed"
L.CHAIN_CHARGER = "The paladin's charger"
L.CHAIN_THUNDERFURY = "Thunderfury, Blessed Blade of the Windseeker"

L.TRACKER_DUNGEONS = "Dungeon and raid runs"
L.TRACKER_DUNGEONS_TIP = "Each run with the group you had, its duration and the bosses you defeated."
L.DUNGEON_CLEARED = "Cleared %s"
L.DUNGEON_CLEARED_FIRST = "First clear of %s"
L.DUNGEON_VISITED = "Visited %s"
L.DUNGEON_VISITED_BOSS = "Visited %s and defeated 1 boss"
L.DUNGEON_VISITED_BOSSES = "Visited %s and defeated %d bosses"
L.DUNGEON_WITH = "with %s"
L.UNKNOWN_INSTANCE = "instance %d"
L.INSTANCE_WING = "%s (%s)"
L.WING_GRAVEYARD = "Graveyard"
L.WING_LIBRARY = "Library"
L.WING_ARMORY = "Armory"
L.WING_CATHEDRAL = "Cathedral"
L.WING_LOWER = "Lower"
L.WING_UPPER = "Upper"
L.WING_EAST = "East"
L.WING_WEST = "West"
L.WING_NORTH = "North"
L.WING_LIVING = "Living side"
L.WING_UNDEAD = "Undead side"

-- Login recap
L.RECAP_TITLE = "Last session"
L.RECAP_SUBTITLE = "%s · %s"
L.RECAP_OPEN = "Open journal"
L.RECAP_DONT_SHOW = "Don't show at login"
L.RECAP_MORE = "... and %d more"
L.RECAP_NOTHING = "Nothing to recap from your last session."

-- Settings
L.SETTINGS_GENERAL = "General"
L.SETTINGS_TRACKING = "Tracking"
L.SETTINGS_DATA = "Data"
L.SETTINGS_LOGIN_RECAP = "Show last session at login"
L.SETTINGS_LOGIN_RECAP_TIP = "At your first login of the day, show what happened in your previous session."
L.SETTINGS_MINIMAP = "Minimap button"
L.SETTINGS_MINIMAP_TIP = "Left-click opens the journal, right-click these settings. The Addon Compartment entry stays either way."
L.SETTINGS_DATE_FORMAT = "Date format"
L.SETTINGS_DATE_FORMAT_TIP = "How short dates are shown, for example in the login recap. Journal pages always show the full date."
L.SETTINGS_DATE_LOCALE = "Language default (%s)"
L.SETTINGS_SHOW = "Show"
L.SETTINGS_STATS = "Journal statistics"
L.SETTINGS_STATS_TIP = "Entries, days, months and sessions in this character's journal (also /ws stats)."
L.SETTINGS_LOG = "Error log"
L.SETTINGS_LOG_TIP = "The last recorded errors (also /ws log)."
L.SETTINGS_REBUILD = "Rebuild indexes"
L.SETTINGS_REBUILD_BUTTON = "Rebuild"
L.SETTINGS_REBUILD_TIP = "Recompute firsts and monthly summaries from the journal entries, and add quest chains completed before they were known (also /ws rebuild)."
L.SETTINGS_RESET = "Reset journal"
L.SETTINGS_RESET_BUTTON = "Reset..."
L.SETTINGS_RESET_TIP = "Delete this character's entire journal. You will be asked to confirm."
L.SETTINGS_UNAVAILABLE = "The settings page isn't available on this client. All settings are in /ws help."
L.RESET_CONFIRM = "Delete this character's entire Wayscribe journal?\n\nThis cannot be undone. The interface reloads afterwards."
L.RESET_ACCEPT = "Delete"

-- Minimap button and key binding
L.MINIMAP_HINT_LEFT = "Left-click: open the journal"
L.MINIMAP_HINT_RIGHT = "Right-click: settings"
L.BINDING_TOGGLE_JOURNAL = "Open or close the journal"

-- Safe mode
L.SAFE_MODE_BANNER = "Read-only mode: %s"
L.SAFE_MODE_NEWER_SCHEMA = "this journal was written by a newer Wayscribe version. Please update the addon."
L.SAFE_MODE_MIGRATION_FAILED = "upgrading the journal failed. Nothing was changed; see /ws log."
L.SAFE_MODE_CORRUPT = "the journal data has an unexpected shape. Nothing was changed; see /ws log."
L.SAFE_MODE_MISSING = "the journal for this character did not load, although it had %d entries. Before logging out, copy WTF\\Account\\<account>\\<realm>\\<character>\\SavedVariables\\Wayscribe.lua (and its .bak) somewhere safe. /ws accept starts a new journal instead."
L.SAFE_MODE_RENAMED = "this character's journal is still stored under its old name %s-%s. Copy Wayscribe.lua from that character's SavedVariables folder into this one while the game is closed. /ws accept starts a new journal instead."
L.SAFE_MODE_FOREIGN = "this journal belongs to another character (%s). Type /ws accept to take it over."

-- Chat
L.MODULE_DISABLED = "%s was disabled after repeated errors. Details: /ws log"
L.ACCEPTED = "Done. Please /reload to continue."
L.NOTHING_TO_ACCEPT = "There is nothing to accept."
L.DEV_MODE = "Developer mode: %s"
L.ON = "on"
L.OFF = "off"
L.REBUILT = "Indexes rebuilt from %d entries."
L.LOG_EMPTY = "No errors recorded."
L.STATS_LINE = "%d entries on %d days in %d months, %d sessions. Last id: %d."
L.SIM_NEEDS_DEV = "Simulation only works in developer mode (/ws dev)."
L.SIM_USAGE = "Usage: /ws simulate <TYPE> key=value ... | /ws simulate clear"
L.SIM_ADDED = "Simulated %s added."
L.SIM_FAILED = "Simulation failed: %s"
L.SIM_CLEARED = "%d simulated entries removed."
L.COMMAND_FAILED = "That command failed. Details: /ws log"
L.HELP = "Commands: /ws (journal), settings, recap, probe, stats, log, rebuild, dev, simulate, accept"
