-- Config.lua v5.3.0

Config = {}

-- Debug
Config.DebugMode                  = false
Config.SuppressConsoleWarnings    = true

-- Lock Status HUD (top-right sliding indicator)
Config.HudEnabled                 = false
Config.HudDisplayTime             = 3000   -- ms before the HUD slides back off screen

-- Notifications (legacy GTA V pop-up, disabled by default in favour of HUD above)
Config.EnableNotifications        = false
Config.ShowVehicleName            = false

-- Sound
Config.EnableSound                = true
Config.SoundReach                 = 32      -- metres
Config.SoundVolume                = 0.1     -- 0.0 – 1.0
Config.SoundFileNameLock          = "carlock"
Config.SoundFileNameUnlock        = "carunlock"
Config.SoundReverbEnabled         = true    -- distance reverb on lock/unlock clicks
Config.SoundReverbMaxWet          = 0.2     -- 0.0 – 1.0  (reverb intensity at peak)
Config.SoundReverbStart           = 0.4     -- 0.0 – 1.0  (fraction of SoundReach where reverb begins)

-- Lock distance
Config.MaxLockDistance            = 30      -- metres

-- Motorcycle specifics
-- Motorcycles require the player to be much closer and facing the bike
Config.MotorcycleMaxLockDistance  = 1.3     -- metres (must be close)
Config.MotorcycleRequireFacing    = true
Config.MotorcycleFacingAngle      = 90      -- degrees
Config.MotorcycleAnimationDuration = 1000   -- ms
Config.MotorcycleFreezePlayer     = false
Config.MotorcycleSoundsEnabled    = false

-- Alarm
Config.AlarmDuration              = 11000       -- ms
Config.AlarmRetriggerDelay        = 1000        -- ms
Config.AlarmSoundEnabled          = true        -- play custom alarm sound (cars only, not motorcycles)
Config.AlarmSoundFile             = "caralarm"  -- OGG file in html/sounds/ (no extension)
Config.AlarmSoundVolume           = 0.05        -- 0.0 – 1.0
Config.AlarmSoundReach            = 32.0        -- metres
Config.AlarmReverbEnabled         = true        -- subtle reverb that increases with distance
Config.AlarmReverbMaxWet          = 0.35        -- 0.0 – 1.0  (reverb intensity at peak)
Config.AlarmReverbStart           = 0.4         -- 0.0 – 1.0  (fraction of AlarmSoundReach where reverb begins)

-- Occlusion / muffling (player inside a building)
Config.MuffleEnabled              = true
Config.MuffleFrequency            = 400     -- Hz  lowpass cutoff when inside (lower = more muffled)
Config.MuffleTransitionTime       = 0.03    -- seconds  smooth ramp time (Web Audio time constant)

-- Notification strings (supports GTA V colour codes)
Config.Messages = {
    VehicleLocked           = "Vehicle ~r~locked~s~.",
    VehicleLockedWithName   = "~y~%s~s~ ~r~locked~s~.",
    VehicleUnlocked         = "Vehicle ~g~unlocked~s~.",
    VehicleUnlockedWithName = "~y~%s~s~ ~g~unlocked~s~.",
}

-- Key binding default: double-tap E  (rebindable in FiveM settings → Key Bindings → FiveM)