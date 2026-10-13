--!strict
-- Teaching by doing, in the world's own voice. The story bible's rule is that the game never
-- lectures: what the player learns comes from staff notices and pages of the survey manual
-- (src/shared/data/LoreText). Each hint is one of those lines, with the control for the
-- device in the player's hands in brackets underneath, shown only when it is relevant. The
-- intake room walks a new player through scatter, sweep and the door; after that, hints
-- appear once each as new things are met.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Avatar = require(script.Parent.Avatar)
local Dots = require(script.Parent.Dots)
local Hud = require(script.Parent.Hud)
local Input = require(script.Parent.Input)
local Lidar = require(script.Parent.Lidar)
local LoreText = require(ReplicatedStorage.Shared.data.LoreText)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

local FIRST_SCAN_DOTS = 50
local SWEEP_HINT_SECONDS = 12
local HINT_SECONDS = 8
local SPRINT_HINT_AFTER = 35 -- seconds into the first level

local Tutorial = {}

local step = "idle" -- intake room progress: idle, scan, sweep, find, door, done
local stepStarted = 0
local dotsAtStart = 0
local shown: { [string]: boolean } = {}
local timedHintUntil = 0
local levelStartedAt = 0

-- The printed lines of a story entry (margin notes left out unless asked for), joined.
local function words(id: string, withMargin: boolean?): string
	local entry = LoreText.get(id)
	if entry == nil then
		return ""
	end
	local kept = {}
	for _, line in entry.lines do
		local margin = string.sub(line, 1, 7) == "margin:"
		if not margin or withMargin then
			table.insert(kept, line)
		end
	end
	return (string.gsub(table.concat(kept, " "), "^%d+%. ", ""))
end

-- A story line with the device's control underneath.
local function poster(id: string, control: string?): string
	local text = words(id)
	if control ~= nil and control ~= "" then
		text ..= "\n[" .. control .. "]"
	end
	return text
end

local function setStep(name: string)
	step = name
	stepStarted = os.clock()
	if name == "scan" then
		dotsAtStart = Dots.spawned
		Hud.hint(poster("sign.intake.1", Input.hint("fire")))
	elseif name == "sweep" then
		Hud.hint(poster("rule.02", Input.hint("sweep") .. ": one sweep draws the whole view"))
	elseif name == "find" then
		local key = LoreText.get("sign.intake.2")
		local legend = if key then table.concat(key.lines, "   ") else ""
		Hud.hint(legend .. "\n[" .. Input.hint("spread") .. " to narrow or widen the scatter]")
	elseif name == "door" then
		Hud.hint(
			poster("sign.intake.3", "Walk to the gold and " .. string.lower(Input.hint("interact")))
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

-- Shown the first time a player reaches the tier that introduces something new.
local function tierHint(tier: number): string?
	if tier == 1 then
		return poster("rule.05", Input.hint("crouch") .. " to move unseen")
	elseif tier == 3 then
		return poster("rule.04", "The sweep is loud. Scattering is not")
	elseif tier == 4 then
		return poster("rule.09", "Wading is loud, even crouched")
	elseif tier == 5 then
		return words("rule.07", true)
	elseif tier == 6 then
		return poster("rule.10", "Keep your dots on it")
	end
	return nil
end

local function update()
	local now = os.clock()
	if step == "scan" then
		if Dots.spawned - dotsAtStart >= FIRST_SCAN_DOTS then
			(Net.get("Funnel") :: RemoteEvent):FireServer("TutorialFirstScan")
			setStep("sweep")
		end
	elseif step == "sweep" then
		if now - stepStarted > SWEEP_HINT_SECONDS then
			setStep("find")
		end
	end

	if timedHintUntil > 0 and now >= timedHintUntil then
		timedHintUntil = 0
		Hud.hint(nil)
	end

	if State.server.stage == "level" then
		if Avatar.wading then
			once("wade", poster("hint.water"))
		end
		if Lidar.echoProgress > 0 then
			once("recorder", "Something here wants to be found.\n[Keep your dots on it]")
		end
		if State.server.tier == 1 and now - levelStartedAt > SPRINT_HINT_AFTER then
			once("sprint", "[" .. Input.hint("sprint") .. " to run. Running is loud]")
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
		local text = tierHint(tier)
		if text and State.server.mode == "run" and State.profile.bestTier < tier then
			step = "done"
			once("tier" .. tier, text)
		end
	end)
	Lidar.onSweep(function()
		if step == "sweep" then
			setStep("find")
		end
	end)
	Lidar.onBatch(function(_count, _distance, enemy, friend, objective)
		if step == "find" and objective then
			setStep("door")
		elseif State.server.stage == "level" then
			if enemy then
				once("enemy", poster("rule.03", "Get low: " .. Input.hint("crouch")))
			elseif friend and State.server.rescuesTotal > State.server.rescues then
				once("friend", words("rule.07"))
			elseif objective and State.server.tier == 1 then
				once("objective", poster("hint.pickup"))
			end
		end
	end);
	(Net.get("Hazard") :: RemoteEvent).OnClientEvent:Connect(
		function(kind: string, _position: Vector3, userId: number)
			if kind == "plate" then
				once("plate", poster("hint.plate"))
			elseif kind == "pit" and userId == Players.LocalPlayer.UserId then
				once("pit", poster("hint.pit"))
			end
		end
	)
	RunService.Heartbeat:Connect(update)
end

return Tutorial
