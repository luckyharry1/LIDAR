--!strict
-- What this client knows: the latest state and profile the server sent, plus the level plan
-- rebuilt locally from (tier, seed). Other controllers read from here and subscribe to changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelPlan = require(ReplicatedStorage.Shared.pure.LevelPlan)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.pure.Progression)
local SaveData = require(ReplicatedStorage.Shared.pure.SaveData)

export type Session = {
	static: number,
	levels: number,
	catches: number,
	lore: number,
	distance: number,
}
export type ServerState = {
	stage: string,
	phase: string,
	mode: string,
	tier: number,
	tierName: string,
	seed: number,
	epoch: number,
	origin: Vector3,
	sweepScale: number, -- above 1 the sweep recharges more slowly on this level
	forcedAnomaly: string,
	allowPlate: boolean,
	locked: boolean,
	hasKey: boolean,
	gateName: string, -- what opens a locked exit on this level ("" when nothing does)
	cells: number,
	cellsTotal: number,
	rescues: number,
	rescuesTotal: number,
	echoes: number, -- hidden objects revealed on this level
	echoesTotal: number,
	loreRoom: string,
	partySize: number,
	checkpointTier: number,
	dailyDay: number,
	dailyDone: boolean,
	runActive: boolean,
	session: Session,
}
export type Meta = {
	persistent: boolean,
	kitPassId: number,
	ownsKit: boolean,
	canPromptPurchase: boolean,
}

local State = {}

State.server = {
	stage = "title",
	phase = "idle",
	mode = "run",
	tier = 1,
	tierName = "",
	seed = 0,
	epoch = 0,
	origin = Vector3.zero,
	sweepScale = 1,
	forcedAnomaly = "",
	allowPlate = false,
	locked = false,
	hasKey = false,
	gateName = "",
	cells = 0,
	cellsTotal = 0,
	rescues = 0,
	rescuesTotal = 0,
	echoes = 0,
	echoesTotal = 0,
	loreRoom = "",
	partySize = 1,
	checkpointTier = 1,
	dailyDay = 0,
	dailyDone = false,
	runActive = false,
	session = { static = 0, levels = 0, catches = 0, lore = 0, distance = 0 },
} :: ServerState

State.profile = SaveData.default()
State.effects = Progression.effects(State.profile)
State.meta =
	{ persistent = true, kitPassId = 0, ownsKit = false, canPromptPurchase = false } :: Meta
State.profileLoaded = false
State.plan = nil :: LevelPlan.LevelPlan?
State.menuOpen = false -- true while a full-screen menu has the player's attention
State.exitScanned = false -- has the LIDAR touched this level's exit yet (drives the Wayfinder)
State.scannedCells = {} :: { [number]: boolean }

local stateListeners: { (ServerState, ServerState) -> () } = {}
local profileListeners: { () -> () } = {}
local levelListeners: { () -> () } = {}

-- Called with (new, previous) whenever the server sends a state.
function State.onState(listener: (ServerState, ServerState) -> ())
	table.insert(stateListeners, listener)
end

function State.onProfile(listener: () -> ())
	table.insert(profileListeners, listener)
end

-- Called when the player arrives in a different level (new tier or seed).
function State.onLevel(listener: () -> ())
	table.insert(levelListeners, listener)
end

function State.inLevel(): boolean
	return State.server.stage == "level" or State.server.stage == "downed"
end

-- Connects to the server. Call this last, after every controller has subscribed, so the
-- first state and profile (which may already be queued) reach all of them.
function State.connect()
	(Net.get("State") :: RemoteEvent).OnClientEvent:Connect(function(incoming: ServerState)
		local previous = State.server
		State.server = incoming
		-- The epoch catches a restart that lands on the same tier and seed (the daily level, a
		-- haven left for the title): without it the old dots and marks would stay on screen.
		local levelChanged = incoming.seed ~= previous.seed
			or incoming.tier ~= previous.tier
			or incoming.epoch ~= previous.epoch
		if levelChanged then
			State.exitScanned = false
			State.scannedCells = {}
			State.plan = if incoming.seed ~= 0
				then LevelPlan.build(incoming.tier, incoming.seed, {
					forcedAnomaly = if incoming.forcedAnomaly ~= ""
						then incoming.forcedAnomaly
						else nil,
					allowPlate = incoming.allowPlate,
				})
				else nil
		end
		for _, listener in stateListeners do
			task.spawn(listener, incoming, previous)
		end
		if levelChanged then
			for _, listener in levelListeners do
				task.spawn(listener)
			end
		end
	end);
	(Net.get("Profile") :: RemoteEvent).OnClientEvent:Connect(
		function(profile: SaveData.Profile, effects: Progression.Effects, meta: Meta)
			State.profile = profile
			State.effects = effects
			State.meta = meta
			State.profileLoaded = true
			for _, listener in profileListeners do
				task.spawn(listener)
			end
		end
	)
end

return State
