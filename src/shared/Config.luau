--!strict
-- Every scalar tunable lives here. Pure data only (no Roblox globals) so Lune tests can load it.
-- Content tables (tiers, enemies, upgrades, lore) live in src/shared/data.

local Config = {}

Config.SaveVersion = 2

-- The LIDAR gun. Left click scatters a stream of tiny, permanent dots inside a cone; right
-- click fires one loud top-to-bottom sweep that draws a whole grid at once. The scatter is
-- free but starts weak; the sweep costs a battery charge (Config.Battery). Bench upgrades
-- (data/Upgrades, Progression.effects) raise the base numbers below towards their caps.
Config.Lidar = {
	dotsPerSecond = 260, -- base scatter rate; the Emitter upgrade adds emitterDotsPerLevel
	emitterDotsPerLevel = 120, -- five levels: 260 up to 860
	coneHalfAngleDeg = 26, -- default spread
	coneMinDeg = 8, -- the scroll wheel narrows the spread down to this
	coneMaxDeg = 34, -- and widens it up to this
	coneMaxWideDeg = 56, -- with the Wide Lens upgrade
	coneStepDeg = 4,
	baseRange = 65, -- studs the scatter and sweep reach before upgrades
	rangePerLevel = 21, -- the Range Coil upgrade adds this per level (four levels: 149)
	maxRange = 150, -- studs; the hard cap, also what the server allows for pings and reveals

	-- How many permanent dots the world can hold, by the quality setting. When the budget is
	-- full the oldest dot is reused, so the live count can never exceed it.
	dotBudget = { low = 14000, medium = 42000, high = 85000 },
	budgetPerPhosphorLevel = 0.25, -- the Phosphor upgrade adds this share per level (four: x2)
	fadingDots = 1600, -- separate small pool for dots that fade (people, monsters, footprints)

	dotSize = 0.01, -- studs at close range
	-- Extra size per stud of distance. A dot must keep at least about 1.5 px on screen at any
	-- range (size / distance, roughly 0.002 at 1080p and a 70 degree view), or the far dots
	-- straight down a corridor, which is where the crosshair points, drop out while the near
	-- walls at the screen edges still show.
	dotSizeDistanceScale = 0.002,
	-- The cap must sit beyond maxRange: at 0.2 it bit at 95 studs, so the farthest dots (straight
	-- down a long corridor, round the crosshair) shrank back to about one pixel.
	dotSizeMax = 0.32,
	itemDotScale = 0.5, -- items and objects are drawn with finer dots
	markDotScale = 1.6, -- people, monsters and footprints are a little larger

	-- Dots are not stacked: one per grid cell, with the grid chosen by how far away the
	-- surface was when it was scanned (close surfaces get fine detail).
	-- On screen a grid step is about step / distance * 770 px at 1080p. With a 0.8 far grid the
	-- band just past the mid range (45 to 80 studs: the middle of the view down a corridor)
	-- could never hold dots closer than 8 to 14 px apart, so it stayed sparse however long it
	-- was scanned. These keep every range at or under about 9 px.
	gridNear = 0.15,
	gridMid = 0.3,
	gridFar = 0.45,
	gridNearRange = 14, -- studs within which the near grid is used
	gridMidRange = 40,
	gridItem = 0.08,

	friendLifetime = 2.5, -- seconds; people fade fast, the world stays
	enemyLifetime = 1.2,
	enemyDotChance = 0.3, -- share of rays that mark a monster: glimpses, not silhouettes
	fadeExponent = 2.2, -- transparency = age ^ exponent
	fadeStagger = 3, -- each fading dot is refreshed every N frames
	mimicDotDelay = 0.35, -- the Mimic's tell: its dots land late

	-- Lines in one sweep and rays per line, by Sweep Grid upgrade level (0 to 3).
	sweepRowsByLevel = { 44, 60, 76, 90 },
	sweepColumnsByLevel = { 56, 76, 96, 114 },
	sweepSeconds = 1.3, -- time from the top line to the bottom line
	sweepUpDeg = 30,
	sweepDownDeg = 36,
	sweepHalfWidthDeg = 46,

	radarSeconds = { 8, 5 }, -- Pulse Radar interval by upgrade level
	radarRays = 240,
	radarPitchDeg = 16, -- the pulse fans this far above and below level

	beamCount = 26, -- laser lines from the muzzle to fresh dots
	beamTransparency = 0.5,
	beamSeconds = 0.06,
	teammateBeams = 12,
	teammateShare = 0.6, -- teammates' scanners are redrawn locally at this share of the rate
	scanStateHz = 8, -- how often the client reports its scan state to the server
	echoRevealHits = 140, -- dots that must land on a hidden object before it reveals itself
	lightRevealHits = 10, -- dots a lamp, beacon or patch needs to wake: a short scan finds a light
	lightReach = 9, -- studs: a dot this close to a lamp or beacon counts as a hit on it
	concealTrigger = 7, -- studs: a dot this close to a hidden lamp-bag patch brings it back
}

