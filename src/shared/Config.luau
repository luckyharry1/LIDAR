--!strict
-- Every scalar tunable lives here. Pure data only (no Roblox globals) so Lune tests can load it.
-- Content tables (tiers, enemies, upgrades, lore) live in src/shared/data.

local Config = {}

Config.SaveVersion = 2

-- The LIDAR gun. These ten values shape the feel more than anything else.
Config.Lidar = {
	dotsPerSecond = 55, -- wide sweep drip rate
	focusDotsPerSecond = 160, -- hold-to-focus rate
	coneHalfAngleDeg = 17, -- wide sweep cone
	focusConeHalfAngleDeg = 4.5, -- focused cone
	maxRange = 110, -- studs
	maxLiveDots = 3000, -- hard cap; oldest dot is recycled
	dotSize = 0.11, -- studs at close range
	dotSizeDistanceScale = 0.0055, -- extra size per stud of distance so far dots stay readable
	dotSizeMax = 0.6,
	specialDotScale = 1.7, -- friend and enemy dots are larger
	terrainLifetime = 16, -- seconds
	friendLifetime = 9,
	enemyLifetime = 3.2, -- enemies fade fast so they feel elusive
	fadeExponent = 2.2, -- transparency = age ^ exponent
	fadeStagger = 4, -- each dot's fade is refreshed every N frames
	heatPerSecondFocus = 0.3, -- focus fills the heat meter in ~3.3 s
	coolPerSecond = 0.22,
	overheatLockSeconds = 2.2,
	mimicDotDelay = 0.35, -- the Mimic's tell: its dots land late
	beamCount = 5, -- faint scan lines from the muzzle
	beamTransparency = 0.7,
	sharedScanRate = 0.35, -- share of a teammate's dots drawn when shared scans are on
	scanStateHz = 8, -- how often the client reports its scan state to the server
}

-- Dot palettes as RGB triples. `alt` is the colourblind-safe white/blue/orange set.
Config.Palettes = {
	default = {
		terrain = { 235, 240, 255 },
		friend = { 70, 255, 120 },
		enemy = { 255, 45, 45 },
		objective = { 255, 215, 90 },
	},
	alt = {
		terrain = { 235, 240, 255 },
		friend = { 70, 150, 255 },
		enemy = { 255, 150, 20 },
		objective = { 255, 240, 140 },
	},
}

Config.Tags = {
	terrain = "Lidar_Terrain",
	friend = "Lidar_Friend",
	enemy = "Lidar_Enemy",
	objective = "Lidar_Objective",
	litZone = "Lidar_LitZone",
	disguised = "Lidar_Disguised",
	rescue = "Lidar_Rescue",
	anomaly = "Lidar_Anomaly",
}

Config.World = {
	cellSize = 14, -- studs per maze cell
	wallHeight = 11,
	wallThickness = 1,
	levelOrigin = { 0, 0, 0 },
	loreOrigin = { 0, 0, -900 },
	tutorialOrigin = { 1200, 0, 0 }, -- each player's tutorial room is offset from here
	tutorialSpacing = 120,
	transitionSeconds = 3,
	respawnSeconds = 2.2,
	respawnGraceSeconds = 5, -- enemies ignore a freshly respawned player
	promptDistance = 9,
}

Config.Player = {
	walkSpeed = 10,
	sprintSpeed = 17,
	litWalkSpeed = 14,
	jumpPower = 0, -- jumping is disabled in the maze
	cameraBobAmplitude = 0.06,
	cameraBobFrequency = 7,
}

-- Noise radii, in maze cells, heard by enemies.
Config.Noise = {
	walk = 0.5,
	sprint = 3,
	scan = 1,
	focus = 2.4,
	ping = 3, -- a ping marker is also a decoy sound
	pingSeconds = 2.5, -- how long the decoy keeps sounding
	softSolesFactor = 0.7, -- per upgrade level, multiplies movement noise
	floodedFactor = 1.6, -- wading is loud
	sprintSpeedThreshold = 13, -- studs/s above which movement counts as sprinting
	walkSpeedThreshold = 2,
}

