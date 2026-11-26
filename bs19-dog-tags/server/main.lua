-- =============================================================================
-- BS19 - Survivor Dog Tags (Developed by Trident40)
-- Server-Authoritative Stamped Tags, Streak Scaling, Nemesis & Fence Payouts
-- =============================================================================

local RESOURCE_NAME = GetCurrentResourceName()
local ActiveDrops = {}       -- [dropId] = { id, tagUid, coords, victimCharId, victimName, victimFaction, victimFactionId, killerCharId, killerName, tier, tierLabel, streakMinutes, killstreak, isNemesis, bountyValue, expiresAt }
local RecentKillLocks = {}   -- ['killerId:victimId'] = expiresUnix
local LastDeathReport = {}   -- [victimSrc] = lastUnix (anti-spam guard)
local PendingCashIn = {}     -- [charId] = true (prevents async double-cash-in race)
local DropCounter = 0

local function dbg(fmt, ...)
    if not DogTagConfig.Debug then return end
    print(('^3[%s] ' .. fmt .. '^7'):format(RESOURCE_NAME, ...))
end

local function hasOxMysql()
    return GetResourceState('oxmysql') == 'started' and exports.oxmysql ~= nil
end

local function dbQuery(sql, params)
    if not hasOxMysql() then return {} end
    local ok, res = pcall(function()
        return exports.oxmysql:query_async(sql, params or {})
    end)
    if ok and type(res) == 'table' then return res end
    return {}
end

local function dbExecute(sql, params)
    if not hasOxMysql() then return 0 end
    local ok, res = pcall(function()
        return exports.oxmysql:execute_async(sql, params or {})
    end)
    if ok then
        if type(res) == 'table' and res.affectedRows then return tonumber(res.affectedRows) or 0 end
        if type(res) == 'number' then return res end
    end
    return 0
end

local function chatNotify(src, msg, rgb)
    TriggerClientEvent('chat:addMessage', src, {
        color = rgb or { 217, 119, 6 },
        args = { 'BS19 - Dog Tags', msg }
    })
end

