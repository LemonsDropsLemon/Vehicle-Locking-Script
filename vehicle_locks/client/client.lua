-- client.lua | Personal Vehicle System v5.4.0

if Config.SuppressConsoleWarnings then
    local _trace = Citizen.Trace
    Citizen.Trace = function(msg)
        if not msg:find("GetNetworkObject: no object by ID", 1, true)
        and not msg:find("SCRIPT ERROR: Invalid entity",     1, true) then
            _trace(msg)
        end
    end
end

local function dbg(...) if Config.DebugMode then print("^3[PV]^7", ...) end end

-- Constants

local DOUBLE_TAP        = 400
local ANIM_CAR_DICT      = "anim@mp_player_intmenu@key_fob@"
local ANIM_MOTO_DICT     = "amb@code_human_medic_tend_to_dead@base"
local ANIM_MOTO_CLIP     = "base"
local ANIM_BICYCLE_DICT  = "anim@heists@ornate_bank@hack"
local ANIM_BICYCLE_CLIP  = "hack_loop"
local ANIM_AIRCRAFT_DICT = "mini@atmenter"
local ANIM_AIRCRAFT_CLIP = "enter"

local INVALID_CLASS = { [14]=true,[21]=true,[22]=true }

-- State

local personalVehicles  = {}
local myOwnedNetId      = nil
local lastRegisteredVeh = 0
local activeAlarms      = {}
local alarmFlashThreads = {}
local cooldown          = false
local lastPressTime     = 0
local currentVehicle    = 0
local lastSoundTime     = 0

local MY_SERVER_ID = GetPlayerServerId(PlayerId())

-- Anim Preload

CreateThread(function()
    RequestAnimDict(ANIM_CAR_DICT)
    RequestAnimDict(ANIM_MOTO_DICT)
    RequestAnimDict(ANIM_BICYCLE_DICT)
    RequestAnimDict(ANIM_AIRCRAFT_DICT)
    repeat Wait(200) until HasAnimDictLoaded(ANIM_CAR_DICT)
                      and HasAnimDictLoaded(ANIM_MOTO_DICT)
                      and HasAnimDictLoaded(ANIM_BICYCLE_DICT)
                      and HasAnimDictLoaded(ANIM_AIRCRAFT_DICT)
    dbg("Animation dicts ready")
end)

-- Helpers

local function GetVehicleType(veh)
    if not DoesEntityExist(veh) then return false end
    local cls = GetVehicleClass(veh)
    if cls == 8  then return "moto"     end
    if cls == 13 then return "bicycle"  end
    if cls == 15 or cls == 16 then return "aircraft" end
    local wheels = GetVehicleNumberOfWheels(veh)
    if cls == 18 and wheels == 2 then return "moto" end
    if INVALID_CLASS[cls] or wheels <= 2 then return false end
    return "car"
end

local function GetOwnedVehicle()
    if not myOwnedNetId then return nil, nil end
    local netId = tonumber(myOwnedNetId)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return nil, nil end
    local ent   = NetworkGetEntityFromNetworkId(netId)
    local vtype = GetVehicleType(ent)
    if not vtype then return nil, nil end
    return ent, vtype
end

local function GetCamFwd()
    local r   = GetGameplayCamRot(2)
    local rad = math.rad(r.z)
    return -math.sin(rad), math.cos(rad)
end

local function UpdateMyOwnedNetId()
    for k, v in pairs(personalVehicles) do
        if v == MY_SERVER_ID then myOwnedNetId = k; return end
    end
    myOwnedNetId = nil
end

local function EnsureNetworkControl(veh)
    if NetworkHasControlOfEntity(veh) then return true end
    NetworkRequestControlOfEntity(veh)
    local deadline = GetGameTimer() + 500
    while GetGameTimer() < deadline do
        if NetworkHasControlOfEntity(veh) then return true end
        Wait(10)
    end
    return false
end

