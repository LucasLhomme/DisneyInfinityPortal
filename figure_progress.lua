-- DisneyInfinityPortal - one profile record per physical figure, as on console.
-- Author: Lucas Lhomme

local FigureProgress = {}

local SETTLE_SECONDS = 1.0
local RETRY_SECONDS = 5.0
local MAX_RETRIES = 3

FigureProgress.writeEnabled = false

local figures = {}
local uidBySlot = {}
local hiddenVirtualAvatar = nil

-- Copy of a progression table, so later edits never reach the original.
local function copyProgress(p)
    local bits = {}
    for i, b in ipairs(p.skillBits or {}) do bits[i] = b end
    return {
        level = p.level or 0,
        experience = p.experience or 0,
        actionFlags = p.actionFlags or 0,
        lastPlayed = p.lastPlayed or 0,
        skillBits = bits,
    }
end

-- Whether two progression tables would write the same bytes to a figure.
-- lastPlayed is left out: the game refreshes it on every save.
local function sameProgress(a, b)
    if a.level ~= b.level or a.experience ~= b.experience or a.actionFlags ~= b.actionFlags
        or #a.skillBits ~= #b.skillBits then
        return false
    end
    for i = 1, #a.skillBits do
        if a.skillBits[i] ~= b.skillBits[i] then return false end
    end
    return true
end

-- One-line summary of a progression table for the log.
local function describe(p)
    return string.format("level %d, %d XP, %d skill(s), action flags 0x%02x",
        p.level, p.experience, #p.skillBits, p.actionFlags)
end

-- True when CrabeLoader can add figures to the engine's own registry.
-- Without it the mod falls back to picking the character only.
function FigureProgress.isAvailable()
    return Crabe.Gateway ~= nil and Crabe.Gateway.isAvailable()
end

-- Adds a physical figure to the engine under its own UID, with the progression read from it.
-- The game then keeps a profile record for this figure alone and applies its level and skills itself.
-- On Player 1 the virtual reader's avatar is removed first, since the game accepts one avatar per antenna.
function FigureProgress.place(slot, sku, uid, progress, log)
    if uidBySlot[slot] then FigureProgress.remove(slot) end

    local antenna = slot - 1
    if antenna == 0 then
        local virtual = Crabe.Gateway.virtualAvatar()
        if virtual and Crabe.Gateway.removeTag(Crabe.Gateway.uidForId(virtual)) then
            hiddenVirtualAvatar = virtual
            log("virtual reader avatar " .. virtual .. " set aside while the figure is on the base")
        end
    end

    local saved = copyProgress(progress)
    local added = Crabe.Gateway.addTag(uid, sku, antenna, {
        experience = saved.experience,
        level = saved.level,
        lastPlayed = saved.lastPlayed,
        actionFlags = saved.actionFlags,
        skillBits = saved.skillBits,
        watch = true,
    })
    log(string.format("figure %s %s the game's registry: %s", uid, added and "added to" or "REFUSED by", describe(saved)))
    if added then
        figures[uid] = { slot = slot, antenna = antenna, saved = saved, log = log }
        uidBySlot[slot] = uid
    end
    return added
end

-- Removes the figure of a slot from the engine and gives Player 1 back to the virtual reader.
-- A save the game made but that was not written yet is reported as lost.
function FigureProgress.remove(slot)
    local uid = uidBySlot[slot]
    local entry = uid and figures[uid]
    if not entry then return end
    if entry.pending then
        entry.log("figure removed before its save was written: " .. describe(entry.pending) .. " lost")
    end
    Crabe.Gateway.removeTag(uid)
    figures[uid] = nil
    uidBySlot[slot] = nil
    entry.log("figure " .. uid .. " removed from the game's registry")

    if entry.antenna == 0 and hiddenVirtualAvatar then
        local virtual = hiddenVirtualAvatar
        hiddenVirtualAvatar = nil
        local restored = Crabe.Gateway.addTag(Crabe.Gateway.uidForId(virtual), virtual, 0)
        entry.log("virtual reader avatar " .. virtual .. (restored and " restored" or " could NOT be restored"))
    end
end

-- Collects one field the game wrote to a figure's tag, until the whole save has arrived.
-- The owner field is never copied to the figure: its owner sector is never written.
function FigureProgress.onTagWrite(uid, field, value)
    local entry = figures[uid]
    if not entry then return end
    local next = entry.pending or copyProgress(entry.saved)
    if field == "experience" then next.experience = value
    elseif field == "level" then next.level = value
    elseif field == "lastPlayed" then next.lastPlayed = value
    elseif field == "action" then next.actionFlags = value
    elseif field == "progression" then next.skillBits = value
    else
        entry.log("the game wrote " .. tostring(field) .. " = " .. tostring(value) .. " (not copied to the figure)")
        return
    end
    entry.pending = next
    entry.dirtyAt = os.clock()
end

-- Writes a finished save to the figure, unless writing is off or the save is a reset.
-- A reset (level, experience and skills all zero) comes from the game's ownership-clearing path and is never copied.
-- A refused write is retried a few times, then dropped.
local function flush(entry)
    local next = entry.pending
    if sameProgress(next, entry.saved) then
        entry.pending = nil
        return
    end
    if next.level == 0 and next.experience == 0 and #next.skillBits == 0 then
        entry.log("reset requested by the game ignored (" .. describe(entry.saved) .. " kept)")
        entry.pending = nil
        return
    end
    if not FigureProgress.writeEnabled then
        entry.log("the game saved " .. describe(next) .. "; writing to figures is off (menu)")
        entry.saved = next
        entry.pending = nil
        return
    end
    if Crabe.Portal.writeFigureProgress(entry.slot, next) then
        entry.log("progress sent to the figure: " .. describe(next))
        entry.saved = next
        entry.pending = nil
        entry.retries = nil
    elseif (entry.retries or 0) < MAX_RETRIES then
        entry.retries = (entry.retries or 0) + 1
        entry.log("the figure refused the save; retrying in " .. RETRY_SECONDS .. " s")
        entry.dirtyAt = os.clock() + RETRY_SECONDS
    else
        entry.log("save dropped after " .. MAX_RETRIES .. " retries: " .. describe(next))
        entry.pending = nil
        entry.retries = nil
    end
end

-- Writes every save the game has finished, once no new field arrived for a second.
-- Runs on every game tick.
function FigureProgress.update()
    local now = os.clock()
    for _, entry in pairs(figures) do
        if entry.pending and now - entry.dirtyAt >= SETTLE_SECONDS then
            flush(entry)
        end
    end
end

-- Latest known progression of the figure on a slot, for the status line; nil when none.
function FigureProgress.progressOf(slot)
    local uid = uidBySlot[slot]
    local entry = uid and figures[uid]
    return entry and (entry.pending or entry.saved) or nil
end

return FigureProgress