local function makeTagUid(seqNum)
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local out = 'DT-'
    for _ = 1, 6 do
        local idx = math.random(1, #chars)
        out = out .. chars:sub(idx, idx)
    end
    return ('%s-%03d'):format(out, (seqNum or 0) % 1000)
end

-- Resolve a FiveM player's active BS19 character & faction (zero-edit Arcainex/bs19)
local function getPlayerInfo(src)
    if not src or src <= 0 then return nil end
    local charId = nil
    local charName = GetPlayerName(src) or ('Survivor #' .. tostring(src))

    if GetResourceState('bs_core') == 'started' then
        local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end)
        if ok and type(p) == 'table' then
            charId = tonumber(p.charId or p.char_id or p.id or (p.char and p.char.id))
            if p.first_name then
                local combined = (tostring(p.first_name) .. ' ' .. tostring(p.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
                if combined ~= '' then charName = combined end
            elseif p.char and p.char.first_name then
                local combined = (tostring(p.char.first_name) .. ' ' .. tostring(p.char.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
                if combined ~= '' then charName = combined end
            end
        end
    end

    if not charId then
        local license = GetPlayerIdentifierByType(src, 'license')
        if license then
            local rows = dbQuery([[
                SELECT c.id, TRIM(CONCAT(COALESCE(c.first_name, ''), ' ', COALESCE(c.last_name, ''))) AS full_name
                FROM bs_users u
                JOIN bs_characters c ON c.user_id = u.id AND c.deleted_at IS NULL
                WHERE u.identifier = ?
                ORDER BY c.last_played DESC
                LIMIT 1
            ]], { license })
            if rows[1] then
                charId = tonumber(rows[1].id)
                if rows[1].full_name and rows[1].full_name ~= '' then
                    charName = rows[1].full_name
                end
            end
        end
    end

    if not charId then return nil end

    local fRows = dbQuery([[
        SELECT m.faction_id, r.label AS faction_label, r.short AS faction_short
        FROM bs_faction_members m
        LEFT JOIN bs_faction_registry r ON r.faction_id = m.faction_id
        WHERE m.character_id = ?
        LIMIT 1
    ]], { charId })

    local f = fRows[1]
    return {
        src = src,
        charId = charId,
        charName = charName,
        factionId = f and f.faction_id or nil,
        factionLabel = (f and f.faction_label) or 'Lone Wolf',
        factionShort = (f and f.faction_short) or 'SOLO'
    }
end

local function ensureStreakRow(info)
    local now = os.time()
    local rows = dbQuery('SELECT * FROM bs_dog_tag_streaks WHERE char_id = ? LIMIT 1', { info.charId })
    if rows[1] then
        return rows[1]
    end
    dbExecute(
        'INSERT IGNORE INTO bs_dog_tag_streaks (char_id, char_name, alive_since) VALUES (?, ?, ?)',
        { info.charId, info.charName, now }
    )
    return {
        char_id = info.charId,
        char_name = info.charName,
        alive_since = now,
        killstreak = 0,
        best_streak_minutes = 0,
        tags_collected = 0,
        tags_cashed = 0,
        total_earned = 0
    }
end

local function computeTierAndValue(aliveMinutes, killstreak, isNemesis)
    local selected = DogTagConfig.Tiers[#DogTagConfig.Tiers]
    for _, tier in ipairs(DogTagConfig.Tiers) do
        if aliveMinutes >= tier.minAliveMinutes or killstreak >= tier.minKillstreak then
            selected = tier
            break
        end
    end

    local streakBonus = math.min(
        DogTagConfig.MaxKillstreakBonus,
        math.max(0, killstreak) * DogTagConfig.KillstreakBonusPerKill
    )
    local rawValue = selected.baseValue + streakBonus
    if isNemesis then
        rawValue = math.floor(rawValue * (DogTagConfig.NemesisMultiplier or 1.5))
    end

    return selected, rawValue
end

local function creditPlayerCash(src, charId, amount)
    if amount <= 0 then return end
    local paid = false

    -- Attempt native bs_core money export if present
    if GetResourceState('bs_core') == 'started' then
        local ok = pcall(function()
            if exports.bs_core.AddMoney then
                exports.bs_core:AddMoney(src, 'cash', amount, 'bs19_dog_tag_fence')
                paid = true
            end
        end)
        if ok and paid then return end
    end

    -- Fallback: emit clean server event hook + notify player so custom economy scripts can listen
    TriggerEvent('bs19_dogtags:payoutCash', src, charId, amount)
    dbg('Dispatched bs19_dogtags:payoutCash fallback hook for char #%d ($%d)', charId, amount)
end

local function syncDropsToClients(targetSrc)
    TriggerClientEvent('bs19_dogtags:syncDrops', targetSrc or -1, ActiveDrops)
end

-- =============================================================================
-- 1. DATABASE BOOTSTRAP & EXPIRY SWEEP
-- =============================================================================
local function bootstrapDatabase()
    if not hasOxMysql() then
        print(('^1[%s] oxmysql is not started; persistence disabled.^7'):format(RESOURCE_NAME))
        return
    end

    dbExecute([[
        CREATE TABLE IF NOT EXISTS bs_dog_tags (
            id INT AUTO_INCREMENT PRIMARY KEY,
            tag_uid VARCHAR(24) NOT NULL UNIQUE,
            victim_char_id INT NOT NULL,
            victim_name VARCHAR(80) NOT NULL,
            victim_faction VARCHAR(80) DEFAULT 'Lone Wolf',
            killer_char_id INT NOT NULL,
            killer_name VARCHAR(80) NOT NULL,
            owner_char_id INT DEFAULT NULL,
            tier VARCHAR(16) NOT NULL DEFAULT 'BRONZE',
            streak_minutes INT NOT NULL DEFAULT 0,
            killstreak INT NOT NULL DEFAULT 0,
            is_nemesis TINYINT(1) NOT NULL DEFAULT 0,
            bounty_value INT NOT NULL DEFAULT 500,
            status VARCHAR(16) NOT NULL DEFAULT 'CARRIED',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            cashed_at TIMESTAMP NULL DEFAULT NULL,
            INDEX idx_owner_status (owner_char_id, status),
            INDEX idx_killer_victim (killer_char_id, victim_char_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    dbExecute([[
        CREATE TABLE IF NOT EXISTS bs_dog_tag_streaks (
            char_id INT NOT NULL PRIMARY KEY,
            char_name VARCHAR(80) NOT NULL,
            alive_since BIGINT NOT NULL,
            killstreak INT NOT NULL DEFAULT 0,
            best_streak_minutes INT NOT NULL DEFAULT 0,
            tags_collected INT NOT NULL DEFAULT 0,
            tags_cashed INT NOT NULL DEFAULT 0,
            total_earned INT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    dbExecute([[
        CREATE TABLE IF NOT EXISTS bs_dog_tag_nemesis (
            killer_char_id INT NOT NULL,
            victim_char_id INT NOT NULL,
            kills INT NOT NULL DEFAULT 1,
            last_kill_at BIGINT NOT NULL,
            PRIMARY KEY (killer_char_id, victim_char_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    print(('^2[%s] BS19 - Survivor Dog Tags (Developed by Trident40) initialized with %d Fence drop-offs.^7'):format(
        RESOURCE_NAME, #DogTagConfig.Fences
    ))
end

CreateThread(function()
    Wait(2000)
    bootstrapDatabase()

    while true do
        Wait(15000)
        local now = os.time()
        local removed = false
        for dropId, drop in pairs(ActiveDrops) do
            if drop.expiresAt <= now then
                ActiveDrops[dropId] = nil
                removed = true
            end
        end
        if removed then
            syncDropsToClients(-1)
        end
    end
end)

-- =============================================================================
-- 2. PLAYER LIFECYCLE & PVP DOG TAG DROP HANDLER
-- =============================================================================
AddEventHandler('playerDropped', function()
    local src = source
    LastDeathReport[src] = nil
end)

RegisterNetEvent('bs19_dogtags:requestSync', function()
    local src = source
    local info = getPlayerInfo(src)
    if info then
        ensureStreakRow(info)
    end
    syncDropsToClients(src)
end)

RegisterNetEvent('bs19_dogtags:reportDeath', function(killerServerId, deathCoords)
    local victimSrc = source
    local now = os.time()

    -- Server-side anti-spam guard: ignore duplicate death reports within 5 seconds
    if LastDeathReport[victimSrc] and (now - LastDeathReport[victimSrc]) < 5 then
        return
    end
    LastDeathReport[victimSrc] = now

    local victimInfo = getPlayerInfo(victimSrc)
    if not victimInfo then return end

    local victimPed = GetPlayerPed(victimSrc)
    if not victimPed or victimPed == 0 then return end

    local victimStreak = ensureStreakRow(victimInfo)
    local aliveMinutes = math.max(0, math.floor((now - (tonumber(victimStreak.alive_since) or now)) / 60))
    local victimKills = tonumber(victimStreak.killstreak) or 0
    local bestStreak = math.max(tonumber(victimStreak.best_streak_minutes) or 0, aliveMinutes)

    -- Always reset victim's living streak & killstreak on death
    dbExecute(
        'UPDATE bs_dog_tag_streaks SET char_name = ?, alive_since = ?, killstreak = 0, best_streak_minutes = ? WHERE char_id = ?',
        { victimInfo.charName, now, bestStreak, victimInfo.charId }
    )

    local killerSrc = tonumber(killerServerId)
    if not killerSrc or killerSrc <= 0 or killerSrc == victimSrc then
        return -- PvE / environmental death does not spawn a PvP dog tag
    end

    local killerPed = GetPlayerPed(killerSrc)
    if not killerPed or killerPed == 0 then return end

    -- Authoritative server coordinates (prevents client-spoofed drop locations near Fences)
    local dropCoords = GetEntityCoords(victimPed)
    if (dropCoords.x == 0.0 and dropCoords.y == 0.0 and dropCoords.z == 0.0) and type(deathCoords) == 'vector3' then
        dropCoords = deathCoords
    end

    -- Verify killer was within plausible combat range (450m max OneSync sniper range)
    local killerCoords = GetEntityCoords(killerPed)
    if #(dropCoords - killerCoords) > 450.0 then
        dbg('Ignored implausible remote kill report from src %d -> %d', killerSrc, victimSrc)
        return
    end

    local killerInfo = getPlayerInfo(killerSrc)
    if not killerInfo or killerInfo.charId == victimInfo.charId then return end

    -- Anti-exploit: same-faction kills never spawn paid tags
    if DogTagConfig.BlockSameFactionTags and killerInfo.factionId and killerInfo.factionId == victimInfo.factionId then
        chatNotify(killerSrc, 'Friendly-fire kill detected — no Dog Tag dropped.', { 148, 163, 184 })
        return
    end

    -- Anti-farm: same killer -> same victim cooldown
    local lockKey = ('%d:%d'):format(killerInfo.charId, victimInfo.charId)
    if RecentKillLocks[lockKey] and RecentKillLocks[lockKey] > now then
        local minsLeft = math.ceil((RecentKillLocks[lockKey] - now) / 60)
        chatNotify(killerSrc, ('Anti-farm cooldown active for %s (%dm left) — no Dog Tag dropped.'):format(victimInfo.charName, minsLeft), { 148, 163, 184 })
        return
    end
    RecentKillLocks[lockKey] = now + (DogTagConfig.SameVictimCooldownMinutes * 60)

    -- Increment killer's active killstreak
    ensureStreakRow(killerInfo)
    dbExecute(
        'UPDATE bs_dog_tag_streaks SET char_name = ?, killstreak = killstreak + 1 WHERE char_id = ?',
        { killerInfo.charName, killerInfo.charId }
    )

    -- Check Nemesis status: did the victim previously eliminate this killer >= threshold times?
    local revRows = dbQuery(
        'SELECT kills FROM bs_dog_tag_nemesis WHERE killer_char_id = ? AND victim_char_id = ? LIMIT 1',
        { victimInfo.charId, killerInfo.charId }
    )
    local isNemesis = (revRows[1] ~= nil) and ((tonumber(revRows[1].kills) or 0) >= DogTagConfig.NemesisThreshold) or false

    -- If Nemesis is settled, clear the victim's prior rivalry tally so payback resets cleanly
    if isNemesis then
        dbExecute(
            'DELETE FROM bs_dog_tag_nemesis WHERE killer_char_id = ? AND victim_char_id = ?',
            { victimInfo.charId, killerInfo.charId }
        )
    end

    -- Record killer -> victim rivalry kill
    dbExecute([[
        INSERT INTO bs_dog_tag_nemesis (killer_char_id, victim_char_id, kills, last_kill_at)
        VALUES (?, ?, 1, ?)
        ON DUPLICATE KEY UPDATE kills = kills + 1, last_kill_at = VALUES(last_kill_at)
    ]], { killerInfo.charId, victimInfo.charId, now })

    local tier, bountyValue = computeTierAndValue(aliveMinutes, victimKills, isNemesis)

    DropCounter = DropCounter + 1
    local dropId = 'drop_' .. tostring(DropCounter)
    local tagUid = makeTagUid(DropCounter)

    ActiveDrops[dropId] = {
        id = dropId,
        tagUid = tagUid,
        coords = { x = dropCoords.x, y = dropCoords.y, z = dropCoords.z },
        victimCharId = victimInfo.charId,
        victimName = victimInfo.charName,
        victimFaction = victimInfo.factionLabel,
        victimFactionId = victimInfo.factionId,
        killerCharId = killerInfo.charId,
        killerName = killerInfo.charName,
        tier = tier.id,
        tierLabel = tier.label,
        streakMinutes = aliveMinutes,
        killstreak = victimKills,
        isNemesis = isNemesis,
        bountyValue = bountyValue,
        expiresAt = now + (DogTagConfig.TagDespawnMinutes * 60)
    }

    syncDropsToClients(-1)

    if isNemesis then
        chatNotify(-1, ('[NEMESIS SETTLED] %s eliminated their Nemesis %s — %s Tag ($%d) dropped!'):format(
            killerInfo.charName, victimInfo.charName, tier.id, bountyValue
        ), { 220, 38, 38 })
    else
        chatNotify(killerSrc, ('Dropped %s Dog Tag for %s (%s · $%d). Loot it from the body with [E]!'):format(
            tier.id, victimInfo.charName, tier.label, bountyValue
        ), { 245, 158, 11 })
    end

    dbg('Spawned drop %s (%s) for victim %s killed by %s ($%d)', dropId, tier.id, victimInfo.charName, killerInfo.charName, bountyValue)
end)

-- =============================================================================
-- 3. LOOTING DROPPED TAGS & BLACK MARKET FENCE CASH-IN
-- =============================================================================
RegisterNetEvent('bs19_dogtags:collectDrop', function(dropId)
    local src = source
    local drop = ActiveDrops[dropId]
    if not drop then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local dCoords = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
    if #(pCoords - dCoords) > 6.0 then return end

    local looter = getPlayerInfo(src)
    if not looter then return end

    -- Remove drop atomically to prevent double pickup
    ActiveDrops[dropId] = nil
    syncDropsToClients(-1)

    -- Check if victim or same-faction ally reclaimed the tag (denies killer payout!)
    local isReclaim = (looter.charId == drop.victimCharId) or
        (drop.victimFactionId ~= nil and looter.factionId == drop.victimFactionId)

    local finalStatus = isReclaim and 'RECLAIMED' or 'CARRIED'

    dbExecute([[
        INSERT INTO bs_dog_tags
            (tag_uid, victim_char_id, victim_name, victim_faction, killer_char_id, killer_name, owner_char_id, tier, streak_minutes, killstreak, is_nemesis, bounty_value, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        drop.tagUid, drop.victimCharId, drop.victimName, drop.victimFaction,
        drop.killerCharId, drop.killerName, looter.charId, drop.tier,
        drop.streakMinutes, drop.killstreak, drop.isNemesis and 1 or 0,
        drop.bountyValue, finalStatus
    })

    if isReclaim then
        chatNotify(src, ('Reclaimed friendly Dog Tag [%s] (%s) — bounty denied to enemy hunters!'):format(
            drop.tagUid, drop.victimName
        ), { 22, 163, 74 })
    else
        ensureStreakRow(looter)
        dbExecute('UPDATE bs_dog_tag_streaks SET tags_collected = tags_collected + 1 WHERE char_id = ?', { looter.charId })
        chatNotify(src, ('Collected %s Dog Tag [%s] — %s (%s · $%d). Visit a Black Market Fence to cash in!'):format(
            drop.isNemesis and 'NEMESIS ' .. drop.tier or drop.tier,
            drop.tagUid, drop.victimName, drop.victimFaction, drop.bountyValue
        ), { 245, 158, 11 })
    end
end)

RegisterNetEvent('bs19_dogtags:cashInAll', function(fenceId)
    local src = source
    local fence = nil
    for _, f in ipairs(DogTagConfig.Fences) do
        if f.id == fenceId then fence = f break end
    end
    if not fence then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    if #(GetEntityCoords(ped) - fence.coords) > (fence.radius + 4.0) then return end

    local info = getPlayerInfo(src)
    if not info then return end

    -- Mutex lock prevents concurrent async DB calls from double-paying on [E] spam
    if PendingCashIn[info.charId] then return end
    PendingCashIn[info.charId] = true

    local ok, err = pcall(function()
        local carried = dbQuery(
            'SELECT id, bounty_value FROM bs_dog_tags WHERE owner_char_id = ? AND status = ?',
            { info.charId, 'CARRIED' }
        )
        if #carried == 0 then
            chatNotify(src, 'You are not carrying any uncashed survivor Dog Tags.', { 148, 163, 184 })
            return
        end

        local totalPayout = 0
        for _, row in ipairs(carried) do
            totalPayout = totalPayout + (tonumber(row.bounty_value) or 0)
        end

        local affected = dbExecute(
            'UPDATE bs_dog_tags SET status = ?, cashed_at = NOW() WHERE owner_char_id = ? AND status = ?',
            { 'CASHED', info.charId, 'CARRIED' }
        )
        if affected <= 0 then return end

        ensureStreakRow(info)
        dbExecute(
            'UPDATE bs_dog_tag_streaks SET tags_cashed = tags_cashed + ?, total_earned = total_earned + ? WHERE char_id = ?',
            { #carried, totalPayout, info.charId }
        )

        local factionCut = 0
        if info.factionId and (DogTagConfig.FactionBankCutPercent or 0) > 0 then
            factionCut = math.floor(totalPayout * (DogTagConfig.FactionBankCutPercent / 100.0))
            if factionCut > 0 then
                dbExecute([[
                    INSERT INTO bs_faction_banks (faction_id, balance)
                    VALUES (?, ?)
                    ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)
                ]], { info.factionId, factionCut })
            end
        end

        local personalCut = totalPayout - factionCut
        creditPlayerCash(src, info.charId, personalCut)

        if factionCut > 0 then
            chatNotify(src, ('Cashed in %d Dog Tag(s) at %s! Received $%d (+$%d deposited to %s treasury).'):format(
                #carried, fence.label, personalCut, factionCut, info.factionLabel
            ), { 22, 163, 74 })
        else
            chatNotify(src, ('Cashed in %d Dog Tag(s) at %s for $%d!'):format(
                #carried, fence.label, personalCut
            ), { 22, 163, 74 })
        end
    end)

    PendingCashIn[info.charId] = nil
    if not ok then
        print(('^1[%s] Error during cashInAll for char #%d: %s^7'):format(RESOURCE_NAME, info.charId, tostring(err)))
    end
end)

-- =============================================================================
-- 4. IN-GAME COMMANDS (/dogtags, /tagboard) & ADMIN RESET
-- =============================================================================
RegisterCommand('dogtags', function(source)
    if source <= 0 then return end
    local info = getPlayerInfo(source)
    if not info then return end

    local st = ensureStreakRow(info)
    local aliveMins = math.max(0, math.floor((os.time() - (tonumber(st.alive_since) or os.time())) / 60))
    local tier, selfVal = computeTierAndValue(aliveMins, tonumber(st.killstreak) or 0, false)

    local carried = dbQuery(
        'SELECT tag_uid, victim_name, tier, bounty_value, is_nemesis FROM bs_dog_tags WHERE owner_char_id = ? AND status = ? ORDER BY id DESC',
        { info.charId, 'CARRIED' }
    )

    chatNotify(source, ('Your Living Tag: %s (%s) | Value: $%d | Alive: %dm | Killstreak: %d'):format(
        tier.id, tier.label, selfVal, aliveMins, tonumber(st.killstreak) or 0
    ), { 245, 158, 11 })

    if #carried == 0 then
        chatNotify(source, 'Carried Trophies: None. Eliminate hostile survivors and loot their tags with [E].', { 148, 163, 184 })
    else
        local total = 0
        for idx, t in ipairs(carried) do
            total = total + (tonumber(t.bounty_value) or 0)
            if idx <= 10 then
                chatNotify(source, ('  [%s] %s — %s%s ($%d)'):format(
                    t.tag_uid, t.victim_name, t.is_nemesis == 1 and 'NEMESIS ' or '', t.tier, tonumber(t.bounty_value) or 0
                ), { 229, 231, 235 })
            end
        end
        if #carried > 10 then
            chatNotify(source, ('  ...and %d more carried tag(s).'):format(#carried - 10), { 148, 163, 184 })
        end
        chatNotify(source, ('Total Carried Value: $%d (%d tags) — cash in at any Fence.'):format(total, #carried), { 22, 163, 74 })
    end
end, false)

RegisterCommand('tagboard', function(source)
    if source <= 0 then return end
    local top = dbQuery([[
        SELECT char_name, tags_cashed, total_earned
        FROM bs_dog_tag_streaks
        WHERE tags_cashed > 0
        ORDER BY total_earned DESC
        LIMIT 5
    ]])

    chatNotify(source, 'Top Wasteland Tag Hunters:', { 245, 158, 11 })
    if #top == 0 then
        chatNotify(source, 'No Dog Tags have been cashed in yet this wipe.', { 148, 163, 184 })
        return
    end
    for i, row in ipairs(top) do
        chatNotify(source, ('#%d %s — %d tags cashed ($%d earned)'):format(
            i, row.char_name, tonumber(row.tags_cashed) or 0, tonumber(row.total_earned) or 0
        ), { 229, 231, 235 })
    end
end, false)

RegisterCommand('dogtagreset', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command.dogtagreset') then return end
    local target = args[1] or 'all'
    if target == 'all' then
        ActiveDrops = {}
        RecentKillLocks = {}
        LastDeathReport = {}
        dbExecute('DELETE FROM bs_dog_tags')
        dbExecute('DELETE FROM bs_dog_tag_streaks')
        dbExecute('DELETE FROM bs_dog_tag_nemesis')
        syncDropsToClients(-1)
        print(('^2[%s] Reset all Survivor Dog Tags, streaks, and Nemesis records.^7'):format(RESOURCE_NAME))
    else
        local cid = tonumber(target)
        if cid then
            for dropId, drop in pairs(ActiveDrops) do
                if drop.victimCharId == cid or drop.killerCharId == cid then
                    ActiveDrops[dropId] = nil
                end
            end
            dbExecute('DELETE FROM bs_dog_tags WHERE owner_char_id = ? OR victim_char_id = ?', { cid, cid })
            dbExecute('DELETE FROM bs_dog_tag_streaks WHERE char_id = ?', { cid })
            dbExecute('DELETE FROM bs_dog_tag_nemesis WHERE killer_char_id = ? OR victim_char_id = ?', { cid, cid })
            syncDropsToClients(-1)
            print(('^2[%s] Reset Dog Tag, streak, and Nemesis records for character #%d.^7'):format(RESOURCE_NAME, cid))
        end
    end
end, false)

-- =============================================================================
-- 5. PUBLIC SERVER EXPORTS (For integration with other BS19 scripts)
-- =============================================================================
exports('GetPlayerTagValue', function(src)
    local info = getPlayerInfo(src)
    if not info then return nil end
    local st = ensureStreakRow(info)
    local aliveMins = math.max(0, math.floor((os.time() - (tonumber(st.alive_since) or os.time())) / 60))
    local ks = tonumber(st.killstreak) or 0
    local tier, val = computeTierAndValue(aliveMins, ks, false)
    return { tier = tier.id, label = tier.label, value = val, aliveMinutes = aliveMins, killstreak = ks }
end)

exports('GetCarriedTags', function(src)
    local info = getPlayerInfo(src)
    if not info then return {} end
    return dbQuery('SELECT * FROM bs_dog_tags WHERE owner_char_id = ? AND status = ?', { info.charId, 'CARRIED' })
end)

exports('IsNemesis', function(killerCharId, victimCharId)
    local rows = dbQuery(
        'SELECT kills FROM bs_dog_tag_nemesis WHERE killer_char_id = ? AND victim_char_id = ? LIMIT 1',
        { tonumber(killerCharId) or 0, tonumber(victimCharId) or 0 }
    )
    local kills = rows[1] and (tonumber(rows[1].kills) or 0) or 0
    return kills >= DogTagConfig.NemesisThreshold, kills
end)

exports('GetTopHunters', function(limit)
    local lim = math.max(1, math.min(25, tonumber(limit) or 5))
    return dbQuery(
        'SELECT char_id, char_name, tags_collected, tags_cashed, total_earned FROM bs_dog_tag_streaks ORDER BY total_earned DESC LIMIT ?',
        { lim }
    )
end)