-- Battery cells. The sweep is the strong scan and every one costs a charge in a level; the
-- scatter stays free so nobody is ever fully blind. Cells are hidden in each level (most in
-- dead ends) and give 1 or 2 charges. Charges carry from level to level within a run.
-- Sweeps in the tutorial and in havens are free.
Config.Battery = {
	startCharges = 1, -- charges at the start of a run
	baseCapacity = 3, -- most charges the gun holds; the Capacitor upgrade adds one per level
	doubleChance = 0.3, -- share of cells that give 2 charges instead of 1
	overflowStatic = 6, -- a charge that does not fit is paid out as Static instead
	trickleSeconds = { 150, 110, 80 }, -- Trickle Charger: one charge back every N s in a level
}

-- Footprints and breath: how monsters and teammates give themselves away.
Config.Tracks = {
	stride = 2.4, -- studs between prints
	lifetime = 12, -- seconds a print lasts
	range = 75, -- prints farther than this from the camera are not drawn
	mistRange = 34, -- a monster this close breathes visible mist
	mistInterval = 0.35,
	auraRange = 46, -- the red edge-of-screen aura starts at this distance
}

-- Dot palettes as RGB triples. `alt` is the colourblind-safe set (blue friends, orange monsters).
Config.Palettes = {
	default = {
		wall = { 196, 200, 210 },
		floor = { 190, 160, 96 },
		ceiling = { 104, 122, 156 },
		water = { 50, 130, 255 },
		friend = { 70, 235, 120 },
		enemy = { 255, 50, 50 },
		objective = { 255, 205, 80 },
		hazard = { 200, 90, 255 },
	},
	alt = {
		wall = { 196, 200, 210 },
		floor = { 190, 160, 96 },
		ceiling = { 104, 122, 156 },
		water = { 150, 110, 255 },
		friend = { 70, 150, 255 },
		enemy = { 255, 150, 20 },
		objective = { 255, 240, 140 },
		hazard = { 200, 90, 255 },
	},
}

Config.Tags = {
	friend = "Lidar_Friend",
	enemy = "Lidar_Enemy",
	objective = "Lidar_Objective",
	litZone = "Lidar_LitZone",
	disguised = "Lidar_Disguised",
	rescue = "Lidar_Rescue",
	anomaly = "Lidar_Anomaly",
	echo = "Lidar_Echo",
	water = "Lidar_Water",
	hazard = "Lidar_Hazard", -- pit rims and alarm plates
	sound = "Lidar_Sound", -- server-made sounds the client routes through its volume setting
	light = "Lidar_Light", -- every server-made light, so clients find them without a scan
	concealed = "Lidar_Concealed", -- built dark; each client shows it once its scan lands near
}

Config.World = {
	cellSize = 14, -- studs per maze cell
	wallHeight = 11,
	wallThickness = 1,
	loreOrigin = { 0, 0, -900 },
	tutorialOrigin = { 1200, 0, 0 }, -- each player's tutorial room is offset from here
	tutorialSpacing = 120,
	transitionSeconds = 3,
	respawnSeconds = 2.2,
	respawnGraceSeconds = 5, -- enemies ignore a freshly respawned player
	promptDistance = 9,
	pitSize = 6, -- studs across; leaves a ledge to walk round on every side
	pitDepth = 16,
	pitFallDepth = 7, -- falling this far below the floor counts as falling in
	plateRadius = 2.4, -- stepping this close to an alarm plate sets it off
	plateRearmSeconds = 12,
	lampRange = 11, -- studs lit by a lantern: about one cell
	echoLightRange = 11,
	pitNoise = 3, -- cells; someone falling into a pit is heard this far
	pitNoiseSeconds = 2,
}

Config.Player = {
	walkSpeed = 10,
	sprintSpeed = 17,
	crouchSpeed = 5,
	litWalkSpeed = 14,
	jumpPower = 0, -- jumping is disabled in the maze
	crouchCameraDrop = 1.7, -- studs the view lowers while crouched
	cameraBobAmplitude = 0.06,
	cameraBobFrequency = 7,
}

