--!strict
-- Base, on the radio. In the story Base is Ines Calder, keeping the Lamp at the bottom of the
-- Backrooms. Base checks in on a new Level, when the dark gives you back, when a level is
-- logged, the first time you reach the Night Desk, and now and then in the dark. (The camps'
-- surveyors talk for themselves: see Cutscene.)
-- Real Base asks what you see, counts with you and never says "come to me". Close to an Echo
-- that is still pretending to be one of ours, a second voice comes on calling itself Base,
-- and it does give directions: that difference is the tell, and nobody points it out.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

local FLOOR_CALL_DELAY = 4.5 -- seconds after a level starts, once its title card has faded
local BACK_CALL_DELAY = Config.World.respawnSeconds + 0.8
local DARK_CALL_SECONDS = { 180, 360 } -- Base checks in at a random interval in this range
local BACK_COOLDOWN_SECONDS = 90 -- and welcomes you back no more often than this
local FAKE_RANGE = 30 -- studs: the false Base only speaks this close to a disguised Echo
local FAKE_COOLDOWN = 40
local CHECK_HZ = 4

local Radio = {}

local deskHeard = false
local nextDarkCall = 0
local fakeReadyAt = 0
local nextFake = 1
local checkTimer = 0
local caughtCount = 0 -- catches this session
local lastBackAt = -math.huge
local unused: { [{ string }]: { string } } = {} -- per pool: the lines not yet said this session

-- Base talks only into a quiet screen (a thought, a card, a tape would be talked over), so a
-- check-in that finds it busy is simply skipped. The false Base is the exception: it is a scare.
local function say(line: string, fake: boolean?): boolean
	if not State.storyLive then
		return false -- the first minutes stay quiet: the first hidden object starts the talking
	end
	if not fake and Hud.busy() then
		return false
	end
	local speaker = if fake then Lore.radio.fakeSpeaker else Lore.radio.speaker
	if Hud.dialogue(speaker, line, not fake) then
		Audio.sequence({ 0.55, 0.62, 0.5 }, 0.035, 0.16) -- a crackle of static first
		return true
	end
	return false
end

-- A line of the pool that has not been said yet this session. A pool is shuffled and used up
-- before any line comes round again, so the same sentence is never heard twice in a row.
local function pick(pool: { string }): string
	local left = unused[pool]
	if left == nil or #left == 0 then
		left = table.clone(pool)
		unused[pool] = left
	end
	return table.remove(left, math.random(1, #left)) :: string
end

-- Welcome back after a fall. Theo's own thought covers the first one; after that Base, rarely.
local function welcomeBack()
	if caughtCount < 2 or os.clock() - lastBackAt < BACK_COOLDOWN_SECONDS then
		return
	end
	if say(pick(Lore.radio.back)) then
		lastBackAt = os.clock()
	end
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
				say(Lore.radioFor(tier))
			end
		end)
		resetDarkCall()
	end);
	(Net.get("Caught") :: RemoteEvent).OnClientEvent:Connect(
		function(_kind: string, downed: boolean)
			caughtCount += 1
			if not downed then
				task.delay(BACK_CALL_DELAY, welcomeBack)
			end
		end
	);
	(Net.get("Revived") :: RemoteEvent).OnClientEvent:Connect(welcomeBack);
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
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Radio
