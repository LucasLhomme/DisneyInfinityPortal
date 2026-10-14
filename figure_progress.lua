-- DisneyInfinityPortal - progression d'une figurine physique, dans les deux sens, comme la console.
-- Lecture (IGPGameFlow::LoadIGP) : la figurine ne fait jamais baisser la progression PC, elle ne
-- l'emporte que si son niveau est plus haut ; ses compétences sont ajoutées, aucune n'est retirée.
-- Écriture (IGPGameFlow::SaveIGPByPlayerNum) : tant que la figurine est posée, le niveau et les
-- compétences du PC sont enregistrés dessus quand ils changent (au plus toutes les 10 s), dans la plus
-- ancienne des deux copies ; jamais à la baisse. L'XP dans le niveau n'est pas lisible côté PC : celle
-- de la figurine est gardée, et remise à 0 seulement quand le niveau PC la dépasse.
-- Auteur: Lucas Lhomme

local FigureSkills = require("mods.disneyinfinityportal.figure_skills")

local FigureProgress = {}

local MAX_LEVEL_STEPS = 40
local SKILLS_DELAY = 2.5          -- secondes : laisser le personnage se charger avant l'arbre
local MAX_SKILL_GRIDS = 8
local ACTION_MAX_LEVEL = 64       -- bit 6 des drapeaux d'action : niveau max atteint

local SAVE_PERIOD = 10            -- secondes entre deux écritures (TAG_DATA_FLUSH_TIME du moteur)
local FIRST_SAVE_DELAY = 5        -- après la pose : niveau et compétences de la figurine appliqués

local pending = {}                -- [slot] = { at, sku, bits, log }
local tracked = {}                -- [slot] = { sku, figure = progression sur la figurine, nextSave, log }

FigureProgress.writeEnabled = true

local function hasFlag(flags, bit)
    return math.floor((flags or 0) / bit) % 2 == 1
end

-- Monte le niveau du personnage PC jusqu'à celui de la figurine (un niveau par appel natif).
local function applyLevel(slot, sku, progress, log)
    local current = Game.GetAvatarLevel(sku)
    local target = progress.level
    local toMax = hasFlag(progress.actionFlags, ACTION_MAX_LEVEL)
    if not toMax and target <= current then
        log(string.format("niveau PC %d >= niveau figurine %d : rien a changer", current, target))
        return
    end
    for _ = 1, MAX_LEVEL_STEPS do
        if not toMax and current >= target then break end
        Game.LevelUpAvatar(slot, sku)
        local after = Game.GetAvatarLevel(sku)
        if after <= current then break end -- niveau max atteint
        current = after
    end
    log(string.format("niveau PC porte a %d (figurine : %d%s)", current, target, toMax and ", max" or ""))
end

-- Parcourt les cases de compétence de l'arbre du joueur : visit(index, grid, upgradeName).
local function forEachSkillCell(player, visit)
    for grid = 1, MAX_SKILL_GRIDS do
        local data = UI_GetSkillTreeGridData(player, grid)
        if type(data) ~= "table" or type(data.GridData) ~= "table" then break end
        for index, cell in pairs(data.GridData) do
            local skill = type(cell) == "table" and cell.SkillData
            if type(skill) == "table" and skill.UpgradeName then
                visit(index, grid, skill.UpgradeName)
            end
        end
        if data.GridCount and grid >= data.GridCount then break end
    end
end

local function isPurchased(player, index, grid)
    local state = UI_GetItemArgumentsForPlayer("SkillTree_IN3", player, "ispurchased", index, grid)
    return state == true or state == "true"
end

local function skillMap(sku)
    local row = Crabe.VirtualReader and Crabe.VirtualReader.findCharacter(sku)
    local tree = row and row.ProgressionTree
    return tree and FigureSkills[tree], tree
end