local function IsFacingVehicle(ped, veh, maxAngle)
    local pp     = GetEntityCoords(ped)
    local vp     = GetEntityCoords(veh)
    local dx, dy = vp.x - pp.x, vp.y - pp.y
    local len    = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return false end
    local rad        = math.rad(GetEntityHeading(ped))
    local fwdX, fwdY = -math.sin(rad), math.cos(rad)
    local dot        = math.max(-1.0, math.min(1.0, (dx * fwdX + dy * fwdY) / len))
    return math.deg(math.acos(dot)) <= maxAngle
end

local function notify(msg)
    if not Config.EnableNotifications then return end
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

-- Flash

local function FlashLocal(veh, count, speed)
    if not DoesEntityExist(veh) then return end
    local nId = NetworkGetNetworkIdFromEntity(veh)
    if nId and nId ~= 0 and activeAlarms[tostring(nId)] then return end
    for _ = 1, count do
        SetVehicleLights(veh, 2); Wait(speed)
        SetVehicleLights(veh, 0); Wait(speed)
    end
end

local function RequestFlash(netId, count, speed, coords)
    TriggerServerEvent("PersonalVehicle:RequestFlash", netId, count, speed, coords.x, coords.y, coords.z)
end

local function StartIndicatorFlash(netIdStr, veh)
    if alarmFlashThreads[netIdStr] then return end
    alarmFlashThreads[netIdStr] = true
    CreateThread(function()
        while alarmFlashThreads[netIdStr] and DoesEntityExist(veh) do
            if NetworkHasControlOfEntity(veh) then
                SetVehicleLights(veh, 2)
                Wait(250)
                if not alarmFlashThreads[netIdStr] then break end
                SetVehicleLights(veh, 0)
                Wait(250)
            else
                Wait(100)
            end
        end
        if DoesEntityExist(veh) and NetworkHasControlOfEntity(veh) then
            SetVehicleLights(veh, 0)
        end
        alarmFlashThreads[netIdStr] = nil
    end)
end

local function StopIndicatorFlash(netIdStr, veh)
    alarmFlashThreads[netIdStr] = nil
    if veh and DoesEntityExist(veh) and NetworkHasControlOfEntity(veh) then
        SetVehicleLights(veh, 0)
    end
end

local function ClearAlarmLocally(veh, netIdStr)
    activeAlarms[netIdStr] = nil
    SendNUIMessage({ transactionType = "stopAlarm", key = netIdStr })
    StopIndicatorFlash(netIdStr, veh)
    if netIdStr == myOwnedNetId and Config.AlarmHudEnabled then
        SendNUIMessage({ transactionType = "hideAlarmHud" })
    end
end

-- Alarm NUI

local function SendAlarmNUI(netIdStr, veh, ped)
    if not Config.AlarmSoundEnabled or not Config.EnableSound then return end
    local ac         = GetEntityCoords(veh)
    local pc         = GetEntityCoords(ped)
    local fwdX, fwdY = GetCamFwd()
    SendNUIMessage({
        transactionType = "startAlarm",
        key             = netIdStr,
        file            = Config.AlarmSoundFile,
        volume          = Config.AlarmSoundVolume,
        maxDist         = Config.AlarmSoundReach,
        reverbEnabled   = Config.AlarmReverbEnabled,
        reverbMaxWet    = Config.AlarmReverbMaxWet,
        reverbStart     = Config.AlarmReverbStart,
        srcX            = ac.x,
        srcY            = ac.y,
        playerX         = pc.x,
        playerY         = pc.y,
        fwdX            = fwdX,
        fwdY            = fwdY,
    })
end

-- Exterior Lock Toggle

