-- DisneyInfinityPortal - physical (PS3/PS4/Wii/Wii U/PC, Xbox 360, Xbox One) and virtual Disney Infinity base.
-- Author: Lucas Lhomme

local FigureProgress = require("mods.disneyinfinityportal.figure_progress")

local PortalMod = {
    version = "1.0.0",
    category = "Disney Infinity Base",
}

local SLOT_COLORS = {
    [1] = { 0, 255, 255 },
    [2] = { 255, 0, 255 },
    [3] = { 255, 215, 0 },
}
local SLOT_NAMES = { [1] = "Player 1", [2] = "Player 2", [3] = "Hexagon" }

-- Writes one line to the overlay and loader.log, tagged with the mod name.
local function logMsg(msg)
    Crabe.write("[DisneyInfinityPortal] " .. tostring(msg))
end

-- Display name of a character SKU, from the virtual reader table or the game's character list.
local function characterName(sku)
    if not sku or sku == 0 then return "None" end
    if Crabe.VirtualReader and Crabe.VirtualReader.findCharacter then
        local row = Crabe.VirtualReader.findCharacter(sku)
        if row and row.Name then return row.Name end
    end
    for _, c in ipairs(Game.ListCharacters and Game.ListCharacters() or {}) do
        if tonumber(c.sku) == sku then return c.name end
    end
    return "SKU #" .. tostring(sku)
end

-- A figure was placed: light its slot and, on a player slot, make it the played character.
-- A physical figure enters the game's registry under its own UID, so it keeps its own progression.
-- A virtual figure, or a physical one when CrabeLoader lacks that bridge, only picks the character.
function PortalMod.onPlaced(slot, sku, uid, progress)
    logMsg(string.format("figure placed on %s: %s (SKU %s, UID %s)",
        SLOT_NAMES[slot] or tostring(slot), characterName(sku), tostring(sku), uid ~= "" and uid or "virtual"))
    local color = SLOT_COLORS[slot]
    if color then Crabe.Portal.setLed(slot, color[1], color[2], color[3]) end
    if (slot == 1 or slot == 2) and sku and sku > 0 then
        if uid ~= "" and progress and FigureProgress.isAvailable()
            and FigureProgress.place(slot, sku, uid, progress, logMsg) then
            return
        end
        Game.SetCharacter(sku, "loadout", slot)
    end
end

-- A figure was removed: switch its slot's light off and take it out of the game's registry.
function PortalMod.onRemoved(slot, uid)
    logMsg("figure removed from " .. (SLOT_NAMES[slot] or tostring(slot)))
    Crabe.Portal.setLed(slot, 0, 0, 0)
    if slot == 1 or slot == 2 then FigureProgress.remove(slot) end
end

-- Progression suffix of a slot for the status line, empty when the slot holds no physical figure.
local function progressText(slot)
    local p = FigureProgress.progressOf(slot)
    if not p then return "" end
    return string.format(" (lvl %d, %d XP, %d skills)", p.level, p.experience or 0, #p.skillBits)
end

-- Status line shown by the menu: base type and the figure on each slot.
local function statusText()
    local st = Crabe.Portal.getStatus()
    if not st.connected then
        return "Physical base: not connected. " .. (st.diagnostic or "")
    end
    return string.format("%s | P1: %s%s | P2: %s%s | Hex: %s",
        st.typeDescription, characterName(st.slot1Sku), progressText(1), characterName(st.slot2Sku), progressText(2),
        st.slot3Sku and ("SKU #" .. st.slot3Sku) or "empty")
end

-- Menu entry that sets every LED of the base to one colour.
local function ledEntry(label, r, g, b)
    return {
        label = label,
        action = function()
            if not Crabe.Portal.setLed(0, r, g, b) then
                return "No physical base connected."
            end
            return "LEDs: " .. label
        end,
    }
end

-- Submenu listing every character, to place it as a virtual figure on a player slot.
local function virtualFigureMenu(slot)
    return {
        label = "Place a virtual figure (" .. SLOT_NAMES[slot] .. ")",
        submenu = {
            title = "VIRTUAL FIGURE " .. string.upper(SLOT_NAMES[slot]),
            build = function()
                local items = {}
                for _, c in ipairs(Game.ListCharacters()) do
                    local sku = tonumber(c.sku)
                    if sku then
                        items[#items + 1] = {
                            label = c.name,
                            action = function()
                                Crabe.Portal.placeVirtualFigure(slot, sku)
                                return c.name .. " placed on " .. SLOT_NAMES[slot]
                            end,
                        }
                    end
                end
                return items
            end,
        },
    }
end

-- Menu entry that removes the figure of a player slot, virtual or not.
local function removeEntry(slot)
    return {
        label = "Remove the figure (" .. SLOT_NAMES[slot] .. ")",
        action = function()
            Crabe.Portal.removeVirtualFigure(slot)
            return SLOT_NAMES[slot] .. " slot empty"
        end,
    }
end

-- Adds the mod's entries to the CrabeMenu category.
function PortalMod.registerMenu()
    local cat = PortalMod.category
    Crabe.Menu.registerInCategory(cat, { label = "Base status", action = statusText })
    Crabe.Menu.registerInCategory(cat, ledEntry("Test LEDs: cyan", 0, 255, 255))
    Crabe.Menu.registerInCategory(cat, ledEntry("Test LEDs: green", 0, 255, 0))
    Crabe.Menu.registerInCategory(cat, ledEntry("Test LEDs: red", 255, 0, 0))
    Crabe.Menu.registerInCategory(cat, ledEntry("LEDs off", 0, 0, 0))
    Crabe.Menu.registerInCategory(cat, {
        label = "Save progress to figures",
        toggle = true,
        state = FigureProgress.writeEnabled,
        onToggle = function(on)
            FigureProgress.writeEnabled = on
            return on and "Saving to figures on" or "Saving to figures off"
        end,
    })
    Crabe.Menu.registerInCategory(cat, virtualFigureMenu(1))
    Crabe.Menu.registerInCategory(cat, virtualFigureMenu(2))
    Crabe.Menu.registerInCategory(cat, removeEntry(1))
    Crabe.Menu.registerInCategory(cat, removeEntry(2))
end

Crabe.Events.on("portalFigurePlaced", PortalMod.onPlaced)
Crabe.Events.on("portalFigureRemoved", PortalMod.onRemoved)
Crabe.Events.on("gatewayTagWrite", FigureProgress.onTagWrite)
Game.onTick(FigureProgress.update)
PortalMod.registerMenu()

logMsg("Disney Infinity Portal v" .. PortalMod.version .. " loaded.")

return PortalMod
