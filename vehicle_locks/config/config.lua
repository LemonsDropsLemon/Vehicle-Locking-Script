-- Config.lua v5.4.0

Config = {}

-- Debug

Config.DebugMode               = false
Config.SuppressConsoleWarnings = true

-- HUD

Config.HudEnabled     = true
Config.HudDisplayTime = 2200

-- Alarm HUD

Config.AlarmHudEnabled = true

-- Notifications

Config.EnableNotifications = false
Config.ShowVehicleName     = false

-- Interior Lock

Config.InteriorLockSoundLock     = "doorlock"
Config.InteriorLockSoundUnlock   = "doorunlock"
Config.InteriorLockSoundVolume   = 0.48
Config.InteriorLockOutsideReach  = 6
Config.InteriorLockOutsideVolume = 0.22
Config.InteriorLockMuffleFreq    = 350

-- Cars

Config.EnableSound         = true
Config.SoundReach          = 32
Config.SoundVolume         = 0.1
Config.SoundFileNameLock   = "carlock"
Config.SoundFileNameUnlock = "carunlock"
Config.SoundReverbEnabled  = true
Config.SoundReverbMaxWet   = 0.2
Config.SoundReverbStart    = 0.4
Config.MaxLockDistance     = 30

-- Motorcycle

Config.MotorcycleRequireFacing     = true
Config.MotorcycleFacingAngle       = 90
Config.MotorcycleAnimationDuration = 1000
Config.MotorcycleFreezePlayer      = false
Config.MotorcycleSoundsEnabled     = false
Config.MotorcycleMaxLockDistance   = 1.3

-- Bicycle

Config.BicycleRequireFacing     = true
Config.BicycleFacingAngle       = 30
Config.BicycleAnimationDuration = 1000
Config.BicycleFreezePlayer      = false
Config.BicycleSoundsEnabled     = true
Config.BicycleSoundVolume       = 0.24
Config.BicycleLockSound         = "chainlock"
Config.BicycleUnlockSound       = "chainunlock"
Config.BicycleMaxLockDistance   = 1.3

-- Aircraft

Config.AircraftRequireFacing     = true
Config.AircraftFacingAngle       = 50
Config.AircraftAnimationDuration = 800
Config.AircraftFreezePlayer      = false
Config.AircraftSoundsEnabled     = true
Config.AircraftLockSound         = "doorlock"
Config.AircraftUnlockSound       = "doorunlock"
Config.AircraftSoundVolume       = 0.48
Config.AircraftSoundReach        = 6.0
Config.AircraftOutsideVolume     = 0.22
Config.AircraftSoundMuffleFreq   = 350
Config.AircraftMaxLockDistance   = 3.4

-- Alarm

Config.AlarmDuration       = 11000
Config.AlarmRetriggerDelay = 1000
Config.AlarmSoundEnabled   = true
Config.AlarmSoundFile      = "caralarm"
Config.AlarmSoundVolume    = 0.05
Config.AlarmSoundReach     = 32.0
Config.AlarmReverbEnabled  = true
Config.AlarmReverbMaxWet   = 0.35
Config.AlarmReverbStart    = 0.4

-- Occlusion

Config.MuffleEnabled        = true
Config.MuffleFrequency      = 400
Config.MuffleTransitionTime = 0.03

-- Messages

Config.Messages = {
    VehicleLocked           = "Vehicle ~r~locked~s~.",
    VehicleLockedWithName   = "~y~%s~s~ ~r~locked~s~.",
    VehicleUnlocked         = "Vehicle ~g~unlocked~s~.",
    VehicleUnlockedWithName = "~y~%s~s~ ~g~unlocked~s~.",
}

-- Key Bindings
-- Exterior lock: double-tap E
-- Interior lock: G