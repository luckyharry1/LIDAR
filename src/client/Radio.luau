--!strict
-- Base, on the radio. In the story Base is Ines Calder, keeping the lamp at the bottom of the
-- building; the player only ever hears her report and count. Base checks in on a new floor,
-- when the dark gives you back, when a level is logged, the first time you reach the Night
-- Desk (and, briefly, in each small haven), and now and then in the dark.
-- Real Base reports. Real Base counts. Real Base never gives directions. Close to an Echo
-- that is still pretending to be one of ours, a second voice comes on calling itself Base,
-- and it does give directions: that difference is the tell, and nobody points it out.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Difficulty = require(ReplicatedStorage.Shared.pure.Difficulty)
local Hud = require(script.Parent.Hud)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

local FLOOR_CALL_DELAY = 4.5 -- seconds after a level starts, once its title card has faded
local BACK_CALL_DELAY = Config.World.respawnSeconds + 0.8
local DARK_CALL_SECONDS = { 110, 220 } -- Base checks in at a random interval in this range
local FAKE_RANGE = 30 -- studs: the false Base only speaks this close to a disguised Echo
local FAKE_COOLDOWN = 40
local CHECK_HZ = 4

local Radio = {}

local deskHeard = false
local havensHeard: { [string]: boolean } = {} -- each small haven gets one call, the first visit
local nextDarkCall = 0
local fakeReadyAt = 0
local nextFake = 1
local checkTimer = 0

local function say(line: string, fake: boolean?)
	Audio.sequence({ 0.55, 0.62, 0.5 }, 0.035, 0.16) -- a crackle of static first
	Hud.dialogue(if fake then Lore.radio.fakeSpeaker else Lore.radio.speaker, line)
end

local function pick(lines: { string }): string
	return lines[math.random(1, #lines)]
end

-- "B3" on the authored floors, "R2" on the second Relay floor.
local function floorName(tier: number): string
	local section = Lore.sectionFor(tier)
	if section ~= nil then
		return section.floor
	end
	return "R" .. math.max(1, tier - Difficulty.authoredCount)
end

local function resetDarkCall()
	local range = DARK_CALL_SECONDS
	nextDarkCall = os.clock() + range[1] + math.random() * (range[2] - range[1])
end

-- The Echo's false Base: only while one is disguised and close.
local function disguisedEchoNear(eye: Vector3): boolean
	for _, model in CollectionService:GetTagged(Config.Tags.disguised) do
		if model:IsA("Model") and model.PrimaryPart ~= nil then
			if (model.PrimaryPart.Position - eye).Magnitude <= FAKE_RANGE then
				return true
			end
		end
	end
	return false
end

local function update(dt: number)
	checkTimer -= dt
	if checkTimer > 0 then
		return
	end
	checkTimer = 1 / CHECK_HZ
	local camera = workspace.CurrentCamera
	if camera == nil or State.server.stage ~= "level" or Atmosphere.zone() ~= nil then
		return
	end
	local now = os.clock()
	if now >= fakeReadyAt and disguisedEchoNear(camera.CFrame.Position) then
		fakeReadyAt = now + FAKE_COOLDOWN
		say(Lore.radio.fake[nextFake], true)
		nextFake = nextFake % #Lore.radio.fake + 1
		resetDarkCall() -- never let the real Base answer straight after the false one
		return
	end
	if now >= nextDarkCall then
		resetDarkCall()
		say(pick(Lore.radio.dark))
	end
end

function Radio.start()
	resetDarkCall()
	State.onLevel(function()
		local server = State.server
		if server.seed == 0 then
			return
		end
		local tier = server.tier
		task.delay(FLOOR_CALL_DELAY, function()
			if State.server.tier == tier and State.server.stage == "level" then
				say(Lore.fill(Lore.radio.floor, { floor = floorName(tier) }))
			end
		end)
		resetDarkCall()
	end);
	(Net.get("Caught") :: RemoteEvent).OnClientEvent:Connect(
		function(_kind: string, downed: boolean)
			if not downed then
				task.delay(BACK_CALL_DELAY, function()
					say(pick(Lore.radio.back))
				end)
			end
		end
	);
	(Net.get("Revived") :: RemoteEvent).OnClientEvent:Connect(function()
		say(pick(Lore.radio.back))
	end);
	(Net.get("LevelCleared") :: RemoteEvent).OnClientEvent:Connect(function()
		say(Lore.radio.cleared)
	end)
	Atmosphere.onZone(function(zone)
		if zone == nil or State.server.stage ~= "lore" then
			return
		end
		local roomId = State.server.loreRoom
		if roomId == "office" and not deskHeard then
			deskHeard = true
			say(Lore.radio.desk)
		elseif Lore.rooms[roomId] ~= nil and Lore.rooms[roomId].size == "haven" then
			if not havensHeard[roomId] then
				havensHeard[roomId] = true
				say(Lore.radio.haven)
			end
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Radio
