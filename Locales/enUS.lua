local _, ns = ...

-- Missing keys fall back to the key itself, so a forgotten translation shows up as
-- readable text instead of a Lua error.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- Dates: DD, MM and YYYY are replaced; everything else is kept as-is.
L.DATE_FORMAT = "YYYY-MM-DD"

-- Journal
L.JOURNAL_TITLE = "Wayscribe"
L.JOURNAL_EMPTY = "Your journal is still empty. Go on an adventure!"
L.JOURNAL_MORE_DAYS = "%d older days are not shown yet."
L.ENTRY_UNREADABLE = "(unreadable entry: %s)"
L.ENTRY_SIMULATED = "[sim]"

-- Trackers and record types
L.TRACKER_LEVEL = "Level ups"
L.LEVEL_UP = "Reached level %d"

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
L.HELP = "Commands: /ws (journal), probe, stats, log, rebuild, dev, simulate, accept"