-- Noise radii, in maze cells, heard by enemies. Scattering dots and crouching are quiet, not silent; the sweep is the loud one.
Config.Noise = {
	walk = 0.5,
	sprint = 3,
	sweep = 4,
	crouch = 0.22, -- a crouched walk is quiet, not silent: nothing can be crept past for free
	scatter = 0.3, -- so is the scatter stream (the sweep is the loud one)
	wade = 0.5, -- moving through water is heard this far even crouched
	ping = 3, -- a ping marker is also a decoy sound
	pingSeconds = 2.5, -- how long the decoy keeps sounding
	plate = 5, -- an alarm plate is very loud
	plateSeconds = 3,
	softSolesFactor = 0.7, -- per upgrade level, multiplies movement noise
	quietShutterFactor = 0.82, -- per upgrade level, multiplies sweep noise
	floodedFactor = 1.6, -- wading is loud
	sprintSpeedThreshold = 13, -- studs/s above which movement counts as sprinting
	walkSpeedThreshold = 2,
	crouchSpeedLimit = 7, -- a client claiming to crouch must be moving no faster than this
}

-- Shared enemy behaviour. Per-enemy numbers are in data/Enemies.
Config.Enemy = {
	sleepCells = 12, -- enemies farther than this from every player do not think or move
	thinkInterval = 0.25, -- seconds between sensing and repathing
	startSafeCells = 1, -- roaming never ends within this many cells of the level start
	stalkerConeDot = 0.8, -- how directly a scan must point at a Stalker to pin it
	stalkerStareSeconds = 2.5, -- pin a Stalker this long and it withdraws to its post
	stalkerStareDecay = 0.5, -- how fast that progress drains while it is not pinned
	stalkerWithdrawSpeed = 1.5, -- multiplier on its speed while it withdraws
	stalkerCooldown = 18, -- seconds it stays dormant after withdrawing
	spawnSpacingCells = 3, -- enemies start at least this many path cells apart when possible
	spawnClearCells = 2.5, -- and at least this far from the level start in a straight line
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
	markerDistance = 400, -- teammates' name markers show through walls up to this far
}

Config.Economy = {
	cellBonus = 5, -- Static per battery cell collected (there are 3 to 4 a level now)
	rescueBonus = 30,
	cleanClearMultiplier = 1.3, -- bonus for clearing without being caught
	loreNoteBonus = 8,
	echoBonus = 10, -- for revealing a hidden object
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
	bloomDots = 1400,
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
		Reveal = 2,
		BuyUpgrade = 4,
		EquipCosmetic = 4,
		SetSetting = 6,
		Start = 2,
		Funnel = 4,
		ToggleUpgrade = 6,
		Choose = 2,
		Descend = 2,
		PartyReady = 4,
		PartyStart = 2,
	},
}

Config.Telemetry = {
	enabled = true,
}

-- Sounds. The short interface clips ship inside the Roblox client. The atmosphere and monster
-- sounds are from Roblox's licensed libraries (Pro Sound Effects, APM): see docs/ASSETS.md.
-- Set any id to "" to silence it.
Config.Audio = {
	tick = "rbxasset://sounds/volume_slider.ogg",
	thud = "rbxasset://sounds/action_jump_land.mp3",
	air = "rbxasset://sounds/action_falling.ogg",
	wade = "rbxasset://sounds/action_swim.mp3",
	rumble = "rbxasset://sounds/impact_explosion_03.mp3",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	ambience = "rbxassetid://9125970426", -- low engine-room rumble with sporadic distant noises
	drips = "rbxassetid://9112773041", -- water drips, creaks and distant metal
	presence = "rbxassetid://9113586520", -- slow airy breathing, rises when something is near
	heartbeat = "rbxassetid://9043365842",
	bumps = "rbxassetid://9113136235", -- far-off bumps and creaks, played from random directions
	wandererVoice = "rbxassetid://9112863181", -- rumbling breath
	wandererStep = "rbxassetid://9114166413", -- one heavy footstep
	listenerVoice = "rbxassetid://9119531802", -- ratchety clicks
	stalkerVoice = "rbxassetid://9126147232", -- bending metal whine, only while it moves
	caughtRoar = "rbxassetid://9113980319",
	door = "rbxassetid://9114434781",
	waterfall = "rbxassetid://9120552550",
	masterVolume = 1,
	tickInterval = 0.05, -- seconds between scan ticks
	tickVolume = 0.07,
	ambienceVolume = 0.32,
	dripsVolume = 0.22,
	presenceVolume = 0.9,
	heartbeatDistance = 60, -- studs at which the heartbeat begins
	heartbeatVolume = 0.8,
	bumpSeconds = { 14, 34 }, -- a distant bump plays at a random interval in this range
	stingDistance = 26, -- a monster arriving this close triggers a sting
	stingRearmSeconds = 14,
}

-- Monetisation placeholders. Zero means "not configured"; the game runs fine without them.
-- The plan for what could be sold, and what never should be, is in docs/MONETIZATION.md.
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