-- Bits de figurine des compétences achetées sur PC pour ce joueur (nil si l'arbre est inconnu).
function FigureProgress.readPcSkillBits(slot, sku)
    local map = skillMap(sku)
    if not map then return nil end
    local bitForName = {}
    for bit, entry in pairs(map) do
        bitForName[entry[1]] = bit
        if entry[2] then bitForName[entry[2]] = bit end
    end
    local bits, seen = {}, {}
    local player = Game.ResolvePlayerId(slot)
    forEachSkillCell(player, function(index, grid, name)
        local bit = bitForName[name]
        if bit and not seen[bit] and isPurchased(player, index, grid) then
            seen[bit] = true
            bits[#bits + 1] = bit
        end
    end)
    table.sort(bits)
    return bits
end

-- Achète dans l'arbre de compétences du joueur les compétences enregistrées sur la figurine.
local function applySkills(job)
    local log = job.log
    local map, tree = skillMap(job.sku)
    if not map then
        log("arbre de competences inconnu pour le SKU " .. tostring(job.sku) .. " (" .. tostring(tree) .. ")")
        return
    end
    local wanted, names = {}, {}
    for _, bit in ipairs(job.bits) do
        local entry = map[bit]
        if entry then
            wanted[entry[1]] = true
            if entry[2] then wanted[entry[2]] = true end
            names[#names + 1] = entry[1]
        end
    end
    if #names == 0 then
        log("aucune competence enregistree sur la figurine")
        return
    end
    log("competences de la figurine : " .. table.concat(names, ", "))

    local player = Game.ResolvePlayerId(job.slot)
    local bought, owned, seen = 0, 0, {}
    forEachSkillCell(player, function(index, grid, name)
        seen[#seen + 1] = tostring(name)
        if not wanted[name] then return end
        if isPurchased(player, index, grid) then
            owned = owned + 1
        else
            local ok = UI_GetItemArgumentsForPlayer("SkillTree_IN3", player, "purchaseskill", index, grid, true)
            if ok == true or ok == "true" then bought = bought + 1 end
        end
    end)
    log(string.format("competences : %d achetee(s), %d deja possedee(s), sur %d enregistree(s)", bought, owned, #names))
    if bought + owned < #names then
        log("cases vues dans l'arbre : " .. table.concat(seen, ", "))
    end
end

-- Date locale empaquetée comme AvatarSpawning::GetCurrentDateAsUInt ; nil si os.date manque.
local function packedNow()
    if not (os and os.date) then return nil end
    local t = os.date("*t")
    return (t.year - 2013) * 2 ^ 26 + t.month * 2 ^ 22 + t.day * 2 ^ 17 + t.hour * 2 ^ 12 + t.min * 2 ^ 6
end

local function sameBits(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Progression à enregistrer : le plus haut des deux côtés, compétences réunies.
local function mergedProgress(slot, entry)
    local figure = entry.figure
    local pcLevel = Game.GetAvatarLevel(entry.sku) or 0
    local level = math.max(pcLevel, figure.level)
    local bits, set = {}, {}
    for _, b in ipairs(figure.skillBits) do set[b] = true end
    for _, b in ipairs(FigureProgress.readPcSkillBits(slot, entry.sku) or {}) do set[b] = true end
    for b in pairs(set) do bits[#bits + 1] = b end
    table.sort(bits)
    return {
        level = level,
        experience = level > figure.level and 0 or figure.experience,
        actionFlags = figure.actionFlags,
        lastPlayed = figure.lastPlayed,
        skillBits = bits,
    }
end

local function saveToFigure(slot, entry)
    local next = mergedProgress(slot, entry)
    local figure = entry.figure
    if next.level == figure.level and next.experience == figure.experience and sameBits(next.skillBits, figure.skillBits) then
        return
    end
    next.lastPlayed = packedNow() or figure.lastPlayed
    if Crabe.Portal.writeFigureProgress(slot, next) then
        entry.figure = next
        entry.log(string.format("progression enregistree sur la figurine : niveau %d, %d competence(s)",
            next.level, #next.skillBits))
    end
end

-- Appelé quand une figurine avec une progression est posée sur un slot joueur.
function FigureProgress.apply(slot, sku, progress, log)
    log(string.format("progression de la figurine : niveau %d, %d XP, %d competence(s)",
        progress.level, progress.experience or 0, #progress.skillBits))
    applyLevel(slot, sku, progress, log)
    pending[slot] = { at = os.clock() + SKILLS_DELAY, slot = slot, sku = sku, bits = progress.skillBits, log = log }
    tracked[slot] = { sku = sku, figure = progress, nextSave = os.clock() + FIRST_SAVE_DELAY, log = log }
end

function FigureProgress.cancel(slot)
    pending[slot] = nil
    tracked[slot] = nil
end

-- À appeler à chaque tick : lance l'achat des compétences une fois le personnage chargé.
function FigureProgress.update()
    local now = os.clock()
    for slot, job in pairs(pending) do
        if now >= job.at then
            pending[slot] = nil
            applySkills(job)
        end
    end
    if not FigureProgress.writeEnabled then return end
    for slot, entry in pairs(tracked) do
        if now >= entry.nextSave and not pending[slot] then
            entry.nextSave = now + SAVE_PERIOD
            saveToFigure(slot, entry)
        end
    end
end

return FigureProgress
