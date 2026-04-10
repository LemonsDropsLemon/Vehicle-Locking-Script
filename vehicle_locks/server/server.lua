-- server.lua v5.3.0

local personalVehicles     = {}
local playerOwnedVehicle   = {}
local pendingBroadcast     = false
local registrationDebounce = {}
local lockCooldowns        = {}
local flashCooldowns       = {}


local function QueueBroadcast()
    if pendingBroadcast then return end
    pendingBroadcast = true
    SetTimeout(50, function()
        pendingBroadcast = false
        TriggerClientEvent("PersonalVehicle:UpdateOwnership", -1, personalVehicles)
    end)
end

local function ClearPlayer(src)
    local prev = playerOwnedVehicle[src]
    if not prev then return end
    personalVehicles[prev] = nil
    playerOwnedVehicle[src] = nil
end

local function ClearVehicle(netIdStr)
    local owner = personalVehicles[netIdStr]
    if not owner then return false end
    personalVehicles[netIdStr]  = nil
    playerOwnedVehicle[owner]   = nil
    TriggerClientEvent("PersonalVehicle:VehicleDespawned", owner)
    return true
end

local function Assign(src, netIdStr)
    ClearPlayer(src)
    local prev = personalVehicles[netIdStr]
    if prev then playerOwnedVehicle[prev] = nil end
    personalVehicles[netIdStr] = src
    playerOwnedVehicle[src]    = netIdStr
end


local function BroadcastInRadius(eventName, x, y, z, radius, ...)
    local origin = vector3(x, y, z)
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 and #(origin - GetEntityCoords(ped)) <= radius then
            TriggerClientEvent(eventName, id, ...)
        end
    end
end


AddEventHandler("entityRemoved", function(entity)
    local ok, t = pcall(GetEntityType, entity)
    if not ok or t ~= 2 then return end
    local ok2, netId = pcall(NetworkGetNetworkIdFromEntity, entity)
    if not ok2 or netId == 0 then return end
    if ClearVehicle(tostring(netId)) then QueueBroadcast() end
end)

RegisterNetEvent("PersonalVehicle:Register", function(netId)
    local src      = source
    local netIdStr = tostring(netId)
    local key      = src .. "_" .. netIdStr
    local now      = GetGameTimer()

    if registrationDebounce[key] and now - registrationDebounce[key] < 1000 then return end
    registrationDebounce[key] = now

    if personalVehicles[netIdStr] then return end
    Assign(src, netIdStr)
    QueueBroadcast()
end)

RegisterNetEvent("PersonalVehicle:RequestOverride", function(netId)
    local src      = source
    local netIdStr = tostring(netId)
    if personalVehicles[netIdStr] == src then return end
    local prev = personalVehicles[netIdStr]
    Assign(src, netIdStr)
    QueueBroadcast()
    TriggerClientEvent("PersonalVehicle:OwnershipOverridden", -1, netIdStr, src, prev)
end)

AddEventHandler("playerDropped", function()
    local src = source
    lockCooldowns[src]  = nil
    flashCooldowns[src] = nil
    local prefix = src .. "_"
    for k in pairs(registrationDebounce) do
        if k:sub(1, #prefix) == prefix then registrationDebounce[k] = nil end
    end
    if playerOwnedVehicle[src] then
        ClearPlayer(src)
        QueueBroadcast()
    end
end)

RegisterNetEvent("PersonalVehicle:RequestFlash", function(netId, count, speed, x, y, z)
    local src = source
    local now = GetGameTimer()
    if flashCooldowns[src] and now - flashCooldowns[src] < 500 then return end
    flashCooldowns[src] = now
    BroadcastInRadius("PersonalVehicle:DoFlash", x, y, z, 150, tostring(netId), count or 1, speed or 150)
end)

RegisterNetEvent("PersonalVehicle:RequestLockToggle", function(netId, shouldLock, x, y, z, isMoto)
    local src      = source
    local netIdStr = tostring(netId)
    if personalVehicles[netIdStr] ~= src then return end
    local now = GetGameTimer()
    if lockCooldowns[src] and now - lockCooldowns[src] < 300 then return end
    lockCooldowns[src] = now

    TriggerClientEvent("PersonalVehicle:ToggleLockState", -1, netIdStr, shouldLock)

    if not isMoto and shouldLock ~= nil and x and y and z then
        local sound = shouldLock and Config.SoundFileNameLock or Config.SoundFileNameUnlock
        BroadcastInRadius("PersonalVehicle:PlaySound", x, y, z, Config.SoundReach * 1.5,
            x, y, z, Config.SoundReach, sound, Config.SoundVolume)
    end
end)

RegisterNetEvent("PersonalVehicle:StartAlarm", function(netId, x, y, z)
    if not netId or not x then return end
    BroadcastInRadius("PersonalVehicle:TriggerAlarm", x, y, z, 50, tostring(netId))
end)

RegisterNetEvent("PersonalVehicle:StopAlarm", function(netId, x, y, z)
    if not netId or not x then return end
    BroadcastInRadius("PersonalVehicle:CancelAlarm", x, y, z, 50, tostring(netId))
end)

RegisterCommand("pv_clearownership", function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, "command") then return end
    if args[1] and ClearVehicle(args[1]) then QueueBroadcast() end
end, true)

CreateThread(function()
    while true do
        Wait(60000)
        local now   = GetGameTimer()
        local stale = {}
        for k, t in pairs(registrationDebounce) do
            if now - t > 10000 then stale[#stale+1] = k end
        end
        for _, k in ipairs(stale) do registrationDebounce[k] = nil end
        for k, t in pairs(lockCooldowns) do
            if now - t > 5000 then lockCooldowns[k] = nil end
        end
        for k, t in pairs(flashCooldowns) do
            if now - t > 5000 then flashCooldowns[k] = nil end
        end
    end
end)