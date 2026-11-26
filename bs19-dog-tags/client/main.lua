-- =============================================================================
-- BS19 - Survivor Dog Tags (Developed by Trident40)
-- Client PvP Death Detection, 3D Dropped Tag Markers & Black Market Fence Blips
-- =============================================================================

local ActiveDrops = {}
local FenceBlips = {}
local ReportedCurrentDeath = false
local LastInteractAt = 0

local function getTierMarkerColor(tierId, isNemesis)
    if isNemesis then
        return 220, 38, 38 -- Crimson Nemesis glow
    end
    for _, t in ipairs(DogTagConfig.Tiers) do
        if t.id == tierId and t.color then
            return t.color[1] or 245, t.color[2] or 158, t.color[3] or 11
        end
    end
    return 245, 158, 11
end

local function drawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(245, 246, 248, 235)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function createFenceBlips()
    for _, blip in ipairs(FenceBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    FenceBlips = {}

    for _, fence in ipairs(DogTagConfig.Fences) do
        local blip = AddBlipForCoord(fence.coords.x, fence.coords.y, fence.coords.z)
        SetBlipSprite(blip, 431) -- Black Market / Trophy Broker
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.78)
        SetBlipColour(blip, 47) -- Tactical Amber
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Dog Tag Fence: ' .. fence.label)
        EndTextCommandSetBlipName(blip)
        FenceBlips[#FenceBlips + 1] = blip
    end
end

RegisterNetEvent('bs19_dogtags:syncDrops', function(drops)
    ActiveDrops = drops or {}
end)

AddEventHandler('onClientResourceStart', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    createFenceBlips()
    TriggerServerEvent('bs19_dogtags:requestSync')
end)

AddEventHandler('playerSpawned', function()
    ReportedCurrentDeath = false
    TriggerServerEvent('bs19_dogtags:requestSync')
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    for _, blip in ipairs(FenceBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
end)

-- Reliable PvP death watcher: supports on-foot & vehicle kills, reports once per death
CreateThread(function()
    while true do
        Wait(500)
        local ped = PlayerPedId()
        if IsEntityDead(ped) then
            if not ReportedCurrentDeath then
                ReportedCurrentDeath = true
                local killerEntity = GetPedSourceOfDeath(ped)
                local killerPed = nil

                if killerEntity and killerEntity ~= 0 then
                    if IsEntityAPed(killerEntity) then
                        killerPed = killerEntity
                    elseif IsEntityAVehicle(killerEntity) then
                        local driver = GetPedInVehicleSeat(killerEntity, -1)
                        if driver and driver ~= 0 then
                            killerPed = driver
                        end
                    end
                end

                local killerServerId = 0
                if killerPed and IsPedAPlayer(killerPed) then
                    local playerIdx = NetworkGetPlayerIndexFromPed(killerPed)
                    if playerIdx ~= -1 and playerIdx ~= PlayerId() then
                        killerServerId = GetPlayerServerId(playerIdx)
                    end
                end
                TriggerServerEvent('bs19_dogtags:reportDeath', killerServerId, GetEntityCoords(ped))
            end
        else
            ReportedCurrentDeath = false
        end
    end
end)

-- Main world marker loop: smooth 0-flicker 3D dropped Dog Tags & Fence terminals
CreateThread(function()
    while true do
        local sleep = 750
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local nowMs = GetGameTimer()

        -- 1. Render dropped Dog Tags
        for dropId, drop in pairs(ActiveDrops) do
            local dPos = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
            local dist = #(coords - dPos)
            if dist < 25.0 then
                sleep = 0
                local r, g, b = getTierMarkerColor(drop.tier, drop.isNemesis)

                DrawMarker(
                    2,
                    dPos.x, dPos.y, dPos.z + 0.25,
                    0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                    0.32, 0.32, 0.32,
                    r, g, b, 210,
                    true, true, 2, false, nil, nil, false
                )

                if dist < 3.0 then
                    local prefix = drop.isNemesis and '[NEMESIS] ' or ''
                    drawText3D(
                        dPos.x, dPos.y, dPos.z + 0.65,
                        ('[E] Collect %s%s Tag: %s ($%d)'):format(prefix, drop.tier, drop.victimName, drop.bountyValue)
                    )
                    if IsControlJustReleased(0, DogTagConfig.InteractKey) and (nowMs - LastInteractAt) > 750 then
                        LastInteractAt = nowMs
                        TriggerServerEvent('bs19_dogtags:collectDrop', dropId)
                    end
                end
            end
        end

        -- 2. Render Black Market Fence terminals
        for _, fence in ipairs(DogTagConfig.Fences) do
            local dist = #(coords - fence.coords)
            if dist < 20.0 then
                sleep = 0
                DrawMarker(
                    1,
                    fence.coords.x, fence.coords.y, fence.coords.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    fence.radius * 1.2, fence.radius * 1.2, 0.9,
                    217, 119, 6, 110,
                    false, false, 2, false, nil, nil, false
                )
                if dist <= fence.radius then
                    drawText3D(
                        fence.coords.x, fence.coords.y, fence.coords.z + 0.4,
                        ('[E] %s — Cash In Carried Dog Tags'):format(fence.label)
                    )
                    if IsControlJustReleased(0, DogTagConfig.InteractKey) and (nowMs - LastInteractAt) > 1000 then
                        LastInteractAt = nowMs
                        TriggerServerEvent('bs19_dogtags:cashInAll', fence.id)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