local function ToggleLock()
    if cooldown then return end

    local veh, vehType = GetOwnedVehicle()
    if not veh then return end

    local ped    = PlayerPedId()
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver ~= 0 and driver ~= ped then return end

    local isMoto     = vehType == "moto"
    local isBicycle  = vehType == "bicycle"
    local isAircraft = vehType == "aircraft"

    local coords  = GetEntityCoords(veh)
    local maxDist = isMoto     and Config.MotorcycleMaxLockDistance
                 or isBicycle  and Config.BicycleMaxLockDistance
                 or isAircraft and Config.AircraftMaxLockDistance
                 or Config.MaxLockDistance

    if #(GetEntityCoords(ped) - coords) > maxDist then return end

    if isMoto and Config.MotorcycleRequireFacing then
        if not IsFacingVehicle(ped, veh, Config.MotorcycleFacingAngle) then
            notify("You must be ~r~facing~s~ the motorcycle to lock it.")
            return
        end
    end

    if isBicycle and Config.BicycleRequireFacing then
        if not IsFacingVehicle(ped, veh, Config.BicycleFacingAngle) then
            notify("You must be ~r~facing~s~ the bicycle to lock it.")
            return
        end
    end

    if isAircraft and Config.AircraftRequireFacing then
        if not IsFacingVehicle(ped, veh, Config.AircraftFacingAngle) then
            notify("You must be ~r~facing~s~ the aircraft to lock it.")
            return
        end
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId == 0 then return end

    cooldown = true

    local status        = GetVehicleDoorLockStatus(veh)
    local shouldLock    = status == 0 or status == 1
    local suppressSound = (isMoto and not Config.MotorcycleSoundsEnabled) or isBicycle

    if GetVehiclePedIsIn(ped, false) ~= veh and not EnsureNetworkControl(veh) then
        TriggerServerEvent("PersonalVehicle:RequestLockToggle", netId, shouldLock, coords.x, coords.y, coords.z, suppressSound)
        cooldown = false
        return
    end

    if isBicycle then
        if Config.BicycleFreezePlayer then FreezeEntityPosition(ped, true) end
        TaskPlayAnim(ped, ANIM_BICYCLE_DICT, ANIM_BICYCLE_CLIP, 8.0, 8.0, Config.BicycleAnimationDuration, 1, 0, false, false, false)
        Wait(Config.BicycleAnimationDuration)
        if Config.BicycleFreezePlayer then FreezeEntityPosition(ped, false) end
    elseif isMoto then
        if Config.MotorcycleFreezePlayer then FreezeEntityPosition(ped, true) end
        TaskPlayAnim(ped, ANIM_MOTO_DICT, ANIM_MOTO_CLIP, 8.0, 8.0, Config.MotorcycleAnimationDuration, 1, 0, false, false, false)
        Wait(Config.MotorcycleAnimationDuration)
        if Config.MotorcycleFreezePlayer then FreezeEntityPosition(ped, false) end
    elseif isAircraft then
        if Config.AircraftFreezePlayer then FreezeEntityPosition(ped, true) end
        TaskPlayAnim(ped, ANIM_AIRCRAFT_DICT, ANIM_AIRCRAFT_CLIP, 8.0, 8.0, Config.AircraftAnimationDuration, 48, 0, false, false, false)
        Wait(Config.AircraftAnimationDuration)
        if Config.AircraftFreezePlayer then FreezeEntityPosition(ped, false) end
    else
        TaskPlayAnim(ped, ANIM_CAR_DICT, "fob_click_fp", 8.0, 8.0, -1, 48, 0, false, false, false)
    end

    local netIdStr = tostring(netId)

    if shouldLock then
        SetVehicleDoorsLocked(veh, 2)
        if not isMoto and not isBicycle and not isAircraft then RequestFlash(netId, 1, 150, coords) end
        if Config.ShowVehicleName then
            notify(string.format(Config.Messages.VehicleLockedWithName, GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))))
        else
            notify(Config.Messages.VehicleLocked)
        end
    else
        SetVehicleDoorsLocked(veh, 1)
        if activeAlarms[netIdStr] then
            ClearAlarmLocally(veh, netIdStr)
            TriggerServerEvent("PersonalVehicle:StopAlarm", netId, coords.x, coords.y, coords.z)
        end
        if Config.ShowVehicleName then
            notify(string.format(Config.Messages.VehicleUnlockedWithName, GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))))
        else
            notify(Config.Messages.VehicleUnlocked)
        end
        SetTimeout(250, function()
            if not isMoto and not isBicycle and not isAircraft and DoesEntityExist(veh) then
                RequestFlash(netId, 2, 150, GetEntityCoords(veh))
            end
        end)
    end

    if Config.HudEnabled then
        SendNUIMessage({
            transactionType = "showLockHud",
            locked          = shouldLock,
            displayTime     = Config.HudDisplayTime,
        })
    end

    if isBicycle and Config.EnableSound and Config.BicycleSoundsEnabled then
        SendNUIMessage({
            transactionType = "playDirectSound",
            file            = shouldLock and Config.BicycleLockSound or Config.BicycleUnlockSound,
            volume          = Config.BicycleSoundVolume,
        })
    end

    if isAircraft and Config.EnableSound and Config.AircraftSoundsEnabled then
        local soundFile  = shouldLock and Config.AircraftLockSound or Config.AircraftUnlockSound
        local pedInVeh   = GetVehiclePedIsIn(ped, false)
        if pedInVeh == veh then
            SendNUIMessage({
                transactionType = "playDirectSound",
                file            = soundFile,
                volume          = Config.AircraftSoundVolume,
            })
        else
            local pc         = GetEntityCoords(ped)
            local fwdX, fwdY = GetCamFwd()
            lastSoundTime = GetGameTimer()
            SendNUIMessage({
                transactionType = "playSound",
                file            = soundFile,
                volume          = Config.AircraftOutsideVolume,
                maxDist         = Config.AircraftSoundReach,
                muffleFreq      = Config.AircraftSoundMuffleFreq,
                reverbEnabled   = false,
                srcX            = coords.x,
                srcY            = coords.y,
                playerX         = pc.x,
                playerY         = pc.y,
                fwdX            = fwdX,
                fwdY            = fwdY,
            })
        end
    end

    if isAircraft then
        TriggerServerEvent("PersonalVehicle:RequestAircraftLock", netId, shouldLock, coords.x, coords.y, coords.z)
    else
        TriggerServerEvent("PersonalVehicle:RequestLockToggle", netId, shouldLock, coords.x, coords.y, coords.z, suppressSound)
    end

    Wait(500)
    cooldown = false
