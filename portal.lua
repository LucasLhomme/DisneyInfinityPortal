-- DisneyInfinityPortal - Mod principal
-- Portail Disney Infinity physique (PS3/PS4/Wii/Wii U/PC, Xbox 360, Xbox One) et virtuel.
-- L'API Crabe.Portal ne fait que lire le portail ; c'est ce mod qui décide quoi faire d'une figurine.
-- Auteur: Lucas Lhomme

local FigureProgress = require("mods.disneyinfinityportal.figure_progress")

local PortalMod = {
    version = "1.0.0",
    category = "Portail Disney",
}

-- Couleur de LED de chaque slot quand une figurine y est posée.
local SLOT_COLORS = {
    [1] = { 0, 255, 255 },   -- Joueur 1 : cyan
    [2] = { 255, 0, 255 },   -- Joueur 2 : magenta
    [3] = { 255, 215, 0 },   -- Hexagone : or
}
local SLOT_NAMES = { [1] = "Joueur 1", [2] = "Joueur 2", [3] = "Hexagone" }

local function logMsg(msg)
    Crabe.write("[DisneyInfinityPortal] " .. tostring(msg))
end

local function characterName(sku)
    if not sku or sku == 0 then return "Aucune" end
    if Crabe.VirtualReader and Crabe.VirtualReader.findCharacter then
        local row = Crabe.VirtualReader.findCharacter(sku)
        if row and row.Name then return row.Name end
    end
    for _, c in ipairs(Game.ListCharacters and Game.ListCharacters() or {}) do
        if tonumber(c.sku) == sku then return c.name end
    end
    return "SKU #" .. tostring(sku)
end

-- Progression lue sur la figurine de chaque slot joueur, pour le statut.
local slotProgress = {}

-- Figurine posée : les slots joueur changent le personnage joué et reprennent la progression
-- enregistrée sur une figurine physique ; l'hexagone est seulement signalé.
function PortalMod.onPlaced(slot, sku, uid, progress)
    logMsg(string.format("Figurine posee sur %s : %s (SKU %s, UID %s)",
        SLOT_NAMES[slot] or tostring(slot), characterName(sku), tostring(sku), uid ~= "" and uid or "virtuel"))
    local color = SLOT_COLORS[slot]
    if color then Crabe.Portal.setLed(slot, color[1], color[2], color[3]) end
    if (slot == 1 or slot == 2) and sku and sku > 0 then
        Game.SetCharacter(sku, "loadout", slot)
        slotProgress[slot] = progress
        if progress then FigureProgress.apply(slot, sku, progress, logMsg) end
    end
end

function PortalMod.onRemoved(slot, uid)
    logMsg("Figurine retiree de " .. (SLOT_NAMES[slot] or tostring(slot)))
    Crabe.Portal.setLed(slot, 0, 0, 0)
    FigureProgress.cancel(slot)
    slotProgress[slot] = nil
end

local function progressText(slot)
    local p = slotProgress[slot]
    if not p then return "" end
    return string.format(" (niv. %d, %d XP, %d comp.)", p.level, p.experience or 0, #p.skillBits)
end

local function statusText()
    local st = Crabe.Portal.getStatus()
    if not st.connected then
        return "Portail physique : non connecte. " .. (st.diagnostic or "")
    end
    return string.format("%s | J1 : %s%s | J2 : %s%s | Hex : %s",
        st.typeDescription, characterName(st.slot1Sku), progressText(1), characterName(st.slot2Sku), progressText(2),
        st.slot3Sku and ("SKU #" .. st.slot3Sku) or "vide")
end

local function ledEntry(label, r, g, b)
    return {
        label = label,
        action = function()
            if not Crabe.Portal.setLed(0, r, g, b) then
                return "Aucun portail physique connecte."
            end
            return "LED : " .. label
        end
    }
end

-- Liste des personnages pour poser une figurine virtuelle sur un slot joueur.
local function virtualFigureMenu(slot)
    return {
        label = "Poser une figurine virtuelle (" .. SLOT_NAMES[slot] .. ")",
        submenu = {
            title = "FIGURINE VIRTUELLE " .. SLOT_NAMES[slot],
            build = function()
                local items = {}
                for _, c in ipairs(Game.ListCharacters()) do
                    local sku = tonumber(c.sku)
                    if sku then
                        items[#items + 1] = {
                            label = c.name,
                            action = function()
                                Crabe.Portal.placeVirtualFigure(slot, sku)
                                return c.name .. " pose sur " .. SLOT_NAMES[slot]
                            end
                        }
                    end
                end
                return items
            end
        }
    }
end

function PortalMod.registerMenu()
    local cat = PortalMod.category
    Crabe.Menu.registerInCategory(cat, { label = "Statut du portail", action = statusText })
    Crabe.Menu.registerInCategory(cat, ledEntry("Tester LED : cyan", 0, 255, 255))
    Crabe.Menu.registerInCategory(cat, ledEntry("Tester LED : vert", 0, 255, 0))
    Crabe.Menu.registerInCategory(cat, ledEntry("Tester LED : rouge", 255, 0, 0))
    Crabe.Menu.registerInCategory(cat, ledEntry("Eteindre les LED", 0, 0, 0))
    Crabe.Menu.registerInCategory(cat, {
        label = "Enregistrer la progression sur les figurines",
        toggle = true,
        state = FigureProgress.writeEnabled,
        onToggle = function(on)
            FigureProgress.writeEnabled = on
            return on and "Ecriture sur les figurines activee" or "Ecriture sur les figurines desactivee"
        end
    })
    Crabe.Menu.registerInCategory(cat, virtualFigureMenu(1))
    Crabe.Menu.registerInCategory(cat, virtualFigureMenu(2))
    Crabe.Menu.registerInCategory(cat, {
        label = "Retirer la figurine (Joueur 1)",
        action = function()
            Crabe.Portal.removeVirtualFigure(1)
            return "Slot Joueur 1 vide"
        end
    })
    Crabe.Menu.registerInCategory(cat, {
        label = "Retirer la figurine (Joueur 2)",
        action = function()
            Crabe.Portal.removeVirtualFigure(2)
            return "Slot Joueur 2 vide"
        end
    })
end

Crabe.Events.on("portalFigurePlaced", PortalMod.onPlaced)
Crabe.Events.on("portalFigureRemoved", PortalMod.onRemoved)
Game.onTick(FigureProgress.update)
PortalMod.registerMenu()

logMsg("Mod Disney Infinity Portal v" .. PortalMod.version .. " charge.")

return PortalMod
