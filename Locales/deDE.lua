local _, ns = ...

if GetLocale() ~= "deDE" then return end

local L = ns.L

L.DATE_FORMAT = "DD.MM.YYYY"

-- Journal
L.JOURNAL_EMPTY = "Dein Tagebuch ist noch leer. Zeit für ein Abenteuer!"
L.JOURNAL_MORE_DAYS = "%d ältere Tage werden noch nicht angezeigt."
L.ENTRY_UNREADABLE = "(unlesbarer Eintrag: %s)"

-- Trackers and record types
L.TRACKER_LEVEL = "Stufenaufstiege"
L.LEVEL_UP = "Stufe %d erreicht"

-- Safe mode
L.SAFE_MODE_BANNER = "Nur-Lese-Modus: %s"
L.SAFE_MODE_NEWER_SCHEMA = "dieses Tagebuch stammt von einer neueren Wayscribe-Version. Bitte aktualisiere das Addon."
L.SAFE_MODE_MIGRATION_FAILED = "das Aktualisieren des Tagebuchs ist fehlgeschlagen. Es wurde nichts verändert; siehe /ws log."
L.SAFE_MODE_CORRUPT = "die Tagebuchdaten haben eine unerwartete Form. Es wurde nichts verändert; siehe /ws log."
L.SAFE_MODE_MISSING = "das Tagebuch dieses Charakters wurde nicht geladen, obwohl es %d Einträge hatte. Kopiere vor dem Ausloggen WTF\\Account\\<Account>\\<Realm>\\<Charakter>\\SavedVariables\\Wayscribe.lua (und die .bak) an einen sicheren Ort. /ws accept beginnt stattdessen ein neues Tagebuch."
L.SAFE_MODE_RENAMED = "das Tagebuch dieses Charakters liegt noch unter dem alten Namen %s-%s. Kopiere bei geschlossenem Spiel Wayscribe.lua aus dem SavedVariables-Ordner dieses Charakters in den neuen. /ws accept beginnt stattdessen ein neues Tagebuch."
L.SAFE_MODE_FOREIGN = "dieses Tagebuch gehört einem anderen Charakter (%s). Mit /ws accept übernimmst du es."

-- Chat
L.MODULE_DISABLED = "%s wurde nach wiederholten Fehlern deaktiviert. Details: /ws log"
L.ACCEPTED = "Erledigt. Bitte /reload ausführen."
L.NOTHING_TO_ACCEPT = "Es gibt nichts zu bestätigen."
L.DEV_MODE = "Entwicklermodus: %s"
L.ON = "an"
L.OFF = "aus"
L.REBUILT = "Indizes aus %d Einträgen neu aufgebaut."
L.LOG_EMPTY = "Keine Fehler aufgezeichnet."
L.STATS_LINE = "%d Einträge an %d Tagen in %d Monaten, %d Sitzungen. Letzte ID: %d."
L.SIM_NEEDS_DEV = "Simulation funktioniert nur im Entwicklermodus (/ws dev)."
L.SIM_USAGE = "Verwendung: /ws simulate <TYP> schlüssel=wert ... | /ws simulate clear"
L.SIM_ADDED = "Simulierter Eintrag %s hinzugefügt."
L.SIM_FAILED = "Simulation fehlgeschlagen: %s"
L.SIM_CLEARED = "%d simulierte Einträge entfernt."
L.COMMAND_FAILED = "Der Befehl ist fehlgeschlagen. Details: /ws log"
L.HELP = "Befehle: /ws (Tagebuch), probe, stats, log, rebuild, dev, simulate, accept"