end

-- Interior Lock Toggle

local function InteriorToggleLock()
    if cooldown then return end
    if not myOwnedNetId then return end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end

    local veh, vehType = GetOwnedVehicle()
    if not veh or (vehType ~= "car" and vehType ~= "aircraft") then return end
    if GetVehiclePedIsIn(ped, false) ~= veh then return end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId == 0 then return end

    cooldown = true

    local isAircraft = vehType == "aircraft"
    local status     = GetVehicleDoorLockStatus(veh)
    local shouldLock = status == 0 or status == 1
    local netIdStr   = tostring(netId)
    local coords     = GetEntityCoords(veh)

    if shouldLock then
        SetVehicleDoorsLocked(veh, 2)
    else
        SetVehicleDoorsLocked(veh, 1)
        if activeAlarms[netIdStr] then
            ClearAlarmLocally(veh, netIdStr)
            TriggerServerEvent("PersonalVehicle:StopAlarm", netId, coords.x, coords.y, coords.z)
        end
    end

    if Config.EnableSound then
        if isAircraft and Config.AircraftSoundsEnabled then
            SendNUIMessage({
                transactionType = "playDirectSound",
                file            = shouldLock and Config.AircraftLockSound or Config.AircraftUnlockSound,
                volume          = Config.AircraftSoundVolume,
            })
        else
            SendNUIMessage({
                transactionType = "playDirectSound",
                file            = shouldLock and Config.InteriorLockSoundLock or Config.InteriorLockSoundUnlock,
                volume          = Config.InteriorLockSoundVolume,
            })
        end
    end

    if Config.HudEnabled then
        SendNUIMessage({
            transactionType = "showLockHud",
            locked          = shouldLock,
            displayTime     = Config.HudDisplayTime,
        })
    end

    if isAircraft then
        TriggerServerEvent("PersonalVehicle:RequestAircraftLock", netId, shouldLock, coords.x, coords.y, coords.z)
    else
        TriggerServerEvent("PersonalVehicle:RequestInteriorLock", netId, shouldLock, coords.x, coords.y, coords.z)
    end

    Wait(500)
    cooldown = false
