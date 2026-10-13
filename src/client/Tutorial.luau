--!strict
-- Teaching by doing. One short hint at a time, shown only when it is relevant, worded for
-- the device in the player's hands. The intake room walks a new player through scan, focus
-- and the door; after that, hints appear once each as new things are met.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Avatar = require(script.Parent.Avatar)
local Dots = require(script.Parent.Dots)
local Hud = require(script.Parent.Hud)
local Input = require(script.Parent.Input)
local Lidar = require(script.Parent.Lidar)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

local FIRST_SCAN_DOTS = 50
local FOCUS_HINT_SECONDS = 9
local HINT_SECONDS = 7
local SPRINT_HINT_AFTER = 35 -- seconds into the first level

-- Shown the first time a player reaches the tier that introduces something new.
local TIER_HINTS: { [number]: string } = {
	[1] = "Find the exit. You are not alone in here: red means stay away.",
	[3] = "Something here hunts by sound. Running and long scans call it.",
	[4] = "Flooded floor on this level. Wading is loud. The exit is locked: find the key.",
	[5] = "Not everything green is one of ours. Real surveyors tap on the wall.",
	[6] = "Something tall only moves while no scanner points at it.",
}

local Tutorial = {}

local step = "idle" -- intake room progress: idle, scan, focus, find, door, done
local stepStarted = 0
local dotsAtStart = 0
local shown: { [string]: boolean } = {}
local timedHintUntil = 0
local levelStartedAt = 0

local function setStep(name: string)
	step = name
	stepStarted = os.clock()
	if name == "scan" then
		dotsAtStart = Dots.spawned
		Hud.hint("It is dark. " .. Input.hint("fire") .. " to scan.")
	elseif name == "focus" then
		Hud.hint(
			"Dots show what is there. "
				.. Input.hint("focus")
				.. " to narrow the beam. It runs hot."
		)
	elseif name == "find" then
		Hud.hint("Sweep the room. Find the door.")
	elseif name == "door" then
		Hud.hint(
			"Gold is the way out. Walk to it and " .. string.lower(Input.hint("interact")) .. "."
		)
	else
		Hud.hint(nil)
	end
end

-- A hint that shows once per session and clears itself.
local function once(key: string, text: string)
	if shown[key] or step ~= "done" and step ~= "idle" then
		return
	end
	shown[key] = true
	timedHintUntil = os.clock() + HINT_SECONDS
	Hud.hint(text)
end

local function update()
	local now = os.clock()
	if step == "scan" then
		if Dots.spawned - dotsAtStart >= FIRST_SCAN_DOTS then
			(Net.get("Funnel") :: RemoteEvent):FireServer("TutorialFirstScan")
			setStep("focus")
		end
	elseif step == "focus" then
		if Lidar.focusing or now - stepStarted > FOCUS_HINT_SECONDS then
			setStep("find")
		end
	end

	if timedHintUntil > 0 and now >= timedHintUntil then
		timedHintUntil = 0
		Hud.hint(nil)
	end

	if State.server.stage == "level" then
		if Lidar.overheated then
			once("overheat", "Overheated. Focus comes back as the scanner cools.")
		end
		if Avatar.wading then
			once("wade", "Water. Wading is slow and loud.")
		end
		if State.server.tier == 1 and now - levelStartedAt > SPRINT_HINT_AFTER then
			once("sprint", Input.hint("sprint") .. " to run. Running is loud.")
		end
	end
end

function Tutorial.start()
	State.onState(function(server, previous)
		if server.stage == "tutorial" and previous.stage ~= "tutorial" then
			setStep("scan")
		elseif server.stage ~= "tutorial" and previous.stage == "tutorial" then
			setStep("done")
		end
	end)
	State.onLevel(function()
		levelStartedAt = os.clock()
		local tier = State.server.tier
		local text = TIER_HINTS[tier]
		if text and State.server.mode == "run" and State.profile.bestTier < tier then
			step = "done"
			once("tier" .. tier, text)
		end
	end)
	Lidar.onBatch(function(_count, _distance, enemy, friend, objective)
		if step == "find" and objective then
			setStep("door")
		elseif State.server.stage == "level" then
			if enemy then
				once("enemy", "Red. Stop scanning it and move away quietly.")
			elseif friend and State.server.rescuesTotal > State.server.rescues then
				once("friend", "Green. One of ours: walk up and help them.")
			elseif objective and State.server.tier == 1 then
				once("objective", "Gold is worth walking to: cells, keys, the exit.")
			end
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Tutorial