-- Shared enemy behaviour. Per-enemy numbers are in data/Enemies.
Config.Enemy = {
	sleepCells = 12, -- enemies farther than this from every player do not think or move
	thinkInterval = 0.25, -- seconds between sensing and repathing
	patrolRadius = 4, -- how far, in cells, a patrol wanders from its post
	startSafeCells = 1, -- patrols never idle within this many cells of the level start
	stalkerConeDot = 0.8, -- how directly a scan must point at a Stalker to pin it
	stalkerStareSeconds = 3, -- pin a Stalker this long and it withdraws to its post
	stalkerFocusRate = 3, -- a focused beam pins this many times faster
	spawnSpacingCells = 3, -- enemies start at least this many path cells apart when possible
	spawnClearCells = 2.5, -- and at least this far from the level start in a straight line
	stalkerStareDecay = 0.5, -- how fast that progress drains while it is not pinned
	stalkerWithdrawSpeed = 1.5, -- multiplier on its speed while it withdraws
	stalkerCooldown = 18, -- seconds it stays dormant after withdrawing
	mimicRevealDelay = 0.8, -- seconds between a Mimic turning red and starting to chase
	mimicCooldown = 12,
	stunSeconds = 4, -- after catching someone in co-op an enemy pauses, so it cannot camp
	tickHz = 15,
}

Config.Coop = {
	maxPlayers = 4,
	reviveSeconds = 3,
	reviveDistance = 10,
	reviveConeDot = 0.8, -- how directly you must scan a downed friend
	pingLifetime = 12,
	pingCooldown = 1.5,
	emoteCooldown = 1,
	emotes = { "Here", "Wait", "Go", "Danger", "Thanks" },
}

Config.Economy = {
	cellBonus = 12, -- Static per battery cell collected
	rescueBonus = 30,
	keyVaultBonus = 25,
	cleanClearMultiplier = 1.3, -- bonus for clearing without being caught
	loreNoteBonus = 8,
	rareLoreBonus = 40,
	dailyClearBonus = 50,
	streakBonuses = { 10, 15, 20, 25, 30, 40, 60 }, -- cycles every seven visits
}

Config.Daily = {
	tier = 4,
	boardSize = 10,
	storePrefix = "LidarDaily_",
}

Config.Anomaly = {
	chancePerLevel = 0.1,
	minTier = 2,
	rareLoreChance = 0.12,
	bloomDots = 700,
	bloomSeconds = 5,
}

Config.Save = {
	storeName = "LidarSave",
	lockSeconds = 600, -- a session lock older than this is treated as stale
	loadRetries = 4,
	retryBaseSeconds = 2,
	autosaveSeconds = 180,
}

Config.Net = {
	-- Maximum accepted calls per second for each client-to-server remote.
	rateLimits = {
		ScanState = 14,
		Ping = 1,
		Emote = 2,
		BuyUpgrade = 4,
		EquipCosmetic = 4,
		SetSetting = 6,
		Start = 2,
		Funnel = 4,
		ToggleUpgrade = 6,
	},
}

Config.Telemetry = {
	enabled = true,
}

-- Sounds. Defaults are clips that ship inside the Roblox client, so no uploaded assets are needed.
Config.Audio = {
	tick = "rbxasset://sounds/volume_slider.ogg",
	thud = "rbxasset://sounds/action_jump_land.mp3",
	air = "rbxasset://sounds/action_falling.ogg",
	steps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	water = "rbxasset://sounds/impact_water.mp3",
	wade = "rbxasset://sounds/action_swim.mp3",
	rumble = "rbxasset://sounds/impact_explosion_03.mp3",
	masterVolume = 1,
	tickInterval = 0.07, -- seconds between scan ticks
	tickVolume = 0.16,
	droneVolume = 0.2,
	heartbeatDistance = 70, -- studs at which the heartbeat begins
	heartbeatVolume = 0.55,
}

-- Monetisation placeholders. Zero means "not configured"; the game runs fine without them.
Config.Monetization = {
	surveyorKitPassId = 0, -- convenience pass: a mid-level checkpoint beacon
	cosmeticPackProductId = 0,
	promptAfterLevels = 2, -- never prompt a purchase before this many levels are cleared
}

-- Place IDs for the reserved-server flow. Zero keeps everything in a single place.
Config.Places = {
	runPlaceId = 0,
}

return Config