end

-- Key Bindings

RegisterKeyMapping("toggle_vehicle_lock", "Toggle Vehicle Lock", "keyboard", "e")
RegisterCommand("toggle_vehicle_lock", function()
    if IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local now = GetGameTimer()
    if now - lastPressTime <= DOUBLE_TAP then
        lastPressTime = 0
        if myOwnedNetId then ToggleLock() end
    else
        lastPressTime = now
    end
end, false)

RegisterKeyMapping("interior_vehicle_lock", "Interior Vehicle Lock", "keyboard", "g")
RegisterCommand("interior_vehicle_lock", function()
    if not IsPedInAnyVehicle(PlayerPedId(), false) then return end
    if myOwnedNetId then InteriorToggleLock() end
end, false)

-- Vehicle Registration

CreateThread(function()
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= currentVehicle then
            if veh == 0 and myOwnedNetId and DoesEntityExist(currentVehicle) then
                local prevNetId = NetworkGetNetworkIdFromEntity(currentVehicle)
                if prevNetId and tostring(prevNetId) == myOwnedNetId
                and GetVehicleDoorLockStatus(currentVehicle) >= 2 then
                    local coords   = GetEntityCoords(currentVehicle)
                    local prevType = GetVehicleType(currentVehicle)
                    local wasAircraft = prevType == "aircraft"
                    SetVehicleDoorsLocked(currentVehicle, 1)
                    if Config.EnableSound then
                        if wasAircraft and Config.AircraftSoundsEnabled then
                            SendNUIMessage({
                                transactionType = "playDirectSound",
                                file            = Config.AircraftUnlockSound,
                                volume          = Config.AircraftSoundVolume,
                            })
                        else
                            SendNUIMessage({
                                transactionType = "playDirectSound",
                                file            = Config.InteriorLockSoundUnlock,
                                volume          = Config.InteriorLockSoundVolume,
                            })
                        end
                    end
                    if wasAircraft then
                        TriggerServerEvent("PersonalVehicle:RequestAircraftLock", prevNetId, false, coords.x, coords.y, coords.z)
                    else
                        TriggerServerEvent("PersonalVehicle:RequestInteriorLock", prevNetId, false, coords.x, coords.y, coords.z)
                    end
                end
            end
            currentVehicle = veh
            if veh ~= 0 and veh ~= lastRegisteredVeh
            and GetPedInVehicleSeat(veh, -1) == ped
            and GetVehicleType(veh) then
                local netId = NetworkGetNetworkIdFromEntity(veh)
                if netId and netId ~= 0 then
                    local key = tostring(netId)
                    if not myOwnedNetId and not personalVehicles[key] then
                        dbg("Registering vehicle netId:", netId)
                        TriggerServerEvent("PersonalVehicle:Register", netId)
                        lastRegisteredVeh = veh
                    end
                end
            end
        end
    end
end)

-- Alarm Detection

CreateThread(function()
    local lastAlarmVeh  = 0
    local lastAlarmTime = 0
    while true do
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            Wait(500)
        else
            Wait(100)
            if IsPedTryingToEnterALockedVehicle(ped) then
                local targetVeh = GetVehiclePedIsTryingToEnter(ped)
                if DoesEntityExist(targetVeh) and GetVehicleType(targetVeh) == "car"
                and GetVehicleDoorLockStatus(targetVeh) >= 2 then
                    local netId = NetworkGetNetworkIdFromEntity(targetVeh)
                    if netId and netId ~= 0 then
                        local netIdStr = tostring(netId)
                        local now      = GetGameTimer()
                        if not activeAlarms[netIdStr]
                        and personalVehicles[netIdStr] ~= nil
                        and (targetVeh ~= lastAlarmVeh or now - lastAlarmTime > (Config.AlarmRetriggerDelay or 1000)) then
                            activeAlarms[netIdStr] = true
                            lastAlarmVeh  = targetVeh
                            lastAlarmTime = now

                            StartIndicatorFlash(netIdStr, targetVeh)
                            SendAlarmNUI(netIdStr, targetVeh, ped)

                            local ac = GetEntityCoords(targetVeh)
                            TriggerServerEvent("PersonalVehicle:StartAlarm", netId, ac.x, ac.y, ac.z)

                            SetTimeout(Config.AlarmDuration or 11000, function()
                                ClearAlarmLocally(DoesEntityExist(targetVeh) and targetVeh or nil, netIdStr)
                            end)
                        end
                    end
                end
            end
        end
    end
end)

