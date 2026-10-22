--!strict
-- Teaching by doing, and telling the story as we go. A new player first sees the opening
-- cutscene (Theo falls through a wall into the Backrooms), then the intake room walks them
-- through scatter, the Survey's orientation tape on a television, the sweep and the door.
-- Theo thinks out loud at each first (subtitled), and lines from the Survey manual
-- (src/shared/data/LoreText) carry the rules, with the control for the device in the player's
-- hands in brackets underneath, shown only when it is relevant. After the intake, hints
-- appear once each as new things are met, and surveyors in the camps talk when you arrive.

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
local SPRINT_HINT_AFTER = 35 -- seconds into the first level
local TV_REACH = 3 -- studs: a dot this close to the television's screen counts as a hit on it
local THINK_GAP_SECONDS = 40 -- Theo thinks aloud at most this often
local PROFILE_WAIT_SECONDS = 3 -- how long to wait for a saved profile before assuming a new player
local SCENE_DELAY = 1.6 -- seconds after arriving at a camp before the surveyor speaks

local Tutorial = {}

local step = "idle" -- intake room progress: idle, scan, sweep, find, door, done
local stepStarted = 0
local dotsAtStart = 0
local shown: { [string]: boolean } = {}
local timedHintUntil = 0
local levelStartedAt = 0
local thoughts: { [string]: boolean } = {} -- Theo says each of these once per session
local visited: { [string]: boolean } = {} -- camps whose surveyor has already spoken
local tvHits = 0
local tvPlayed = false
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
	thoughts[key] = true
	lastThought = now
	Hud.dialogue("Theo", Lore.thought(key))
end

local function tvScreen(): BasePart?
	local room = workspace:FindFirstChild("Tutorial")
	local screen = if room then room:FindFirstChild("TVScreen", true) else nil
	return if screen and screen:IsA("BasePart") then screen else nil
end

local setStep: (name: string) -> ()

-- The orientation tape. The screen wakes (a cold blue glow), the tape plays, and the intake
-- carries on with the sweep.
local function playTape()
	if tvPlayed then
		return
	end
	tvPlayed = true
	local screen = tvScreen()
	if screen then
		screen.Transparency = 0
		screen.Material = Enum.Material.Neon
		screen.Color = Color3.fromRGB(150, 190, 255)
		local light = Instance.new("PointLight")
		light.Color = screen.Color
		light.Range = 14
		light.Brightness = 1.4
		light.Parent = screen
	end
	Hud.hint(nil)
	Cutscene.play("tape.orientation")
end

function setStep(name: string)
	step = name
	stepStarted = os.clock()
	if name == "scan" then
		dotsAtStart = Dots.spawned
		Hud.hint("Scan the room. Find a door.\n[" .. Input.hint("fire") .. "]")
	elseif name == "sweep" then
		Hud.hint(poster("rule.03", Input.hint("sweep") .. ": one sweep draws the whole view"))
	elseif name == "find" then
		local key = LoreText.get("rule.04")
		local legend = if key then table.concat(key.lines, "\n") else ""
		Hud.hint(legend .. "\n[" .. Input.hint("spread") .. " to narrow or widen the scatter]")
	elseif name == "door" then
		Hud.hint("The gold dots are a door. Walk to them.\n[" .. Input.hint("interact") .. "]")
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
		return poster("rule.09", "Keep your dots on a lamp until it wakes")
	elseif tier == 4 then
		return words("rule.10", true)
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
	local waited = 0
	while not State.profileLoaded and waited < PROFILE_WAIT_SECONDS do
		waited += task.wait(0.1)
	end
	if State.server.stage ~= "tutorial" then
		return
	end
	if State.profile.tutorialDone then
		setStep("scan")
		return
	end
	Cutscene.play("cs.open", function()
		if State.server.stage == "tutorial" then
			setStep("scan")
		end
	end)
end

function Tutorial.start()
	State.onState(function(server, previous)
		if server.stage == "tutorial" and previous.stage ~= "tutorial" then
			tvHits = 0
			tvPlayed = false
			task.spawn(beginIntake)
		elseif server.stage ~= "tutorial" and previous.stage == "tutorial" then
			setStep("done")
		end
	end)
	Lidar.onHit(function(position: Vector3)
		local screen = tvScreen()
		if
			step ~= "idle"
			and step ~= "done"
			and screen ~= nil
			and (screen.Position - position).Magnitude < TV_REACH
		then
			tvHits += 1
			if tvHits >= Config.Lidar.lightRevealHits then
				playTape()
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
		if room and room.scene and not visited[roomId] then
			visited[roomId] = true
			task.delay(SCENE_DELAY, function()
				if State.server.stage == "lore" and State.server.loreRoom == roomId then
					Cutscene.play(room.scene :: string)
				end
			end)
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
				once(
					"enemy",
					"Red dots: something that was a person. Get low.\n["
						.. Input.hint("crouch")
						.. "]"
				)
			elseif friend and State.server.rescuesTotal > State.server.rescues then
				think("surveyor")
				once("friend", words("rule.10", true))
			elseif objective and State.server.tier == 1 then
				once(
					"objective",
					"Gold dots are worth the walk.\n[" .. Input.hint("interact") .. " to pick up]"
				)
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
