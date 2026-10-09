local addonName, ns = ...
local L, Compat = ns.L, ns.Compat

-- Ways to open Wayscribe besides /ws: the minimap button (LibDataBroker + LibDBIcon), the Addon
-- Compartment entry and the key binding. Without the libraries (an unpackaged copy has no Libs
-- folder) only the minimap button is missing.
local Minimap = {}
ns.Minimap = Minimap

local function onClick(button)
    if button == "RightButton" then
        ns.SettingsPanel:Open()
    else
        ns.Journal:Toggle()
    end
end

local function showTooltip(tooltip)
    tooltip:AddLine(L.ADDON_TITLE)
    tooltip:AddLine(L.MINIMAP_HINT_LEFT, 1, 1, 1)
    tooltip:AddLine(L.MINIMAP_HINT_RIGHT, 1, 1, 1)
end

-- LibDBIcon lays the button out for Classic unless WOW_PROJECT_ID is Mainline's. Forever's is 18,
-- but it draws the Mainline ring, so the icon sat up and to the left of the ring's opening. This is
-- the layout of Blizzard's own button in that ring (WorldMapTrackingPinButtonTemplate), with the
-- border anchored top left as LibDBIcon does.
local function layOutForForever(icon)
    if not (Compat.isForever and icon.SetButtonBorder and icon.SetButtonBackground
        and icon.SetButtonIcon) then
        return
    end
    icon:SetButtonBorder(addonName, nil, 54)
    icon:SetButtonBackground(addonName, nil, 25, "TOPLEFT", 3, -4)
    icon:SetButtonIcon(addonName, nil, 20, "TOPLEFT", 7, -6)
end

function Minimap:Register()
    local libStub = LibStub
    local broker = libStub and libStub("LibDataBroker-1.1", true)
    local icon = libStub and libStub("LibDBIcon-1.0", true)
    if self.icon or not (broker and icon) then return end
    local launcher = broker:NewDataObject(addonName, {
        type = "launcher",
        icon = ns.Theme.ICON_SMALL,
        label = L.ADDON_TITLE,
        OnClick = function(_, button) onClick(button) end,
        OnTooltipShow = showTooltip,
    })
    -- LibDBIcon keeps the button position and hidden flag in this table.
    icon:Register(addonName, launcher, ns.Options:Table("minimap"))
    layOutForForever(icon)
    self.icon = icon
end

function Minimap:IsShown()
    return not ns.Options:Table("minimap").hide
end

function Minimap:SetShown(shown)
    ns.Options:Table("minimap").hide = not shown
    if not self.icon then return end
    if shown then
        self.icon:Show(addonName)
    else
        self.icon:Hide(addonName)
    end
end

ns.Bus:On("READY", Minimap, Minimap.Register)

-- Addon Compartment (## AddonCompartmentFunc in Wayscribe.toc).
function Wayscribe_OnAddonCompartmentClick(_, button)
    onClick(button)
end

-- Key binding (Bindings.xml); unbound by default.
BINDING_HEADER_WAYSCRIBE = L.ADDON_TITLE
BINDING_NAME_WAYSCRIBE_TOGGLE = L.BINDING_TOGGLE_JOURNAL

function Wayscribe_ToggleJournal()
    ns.Journal:Toggle()
end
