--!strict
-- Teaching by doing, and telling the story as we go. A new player first sees the opening
-- cutscene (Theo falls through a wall into the Backrooms), then the intake room walks them
-- through scatter, the sweep and the door, and a television that wakes by itself when enough
-- dots land on it: its tape (the Survey's orientation) is the player's to watch or leave.
-- Theo thinks out loud at each first (subtitled), and lines from the Survey manual
-- (src/shared/data/LoreText) carry the rules, with the control for the device in the player's
-- hands in brackets underneath, shown only when it is relevant. After the intake, hints
-- appear once each as new things are met; surveyors in the camps talk once found
-- (Surveyors.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(script.Parent.Atmosphere)
local Avatar = require(script.Parent.Avatar)
local Config = require(ReplicatedStorage.Shared.Config)
local Cutscene = require(script.Parent.Cutscene)
local Dots = require(script.Parent.Dots)
local Hud = require(script.Parent.Hud)
local Input = require(script.Parent.Input)
local Lidar = require(script.Parent.Lidar)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local LoreText = require(ReplicatedStorage.Shared.data.LoreText)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

local FIRST_SCAN_DOTS = 50
local SWEEP_HINT_SECONDS = 12
local HINT_SECONDS = 8
local HINT_PATIENCE_SECONDS = 30 -- a hint waits this long for the screen to be quiet, then gives up
local SPRINT_HINT_AFTER = 35 -- seconds into the first level
local TV_REACH = 3 -- studs: a dot this close to the television's screen counts as a hit on it
local TV_HITS = 30 -- dots the screen needs before it wakes: looked at, not brushed past
local TV_HINT = "A screen just woke up. Go look."
local THINK_GAP_SECONDS = 40 -- Theo thinks aloud at most this often
local PROFILE_WAIT_SECONDS = 3 -- how long to wait for a saved profile before assuming a new player

local Tutorial = {}

local step = "idle" -- intake room progress: idle, scan, sweep, find, door, done
local stepStarted = 0
local dotsAtStart = 0
local shown: { [string]: boolean } = {}
local timedHintUntil = 0
local levelStartedAt = 0
local thoughts: { [string]: boolean } = {} -- Theo says each of these once per session
local tvHits = 0
local tvAwake = false
local tvHintUntil = 0 -- while the "screen woke" hint is up, the step's own hint is put back after it
local intake = 0 -- counts intakes, so a late callback of an earlier one does nothing
local lastThought = -1000

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

-- Theo thinks out loud: subtitled, once per session. `key` is a LoreText "thought.<key>".
local function think(key: string)
	local now = os.clock()
	if thoughts[key] or not State.storyLive or now - lastThought < THINK_GAP_SECONDS then
		return -- quiet until the first hidden object speaks, and never chatty after it
	end
	-- Only into a quiet screen. If someone else is talking the thought is not spent: it comes
	-- back the next time the same thing happens.
	if Hud.dialogue("Theo", Lore.thought(key), true) then
		thoughts[key] = true
		lastThought = now
	end
end

local function tvScreen(): BasePart?
	local room = workspace:FindFirstChild("Tutorial")
	local screen = if room then room:FindFirstChild("TVScreen", true) else nil
	return if screen and screen:IsA("BasePart") then screen else nil
end

local setStep: (name: string) -> ()

-- What the hint line says for an intake step ("" for none).
local function stepHint(name: string): string
	if name == "scan" then
		return "Scan.\n[" .. Input.hint("fire") .. "]"
	elseif name == "sweep" then
		return "[" .. Input.hint("sweep") .. "] sweeps the whole view"
	elseif name == "find" then
		return "White: walls. Green: friends. Red: danger.\n["
			.. Input.hint("spread")
			.. " widens the scatter]"
	elseif name == "door" then
		return "Gold dots are the way on.\n[" .. Input.hint("interact") .. "]"
	end
	return ""
end

-- The intake television wakes: it lights up with a Watch prompt, and a hint says so once the
-- screen is quiet. The tape is optional: nothing waits for it and the door hint never does. It
-- plays when the prompt is used (client/Tapes), and can be watched again.
local function wakeTv()
	if tvAwake then
		return
	end
	local screen = tvScreen()
	if screen == nil then
		return
	end
	tvAwake = true
	screen.Transparency = 0
	local light = screen:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = true
	end
	local prompt = screen:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = true
	end
	local mine = intake
	task.spawn(function()
		local waited = 0
		while (Hud.busy() or Cutscene.playing) and waited < HINT_PATIENCE_SECONDS do
			waited += task.wait(0.5)
		end
		if mine ~= intake or State.server.stage ~= "tutorial" then
			return -- the player left the intake while the hint waited
		end
		tvHintUntil = os.clock() + HINT_SECONDS
		Hud.hint(TV_HINT)
	end)
end

function setStep(name: string)
	step = name
	stepStarted = os.clock()
	tvHintUntil = 0 -- a new lesson replaces the screen's hint
	if name == "scan" then
		dotsAtStart = Dots.spawned
	end
	local text = stepHint(name)
	Hud.hint(if text ~= "" then text else nil)
end

-- A hint that shows once per session and clears itself. It waits its turn: never while a scene
-- plays, someone is talking or a name is on the screen.
local function once(key: string, text: string)
	if shown[key] or step ~= "done" and step ~= "idle" then
		return
	end
	shown[key] = true
	task.spawn(function()
		local waited = 0
		while (Hud.busy() or Cutscene.playing) and waited < HINT_PATIENCE_SECONDS do
			waited += task.wait(0.5)
		end
		if step ~= "done" and step ~= "idle" then
			return
		end
		timedHintUntil = os.clock() + HINT_SECONDS
		Hud.hint(text)
	end)
end

-- Shown the first time a player reaches the tier that introduces something new.
local function tierHint(tier: number): string?
	if tier == 3 then
		return poster("rule.09", "Keep your dots on a lamp until it wakes")
	elseif tier == 5 then
		return words("rule.07", true)
	elseif tier == 6 then
		return poster("rule.08", "Greet crew with the ping wheel")
	end
	return nil
end

-- Which monster a tier is about, for Theo's first reaction to a red dot.
local function monsterThought(tier: number): string
	if tier <= 2 then
		return "keys"
	elseif tier <= 4 then
		return "hush"
	elseif tier <= 6 then
		return "echo"
	end
	return "still"
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
	if tvHintUntil > 0 and now >= tvHintUntil then
		tvHintUntil = 0
		-- Back to the lesson the screen interrupted, if the player is still in the intake.
		local text = if State.server.stage == "tutorial" then stepHint(step) else ""
		Hud.hint(if text ~= "" then text else nil)
	end

	if State.server.stage == "level" then
		if Avatar.wading then
			think("water")
		end
		if Lidar.echoProgress > 0 then
			once("recorder", "Something here wants to be found.\n[Keep your dots on it]")
		end
		if State.server.tier == 1 and now - levelStartedAt > SPRINT_HINT_AFTER then
			once("sprint", "[" .. Input.hint("sprint") .. " to run. Running is loud]")
		end
	end
end

-- A new player sees the opening cutscene before the intake; anyone else goes straight in.
local function beginIntake()
	local mine = intake
	local waited = 0
	while not State.profileLoaded and waited < PROFILE_WAIT_SECONDS do
		waited += task.wait(0.1)
	end
	if mine ~= intake or State.server.stage ~= "tutorial" then
		return
	end
	if State.profile.tutorialDone then
		setStep("scan")
		return
	end
	Cutscene.play("cs.open", function()
		-- The scene can end early (a friend opened the door and the player is in the level
		-- now) or the intake can have restarted: then there is no lesson to begin.
		if mine == intake and State.server.stage == "tutorial" then
			setStep("scan")
		end
	end)
end

function Tutorial.start()
	State.onState(function(server, previous)
		if server.stage == "tutorial" and previous.stage ~= "tutorial" then
			intake += 1
			tvHits = 0
			tvAwake = false
			task.spawn(beginIntake)
		elseif server.stage ~= "tutorial" and previous.stage == "tutorial" then
			intake += 1
			setStep("done")
		end
	end)
	Lidar.onHit(function(position: Vector3)
		-- Not during the first two lessons: a new player's first stray dots used to take over the
		-- screen before they had learned to scan. From "find" on the television is theirs to find.
		if step ~= "find" and step ~= "door" then
			return
		end
		local screen = tvScreen()
		if screen ~= nil and (screen.Position - position).Magnitude < TV_REACH then
			tvHits += 1
			if tvHits >= TV_HITS then
				wakeTv()
			end
		end
	end)
	Atmosphere.onZone(function(zone)
		if zone == nil or State.server.stage ~= "lore" then
			return
		end
		local roomId = State.server.loreRoom
		if roomId == "cistern" then
			think("falls")
		end
		local room = Lore.rooms[roomId]
		if room and room.surveyor then
			-- The surveyor is a person in the dark (client/Surveyors); they talk once found.
			once("camp." .. roomId, "Somebody is knocking. Follow the sound and scan the dark")
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
	-- The first time a sweep is asked for with an empty battery.
	Lidar.onDenied(function()
		once(
			"cells",
			poster("item.cell", "The sweep runs on battery cells. Scan the dark for them")
		)
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
				think(monsterThought(State.server.tier))
				once("enemy", "[" .. Input.hint("crouch") .. " to get low]")
			elseif friend and State.server.rescuesTotal > State.server.rescues then
				think("surveyor")
				once("friend", words("rule.10", true))
			end
		end
	end);
	(Net.get("Hazard") :: RemoteEvent).OnClientEvent:Connect(
		function(kind: string, _position: Vector3, userId: number)
			if kind == "plate" then
				think("plate")
			elseif kind == "pit" and userId == Players.LocalPlayer.UserId then
				think("pit")
			end
		end
	)
	local caught = Net.get("Caught") :: RemoteEvent
	caught.OnClientEvent:Connect(function(_kind: string, downed: boolean)
		if not downed then
			task.delay(Config.World.respawnSeconds + 2.5, function()
				think(if thoughts["respawn.first"] then "respawn.ines" else "respawn.first")
			end)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Tutorial