-- Listener Update

CreateThread(function()
    while true do
        local hasAlarms     = next(activeAlarms)
        local recentOneShot = (GetGameTimer() - lastSoundTime) < 1500
        if hasAlarms or recentOneShot then
            local ped        = PlayerPedId()
            local pc         = GetEntityCoords(ped)
            local fwdX, fwdY = GetCamFwd()
            SendNUIMessage({
                transactionType  = "updateListener",
                playerX          = pc.x,
                playerY          = pc.y,
                fwdX             = fwdX,
                fwdY             = fwdY,
                muffled          = Config.MuffleEnabled and GetInteriorFromEntity(ped) ~= 0,
                muffleFrequency  = Config.MuffleFrequency,
                muffleTransition = Config.MuffleTransitionTime,
            })
            Wait(50)
        else
            Wait(500)
        end
    end
end)

-- Commands

RegisterCommand("setkeys", function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if not GetVehicleType(veh) then return end
    if GetPedInVehicleSeat(veh, -1) ~= ped then return end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId == 0 then return end
    TriggerServerEvent("PersonalVehicle:RequestOverride", netId)
    RequestFlash(netId, 3, 50, GetEntityCoords(veh))
    lastRegisteredVeh = veh
end, false)

-- Net Events

RegisterNetEvent("PersonalVehicle:UpdateOwnership", function(data)
    personalVehicles = data or {}
    UpdateMyOwnedNetId()
end)

RegisterNetEvent("PersonalVehicle:OwnershipOverridden", function(netIdStr, newOwner, oldOwner)
    personalVehicles[netIdStr] = newOwner
    if oldOwner == MY_SERVER_ID then myOwnedNetId = nil end
    UpdateMyOwnedNetId()
end)

RegisterNetEvent("PersonalVehicle:VehicleDespawned", function()
    myOwnedNetId      = nil
    lastRegisteredVeh = 0
end)

RegisterNetEvent("PersonalVehicle:DoFlash", function(netIdStr, count, speed, srcX, srcY, srcZ)
    local netId = tonumber(netIdStr)
    if not netId or not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(ent) then return end
    if srcX and #(GetEntityCoords(PlayerPedId()) - vector3(srcX, srcY, srcZ)) > 160 then return end
    CreateThread(function() FlashLocal(ent, count or 1, speed or 150) end)
end)

RegisterNetEvent("PersonalVehicle:ToggleLockState", function(netIdStr, shouldLock)
    local netId = tonumber(netIdStr)
    if not netId or not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(ent) then return end

    if shouldLock == nil then
        local s = GetVehicleDoorLockStatus(ent)
        shouldLock = s == 0 or s == 1
    end

    if shouldLock then
        SetVehicleDoorsLocked(ent, 2)
    else
        SetVehicleDoorsLocked(ent, 1)
        if activeAlarms[netIdStr] then
            ClearAlarmLocally(ent, netIdStr)
        end
    end
end)

RegisterNetEvent("PersonalVehicle:PlaySound", function(x, y, z, maxDist, soundFile, volume)
    if not Config.EnableSound then return end
    local ped = PlayerPedId()
    local pc  = GetEntityCoords(ped)
    if #(pc - vector3(x, y, z)) > maxDist then return end
    lastSoundTime = GetGameTimer()
    local fwdX, fwdY = GetCamFwd()
    SendNUIMessage({
        transactionType = "playSound",
        file            = soundFile,
        volume          = volume,
        maxDist         = maxDist,
        reverbEnabled   = Config.SoundReverbEnabled,
        reverbMaxWet    = Config.SoundReverbMaxWet,
        reverbStart     = Config.SoundReverbStart,
        srcX            = x,
        srcY            = y,
        playerX         = pc.x,
        playerY         = pc.y,
        fwdX            = fwdX,
        fwdY            = fwdY,
    })
end)

RegisterNetEvent("PersonalVehicle:PlayMuffledSound", function(x, y, z, maxDist, soundFile, volume, muffleFreq, srcPlayerId)
    if not Config.EnableSound then return end
    if srcPlayerId == MY_SERVER_ID then return end
    local ped = PlayerPedId()
    local pc  = GetEntityCoords(ped)
    if #(pc - vector3(x, y, z)) > maxDist then return end
    lastSoundTime = GetGameTimer()

    if IsPedInAnyVehicle(ped, false) then
        local veh     = GetVehiclePedIsIn(ped, false)
        local vehPos  = GetEntityCoords(veh)
        local srcDist = #(vehPos - vector3(x, y, z))
        local min, max  = GetModelDimensions(GetEntityModel(veh))
        local halfSize  = math.max(max.x - min.x, max.y - min.y, max.z - min.z) * 0.5
        if srcDist < halfSize + 1.0 then
            SendNUIMessage({
                transactionType = "playDirectSound",
                file            = soundFile,
                volume          = Config.InteriorLockSoundVolume,
            })
            return
        end
    end

    local fwdX, fwdY = GetCamFwd()
    SendNUIMessage({
        transactionType = "playSound",
        file            = soundFile,
        volume          = volume,
        maxDist         = maxDist,
        muffleFreq      = muffleFreq,
        reverbEnabled   = false,
        srcX            = x,
        srcY            = y,
        playerX         = pc.x,
        playerY         = pc.y,
        fwdX            = fwdX,
        fwdY            = fwdY,
    })
end)

RegisterNetEvent("PersonalVehicle:TriggerAlarm", function(netIdStr, srcX, srcY, srcZ)
    local netId = tonumber(netIdStr)
    if not netId or not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(ent) or activeAlarms[netIdStr] or GetVehicleType(ent) ~= "car" then return end
    if srcX and #(GetEntityCoords(PlayerPedId()) - vector3(srcX, srcY, srcZ)) > 55 then return end

    activeAlarms[netIdStr] = true
    StartIndicatorFlash(netIdStr, ent)
    SendAlarmNUI(netIdStr, ent, PlayerPedId())
    SetTimeout(Config.AlarmDuration or 11000, function()
        ClearAlarmLocally(DoesEntityExist(ent) and ent or nil, netIdStr)
    end)
end)

RegisterNetEvent("PersonalVehicle:CancelAlarm", function(netIdStr)
    local netId = tonumber(netIdStr)
    if not netId or not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    ClearAlarmLocally(DoesEntityExist(ent) and ent or nil, netIdStr)
end)

RegisterNetEvent("PersonalVehicle:OwnVehicleAlarmStarted", function(netIdStr)
    if Config.AlarmHudEnabled then
        SendNUIMessage({ transactionType = "showAlarmHud" })
    end

    local netId = tonumber(netIdStr)
    if netId and NetworkDoesEntityExistWithNetworkId(netId) then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(ent) and not activeAlarms[netIdStr] then
            activeAlarms[netIdStr] = true
            StartIndicatorFlash(netIdStr, ent)
        end
    end

    SetTimeout(Config.AlarmDuration or 11000, function()
        if Config.AlarmHudEnabled then
            SendNUIMessage({ transactionType = "hideAlarmHud" })
        end
    end)
end)

RegisterNetEvent("PersonalVehicle:OwnVehicleAlarmStopped", function()
    if Config.AlarmHudEnabled then
        SendNUIMessage({ transactionType = "hideAlarmHud" })
    end
end)