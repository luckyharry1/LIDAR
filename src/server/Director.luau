--!strict
-- The game flow. One server hosts one party's run: title -> (tutorial) -> level -> level ->
-- lore room -> ... The Director owns that state machine, wires every prompt and remote to it,
-- and is the only module that changes profiles. Clients are told what happened; they are
-- never asked what should happen.

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Daily = require(ReplicatedStorage.Shared.pure.Daily)
local Data = require(script.Parent.Data)
local Difficulty = require(ReplicatedStorage.Shared.pure.Difficulty)
local Enemies = require(script.Parent.Enemies)
local EnemyBrain = require(ReplicatedStorage.Shared.pure.EnemyBrain)
local Leaderboard = require(script.Parent.Leaderboard)
local LevelPlan = require(ReplicatedStorage.Shared.pure.LevelPlan)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local LoreRooms = require(script.Parent.LoreRooms)
local Passage = require(script.Parent.Passage)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Noise = require(ReplicatedStorage.Shared.pure.Noise)
local Party = require(script.Parent.Party)
local Progression = require(ReplicatedStorage.Shared.pure.Progression)
local Remotes = require(script.Parent.Remotes)
local Telemetry = require(script.Parent.Telemetry)
local TutorialRoom = require(script.Parent.TutorialRoom)
local Upgrades = require(ReplicatedStorage.Shared.data.Upgrades)
local World = require(script.Parent.World)

type Stage = "title" | "tutorial" | "level" | "downed" | "lore" | "passage"

type Member = {
	player: Player,
	stage: Stage,
	starting: boolean, -- true once Play has been pressed, so a double press is ignored
	slot: number, -- 1..maxPlayers, picks the tutorial room position and spawn offset
	scanFiring: boolean,
	scanSweeping: boolean,
	crouching: boolean, -- as reported; only believed while the player is moving slowly
	scanLook: Vector3,
	scanAt: number,
	graceUntil: number,
	caughtThisLevel: boolean,
	catchesThisLevel: number,
	reviveProgress: number,
	respawnCFrame: CFrame?,
	tutorial: TutorialRoom.Tutorial?,
	lastPosition: Vector3?,
	lastPingAt: number,
	ownsKit: boolean,
	effects: Progression.Effects,
	sessionStatic: number,
	sessionLevels: number,
	sessionCatches: number,
	sessionLore: number,
	sessionDistance: number,
	endingOffered: boolean, -- Ines has asked; one answer is accepted
}

type Collected = { key: boolean, cells: number, rescues: number, plate: boolean, echoes: number }
type Decoy = { x: number, z: number, noise: number, expires: number }

local CELL = Config.World.cellSize
local DOORWAY_HOLD_SECONDS = 0.6
local DOORWAY_LEAVE_SECONDS = 1 -- the step through: the screen is black by then
local LOCKED_TOAST_SECONDS = 4
local PASSAGE_ORIGIN = Vector3.new(0, 0, -1500)
local PASSAGE_END_RADIUS = 5
local PASSAGE_MAX_SECONDS = 150 -- someone who never reaches the bottom is carried on anyway
local PASSAGE_POLL_SECONDS = 0.25
local LEVEL_ORIGINS = { Vector3.new(0, 0, 0), Vector3.new(0, 0, 700) } -- levels alternate between these
local SCAN_STALE_SECONDS = 1 -- a scan report older than this counts as "not scanning"
local LOGIC_HZ = 4
local MAX_STEP_DISTANCE = 40 -- studs per logic tick; anything more is a teleport, not walking
local PROMPT_SLACK = 8 -- extra studs allowed on top of the prompt distance for lag
local SPAWN_SPREAD = 2.5
local SEED_SPAN = 2 ^ 30
local SEED_STEP = 7919
local BEACON_RADIUS = 10
local TRANSITION_POLL_SECONDS = 0.2
local PLATE_REACH = 6 -- studs above a plate within which a player counts as standing on it
local DOT_QUALITIES = { auto = true, low = true, medium = true, high = true }
local SETTINGS = {
	palette = function(value: any): boolean
		return value == "default" or value == "alt"
	end,
	sharedScans = function(value: any): boolean
		return type(value) == "boolean"
	end,
	scanMode = function(value: any): boolean
		return value == "auto" or value == "hold" or value == "toggle"
	end,
	volume = function(value: any): boolean
		return type(value) == "number" and value == value and value >= 0 and value <= 1
	end,
	dotQuality = function(value: any): boolean
		return DOT_QUALITIES[value] == true
	end,
}

local Director = {}

local members: { [Player]: Member } = {}
local random = Random.new()

local run = {
	active = false,
	mode = "run", -- "run" or "daily"
	tier = 1,
	seedBase = 1,
	phase = "idle", -- "idle" | "level" | "lore" | "transition"
	level = nil :: World.Level?,
	lore = nil :: LoreRooms.LoreRoom?,
	collected = { key = false, cells = 0, rescues = 0, plate = false, echoes = 0 } :: Collected,
	levelStartedAt = 0,
	originIndex = 1,
	nextTier = 1,
	plateFound = false,
	weeklyShown = false,
	decoys = {} :: { Decoy },
	respawning = false,
	passage = nil :: Passage.Passage?,
	epoch = 0, -- bumped whenever the world is rebuilt or torn down, so clients drop what they drew
}

--------------------------------------------------------------------------------------------
-- Small helpers

local function profileOf(member: Member): Data.Profile
	return Data.get(member.player) :: Data.Profile
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function toast(player: Player, text: string, kind: string?)
	Remotes.send(player, "Toast", text, kind or "info")
end

local function toastStage(text: string, kind: string?, ...: Stage)
	local stages = { ... }
	for player, member in members do
		if table.find(stages, member.stage) then
			toast(player, text, kind)
		end
	end
end

local function inLevel(member: Member): boolean
	return member.stage == "level" or member.stage == "downed"
end

local function countStage(stage: Stage): number
	local count = 0
	for _, member in members do
		if member.stage == stage then
			count += 1
		end
	end
	return count
end

local function sendProfile(member: Member)
	local profile = profileOf(member)
	member.effects = Progression.effects(profile)
	Remotes.send(member.player, "Profile", profile, member.effects, {
		persistent = Data.isPersistent(member.player),
		kitPassId = Config.Monetization.surveyorKitPassId,
		ownsKit = member.ownsKit,
		canPromptPurchase = profile.stats.levels >= Config.Monetization.promptAfterLevels,
	})
end

local function objectiveTotals(): (number, number)
	local level = run.level
	local cells, rescues = 0, 0
	if level then
		for _, objective in level.plan.objectives do
			if objective.kind == "cell" then
				cells += 1
			elseif objective.kind == "rescue" then
				rescues += 1
			end
		end
	end
	return cells, rescues
end

-- What opens this level's locked exit, as the story names it ("Fuse", "Valve Wheel").
local function gateTitle(plan: LevelPlan.LevelPlan): string
	local _, title = World.gate(plan)
	return title
end

-- Hidden objects worth counting on the HUD: recorders and story objects. Posters and lamp-bag
-- tags are found along the way and not counted.
local function countFinds(level: World.Level): number
	local total = 0
	for _, echo in level.echoes do
		if echo.kind == "recorder" or echo.kind == "reveal" then
			total += 1
		end
	end
	return total
end

local function sendState(member: Member)
	local level = run.level
	local lore = run.lore
	local cellsTotal, rescuesTotal = objectiveTotals()
	local day = Daily.dayNumber(os.time())
	local profile = profileOf(member)
	Remotes.send(member.player, "State", {
		stage = member.stage,
		phase = run.phase,
		mode = run.mode,
		tier = run.tier,
		tierName = if level then level.plan.def.name else "",
		seed = if level then level.plan.seed else 0,
		epoch = run.epoch,
		origin = if level then level.origin else Vector3.zero,
		sweepScale = if level and inLevel(member) then level.plan.def.sweepScale else 1,
		-- With (tier, seed) these two options let the client rebuild the exact same plan.
		forcedAnomaly = if level then level.model:GetAttribute("ForcedAnomaly") else "",
		allowPlate = level ~= nil and level.model:GetAttribute("AllowPlate") == true,
		locked = level ~= nil and level.plan.exitLocked,
		hasKey = run.collected.key,
		gateName = if level and level.plan.exitLocked then gateTitle(level.plan) else "",
		cells = run.collected.cells,
		cellsTotal = cellsTotal,
		rescues = run.collected.rescues,
		rescuesTotal = rescuesTotal,
		echoes = run.collected.echoes,
		echoesTotal = if level then countFinds(level) else 0,
		loreRoom = if lore and member.stage == "lore" then lore.room.id else "",
		partySize = countStage("level") + countStage("downed") + countStage("lore"),
		checkpointTier = profile.checkpointTier,
		dailyDay = day,
		dailyDone = profile.daily.day == day,
		runActive = run.active,
		session = {
			static = member.sessionStatic,
			levels = member.sessionLevels,
			catches = member.sessionCatches,
			lore = member.sessionLore,
			distance = math.floor(member.sessionDistance),
		},
	})
end

local function sendStateAll()
	for _, member in members do
		sendState(member)
	end
end

local function grant(member: Member, amount: number, reason: string)
	if amount <= 0 then
		return
	end
	local profile = profileOf(member)
	profile.static += amount
	member.sessionStatic += amount
	Data.touch(member.player)
	Telemetry.earned(member.player, amount, profile.static, reason)
end

--------------------------------------------------------------------------------------------
-- Characters

-- Avatars must not glow in the dark: strip anything emissive once the appearance has loaded.
local function darken(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			if
				descendant.Material == Enum.Material.Neon
				or descendant.Material == Enum.Material.ForceField
			then
				descendant.Material = Enum.Material.SmoothPlastic
			end
		elseif
			descendant:IsA("Light")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Fire")
			or descendant:IsA("Sparkles")
			or descendant:IsA("Smoke")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Highlight")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("BillboardGui")
		then
			descendant:Destroy()
		end
	end
end

local homeCFrame: (member: Member) -> CFrame?

local function setUpCharacter(member: Member, character: Model)
	CollectionService:AddTag(character, Config.Tags.friend)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.Player.walkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Player.jumpPower
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Died:Connect(function()
		-- Only possible by falling out of the world; put them back where they belong.
		task.wait(1)
		local home = homeCFrame(member)
		if home ~= nil and members[member.player] == member then
			Director.placeMember(member, home)
		end
	end)
	darken(character)
	task.spawn(function()
		if not member.player:HasAppearanceLoaded() then
			member.player.CharacterAppearanceLoaded:Wait()
		end
		darken(character)
	end)
end

-- Moves a member's character to a CFrame, loading the character first if needed.
function Director.placeMember(member: Member, target: CFrame)
	local player = member.player
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		player:LoadCharacter()
		character = player.Character
		if character == nil then
			return
		end
		setUpCharacter(member, character)
	end
	local offset = CFrame.new((member.slot - 1) * SPAWN_SPREAD - SPAWN_SPREAD, 0, 0)
	character:PivotTo(target * offset)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		member.lastPosition = root.Position
	end
end

local function setWalkEnabled(member: Member, enabled: boolean)
	local character = member.player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.WalkSpeed = if enabled then Config.Player.walkSpeed else 0
	end
	if character then
		character:SetAttribute("Downed", not enabled)
	end
end

function homeCFrame(member: Member): CFrame?
	if member.stage == "tutorial" and member.tutorial then
		return member.tutorial.spawnCFrame
	elseif inLevel(member) and run.level then
		return member.respawnCFrame or run.level.startCFrame
	elseif member.stage == "lore" and run.lore then
		return run.lore.spawnCFrame
	end
	return nil
end

--------------------------------------------------------------------------------------------
-- Enemies: what they can sense, and what happens when they catch someone

local function buildSources(): { EnemyBrain.Source }
	local level = run.level
	local sources: { EnemyBrain.Source } = {}
	if level == nil then
		return sources
	end
	local now = os.clock()
	local maze = level.plan.maze
	for player, member in members do
		local root = rootOf(player)
		if inLevel(member) and root ~= nil then
			local relative = (root.Position - level.origin) / CELL
			local cell = Maze.cellOf(maze, relative.X, relative.Z)
			local velocity = root.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local fresh = now - member.scanAt < SCAN_STALE_SECONDS
			local scanning = fresh and member.scanFiring
			local sweeping = fresh and member.scanSweeping
			-- Crouching is the client's word, so it only counts at a crouching pace.
			local crouching = fresh and member.crouching and speed <= Config.Noise.crouchSpeedLimit
			local alive = member.stage == "level"
			table.insert(sources, {
				id = player.UserId,
				x = relative.X,
				z = relative.Z,
				noise = if alive
					then Noise.radius(
						speed,
						sweeping,
						scanning,
						crouching,
						level.plan.flooded[Maze.index(maze, cell.x, cell.y)] == true,
						member.effects.solesLevel,
						member.effects.shutterLevel
					)
					else 0,
				scanning = alive and (scanning or sweeping),
				crouching = alive and crouching,
				lookX = member.scanLook.X,
				lookZ = member.scanLook.Z,
				active = alive and now >= member.graceUntil and not run.respawning,
				decoy = false,
			})
		end
	end
	for index = #run.decoys, 1, -1 do
		local decoy = run.decoys[index]
		if now >= decoy.expires then
			table.remove(run.decoys, index)
		else
			table.insert(sources, {
				id = -index,
				x = decoy.x,
				z = decoy.z,
				noise = decoy.noise,
				scanning = false,
				crouching = false,
				lookX = 0,
				lookZ = 1,
				active = false,
				decoy = true,
			})
		end
	end
	return sources
end

local function memberByUserId(userId: number): Member?
	for player, member in members do
		if player.UserId == userId then
			return member
		end
	end
	return nil
end

-- Everyone in the level goes back to their checkpoint and the enemies go back to their posts.
local function respawnParty()
	local level = run.level
	if level == nil or run.respawning then
		return
	end
	run.respawning = true
	task.delay(Config.World.respawnSeconds, function()
		run.respawning = false
		if run.level ~= level then
			return
		end
		Enemies.resetAll()
		local now = os.clock()
		for player, member in members do
			if inLevel(member) then
				local wasDowned = member.stage == "downed"
				member.stage = "level"
				member.reviveProgress = 0
				member.graceUntil = now + Config.World.respawnGraceSeconds
				setWalkEnabled(member, true)
				Director.placeMember(member, member.respawnCFrame or level.startCFrame)
				if wasDowned then
					Remotes.send(player, "Revived")
				end
				sendState(member)
			end
		end
	end)
end

local function onCaught(enemy: EnemyBrain.Enemy, userId: number)
	local level = run.level
	local member = memberByUserId(userId)
	if level == nil or member == nil or member.stage ~= "level" or run.respawning then
		return
	end
	local profile = profileOf(member)
	member.caughtThisLevel = true
	member.catchesThisLevel += 1
	member.sessionCatches += 1
	profile.stats.deaths += 1
	profile.met[enemy.kind] = true
	Data.touch(member.player)
	Telemetry.caught(member.player, run.tier, level.plan.def.name, enemy.kind)

	local othersStanding = countStage("level") - 1
	if othersStanding <= 0 then
		-- Solo, or the last one standing: a quick reset rather than a wipe.
		setWalkEnabled(member, false)
		for player, other in members do
			if inLevel(other) then
				Remotes.send(player, "Caught", enemy.kind, false)
			end
		end
		respawnParty()
	else
		member.stage = "downed"
		member.reviveProgress = 0
		setWalkEnabled(member, false)
		Enemies.stun(enemy)
		Remotes.send(member.player, "Caught", enemy.kind, true)
		toastStage(
			member.player.DisplayName .. " is down. Stand close and scan them.",
			"warn",
			"level"
		)
		sendState(member)
	end
end

local function revive(member: Member)
	member.stage = "level"
	member.reviveProgress = 0
	member.graceUntil = os.clock() + Config.World.respawnGraceSeconds
	setWalkEnabled(member, true)
	Remotes.send(member.player, "Revived")
	toastStage(member.player.DisplayName .. " is back up.", "good", "level")
	sendState(member)
end

local function tickRevives(dt: number)
	local now = os.clock()
	for downedPlayer, downed in members do
		local downedRoot = rootOf(downedPlayer)
		if downed.stage == "downed" and downedRoot ~= nil then
			local helped = false
			for helperPlayer, helper in members do
				local helperRoot = rootOf(helperPlayer)
				if
					helper.stage == "level"
					and helperRoot ~= nil
					and helper.scanFiring
					and now - helper.scanAt < SCAN_STALE_SECONDS
				then
					local toDowned = downedRoot.Position - helperRoot.Position
					local distance = toDowned.Magnitude
					if
						distance <= Config.Coop.reviveDistance
						and (
							distance < 1
							or toDowned.Unit:Dot(helper.scanLook) >= Config.Coop.reviveConeDot
						)
					then
						helped = true
						break
					end
				end
			end
			if helped then
				downed.reviveProgress += dt
			else
				downed.reviveProgress = math.max(0, downed.reviveProgress - dt)
			end
			local character = downedPlayer.Character
			if character then
				character:SetAttribute("Revive", downed.reviveProgress / Config.Coop.reviveSeconds)
			end
			if downed.reviveProgress >= Config.Coop.reviveSeconds then
				revive(downed)
			end
		end
	end
end

--------------------------------------------------------------------------------------------
-- Levels

local completeLevel: () -> ()

local function nearEnough(player: Player, part: BasePart): boolean
	local root = rootOf(player)
	return root ~= nil
		and (root.Position - part.Position).Magnitude
			<= Config.World.promptDistance + PROMPT_SLACK
end

local function wirePickup(level: World.Level, pickup: World.Pickup)
	local taken = false
	pickup.prompt.Triggered:Connect(function(player: Player)
		local member = members[player]
		local anchor = pickup.prompt.Parent :: BasePart
		if
			taken
			or member == nil
			or member.stage ~= "level"
			or run.level ~= level
			or not nearEnough(player, anchor)
		then
			return
		end
		taken = true
		local kind = pickup.objective.kind
		local position = anchor.Position
		pickup.model:Destroy()
		if kind == "key" then
			run.collected.key = true
			toastStage(
				`{gateTitle(level.plan)} found. The exit will open.`,
				"good",
				"level",
				"downed"
			)
		elseif kind == "cell" then
			run.collected.cells += 1
			toastStage("Battery cell. The sweep is charged.", "good", "level", "downed")
		elseif kind == "rescue" then
			run.collected.rescues += 1
			profileOf(member).stats.rescues += 1
			Data.touch(player)
			toastStage("Surveyor found. They lead the way out.", "good", "level", "downed")
		else
			run.collected.plate = true
			run.plateFound = true
			local index = random:NextInteger(1, #Lore.plates)
			for otherPlayer, other in members do
				if inLevel(other) then
					profileOf(other).plates[tostring(index)] = true
					Data.touch(otherPlayer)
					Remotes.send(otherPlayer, "OpenNote", Lore.plateTitle, Lore.plates[index])
				end
			end
		end
		for otherPlayer, other in members do
			if inLevel(other) then
				Remotes.send(
					otherPlayer,
					"Objective",
					kind,
					{ position = position, by = player.UserId }
				)
			end
		end
		sendStateAll()
	end)
end

local function levelSeed(tier: number): number
	if run.mode == "daily" then
		return Daily.seed(Daily.dayNumber(os.time()))
	end
	return (run.seedBase + tier * SEED_STEP) % (SEED_SPAN - 1) + 1
end

-- An exit is an open doorway (no panel to bump into) with a short hold-to-confirm prompt, so
-- nobody leaves by walking into a doorway they could not see in the dark. Anyone of `stage`
-- (default "level") who confirms calls `enter`, which returns true once the party is leaving.
local function watchDoorway(
	prompt: ProximityPrompt,
	alive: () -> boolean,
	enter: (player: Player) -> boolean,
	stage: Stage?
)
	local wanted = stage or "level"
	local door = prompt.Parent :: BasePart
	door.CanCollide = false
	prompt.ActionText = "Go down"
	prompt.ObjectText = "Stairwell"
	prompt.HoldDuration = DOORWAY_HOLD_SECONDS
	prompt.Enabled = true
	prompt.Triggered:Connect(function(player: Player)
		local member = members[player]
		if
			member == nil
			or member.stage ~= wanted
			or not alive()
			or not nearEnough(player, door)
		then
			return
		end
		if enter(player) then
			prompt.Enabled = false
		end
	end)
end

local function beginLevel(tier: number)
	run.phase = "transition"
	run.epoch += 1
	local oldLevel, oldLore = run.level, run.lore
	Enemies.clear()

	local forced: string? = nil
	if run.mode == "run" and not run.weeklyShown and tier >= Config.Anomaly.minTier then
		forced = Daily.weeklyAnomaly(Daily.weekNumber(Daily.dayNumber(os.time())))
	end
	local allowPlate = not run.plateFound and run.mode == "run"
	local plan =
		LevelPlan.build(tier, levelSeed(tier), { forcedAnomaly = forced, allowPlate = allowPlate })
	if forced ~= nil and plan.anomaly ~= nil then
		run.weeklyShown = true
	end

	run.originIndex = run.originIndex % #LEVEL_ORIGINS + 1
	local level = World.buildLevel(plan, LEVEL_ORIGINS[run.originIndex])
	level.model:SetAttribute("AllowPlate", allowPlate)
	level.model:SetAttribute("ForcedAnomaly", forced or "")
	run.level = level
	run.lore = nil
	run.tier = tier
	run.collected = { key = false, cells = 0, rescues = 0, plate = false, echoes = 0 }
	run.decoys = {}
	run.levelStartedAt = os.clock()

	for _, pickup in level.pickups do
		wirePickup(level, pickup)
	end
	-- The exit is an open doorway into the stairwell: confirming at it takes everyone down.
	local lockedToastAt: { [Player]: number } = {}
	watchDoorway(level.exitPrompt, function()
		return run.level == level
	end, function(player: Player): boolean
		if level.plan.exitLocked and not run.collected.key then
			local now = os.clock()
			if now - (lockedToastAt[player] or -math.huge) >= LOCKED_TOAST_SECONDS then
				lockedToastAt[player] = now
				toast(
					player,
					`Locked. Something on this level opens it: the {gateTitle(level.plan)}.`,
					"warn"
				)
			end
			return false
		end
		toastStage("Exit found. Leaving together.", "good", "level", "downed")
		for otherPlayer, other in members do
			if inLevel(other) then
				Remotes.send(
					otherPlayer,
					"Objective",
					"exit",
					{ position = level.exitDoor.Position, by = player.UserId }
				)
			end
		end
		task.delay(DOORWAY_LEAVE_SECONDS, function()
			if run.level == level then
				completeLevel()
			end
		end)
		return true
	end)

	if Config.Monetization.surveyorKitPassId ~= 0 then
		local beacon = Instance.new("Part")
		beacon.Name = "Beacon"
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.Size = Vector3.new(1, 3, 1)
		beacon.Position = level.beaconPosition
		beacon.Color = Color3.fromRGB(60, 60, 64)
		CollectionService:AddTag(beacon, Config.Tags.objective)
		beacon.Parent = level.model
	end

	-- The Mimic poses as a stranded surveyor; it only makes sense once someone in the party has
	-- helped up a real one and knows what they look like.
	local anyRescued = false
	for _, member in members do
		if member.stage ~= "title" and profileOf(member).stats.rescues > 0 then
			anyRescued = true
		end
	end
	Enemies.spawn(level, buildSources, onCaught, if anyRescued then nil else { mimic = true })

	local now = os.clock()
	for player, member in members do
		if
			member.stage == "level"
			or member.stage == "downed"
			or member.stage == "lore"
			or member.stage == "passage"
		then
			member.stage = "level"
			member.caughtThisLevel = false
			member.catchesThisLevel = 0
			member.reviveProgress = 0
			member.respawnCFrame = nil
			member.graceUntil = now + Config.World.respawnGraceSeconds
			setWalkEnabled(member, true)
			Director.placeMember(member, level.startCFrame)
			Telemetry.levelStarted(player, tier, plan.def.name)
		end
	end
	run.phase = "level"
	sendStateAll()

	if oldLevel then
		oldLevel.model:Destroy()
	end
	if oldLore then
		oldLore.model:Destroy()
	end
end

local function enterLore(roomId: string, nextTier: number)
	run.phase = "transition"
	run.epoch += 1
	local oldLevel, oldLore = run.level, run.lore
	Enemies.clear()
	if oldLore then
		oldLore.model:Destroy() -- only the Studio dev command can enter one lit room from another
	end
	local lore = LoreRooms.build(roomId, Vector3.new(table.unpack(Config.World.loreOrigin)))
	run.lore = lore
	run.level = nil
	run.nextTier = nextTier

	for _, note in lore.notes do
		note.prompt.Triggered:Connect(function(player: Player)
			local member = members[player]
			if member == nil or member.stage ~= "lore" or run.lore ~= lore then
				return
			end
			local profile = profileOf(member)
			local text = Lore.notes[note.id]
			-- The guest book signs in whoever is in the room right now.
			local names = {}
			for otherPlayer, other in members do
				if other.stage == "lore" then
					table.insert(names, otherPlayer.DisplayName)
				end
			end
			table.sort(names)
			local body = Lore.fill(text.body, { party = table.concat(names, "\n") })
			if not profile.lore[note.id] then
				profile.lore[note.id] = true
				member.sessionLore += 1
				grant(member, Config.Economy.loreNoteBonus, "LoreNote")
				sendProfile(member)
			end
			Remotes.send(player, "OpenNote", text.title, body)
			if
				note.id == lore.room.notes[#lore.room.notes]
				and lore.room.id == "stairwell"
				and not profile.endingSeen
			then
				profile.endingSeen = true
				member.endingOffered = true
				Data.touch(player)
				Remotes.send(
					player,
					"Ending",
					Lore.ending.title,
					Lore.endingBody(profile.stats.deaths)
				)
			end
		end)
	end
	lore.benchPrompt.Triggered:Connect(function(player: Player)
		local member = members[player]
		if member ~= nil and member.stage == "lore" and run.lore == lore then
			Remotes.send(player, "OpenBench")
		end
	end)
	-- The way on is an open doorway in the dark: confirming at it leaves the haven.
	watchDoorway(lore.exitPrompt, function()
		return run.lore == lore
	end, function(): boolean
		toastStage("Lights off behind you. Heading back in.", "info", "lore")
		for otherPlayer, other in members do
			if other.stage == "lore" then
				Remotes.send(
					otherPlayer,
					"Objective",
					"exit",
					{ position = lore.spawnCFrame.Position, by = 0 }
				)
			end
		end
		task.delay(DOORWAY_LEAVE_SECONDS, function()
			if run.lore == lore then
				run.mode = "run"
				local tier = run.nextTier
				Director.walkPassage(function()
					beginLevel(tier)
				end)
			end
		end)
		return true
	end, "lore")

	for player, member in members do
		if inLevel(member) or member.stage == "passage" then
			member.stage = "lore"
			member.reviveProgress = 0
			setWalkEnabled(member, true)
			Director.placeMember(member, lore.spawnCFrame)
			-- A lore room is a checkpoint: the next "Continue" starts from the tier after it.
			local profile = profileOf(member)
			profile.checkpointTier = math.max(profile.checkpointTier, nextTier)
			Data.touch(player)
			Telemetry.funnel(player, "LoreRoomReached")
			task.spawn(Data.save, player)
		end
	end
	run.phase = "lore"
	sendStateAll()
	if oldLevel then
		oldLevel.model:Destroy()
	end
end

-- Between places the party walks down a stairwell together. `next` builds the place after it;
-- it runs once someone reaches the bottom (or the time runs out) and everyone is carried on.
function Director.walkPassage(next: () -> ())
	run.phase = "transition"
	run.epoch += 1
	local oldLevel, oldLore = run.level, run.lore
	Enemies.clear()
	local passage = Passage.build(PASSAGE_ORIGIN)
	run.passage = passage
	run.level = nil
	run.lore = nil
	for _, member in members do
		if inLevel(member) or member.stage == "lore" then
			member.stage = "passage"
			member.reviveProgress = 0
			member.respawnCFrame = nil
			member.graceUntil = os.clock() + Config.World.respawnGraceSeconds
			setWalkEnabled(member, true)
			Director.placeMember(member, passage.startCFrame)
		end
	end
	sendStateAll()
	if oldLevel then
		oldLevel.model:Destroy()
	end
	if oldLore then
		oldLore.model:Destroy()
	end

	task.spawn(function()
		local deadline = os.clock() + PASSAGE_MAX_SECONDS
		while run.passage == passage and os.clock() < deadline do
			local anyone, arrived = false, false
			for player, member in members do
				if member.stage == "passage" then
					anyone = true
					local root = rootOf(player)
					if
						root
						and (root.Position - passage.endPosition).Magnitude
							<= PASSAGE_END_RADIUS
					then
						arrived = true
					end
				end
			end
			if not anyone or arrived then
				break
			end
			task.wait(PASSAGE_POLL_SECONDS)
		end
		if run.passage ~= passage then
			return
		end
		for player, member in members do
			if member.stage == "passage" then
				Remotes.send(
					player,
					"Objective",
					"exit",
					{ position = passage.endPosition, by = 0 }
				)
			end
		end
		task.wait(DOORWAY_LEAVE_SECONDS)
		if run.passage ~= passage then
			return
		end
		next()
		run.passage = nil
		passage.model:Destroy()
	end)
end

function completeLevel()
	local level = run.level
	if level == nil then
		return
	end
	local def = level.plan.def
	local tier = run.tier
	local seconds = os.clock() - run.levelStartedAt
	local day = Daily.dayNumber(os.time())
	local nextTier = tier + 1
	if run.mode == "daily" then
		-- After the daily, the party carries on from the furthest checkpoint among them.
		nextTier = 1
		for _, member in members do
			if inLevel(member) then
				nextTier = math.max(nextTier, profileOf(member).checkpointTier)
			end
		end
	end
	local loreRoom = if run.mode == "daily" then "landing" else def.loreRoomAfter

	for player, member in members do
		if inLevel(member) then
			local profile = profileOf(member)
			local reward = Progression.levelReward(def.reward, {
				cells = run.collected.cells,
				rescues = run.collected.rescues,
				plate = run.collected.plate,
				caught = member.caughtThisLevel,
			})
			local total = reward.total
			local dailyBest = 0
			if run.mode == "daily" then
				if profile.daily.day ~= day then
					total += Config.Economy.dailyClearBonus
					profile.daily.bestMs = 0
				end
				profile.daily.day = day
				dailyBest = Leaderboard.submit(player, day, seconds * 1000)
				profile.daily.bestMs = dailyBest
			else
				profile.bestTier = math.max(profile.bestTier, tier)
			end
			profile.stats.levels += 1
			member.sessionLevels += 1
			grant(member, total, "LevelClear")
			Data.touch(player)

			local showInvite = not profile.invitePrompted
			profile.invitePrompted = true
			Telemetry.levelCleared(player, tier, def.name)
			if tier == 1 then
				Telemetry.funnel(player, "LevelOneCleared")
			elseif tier == 3 then
				Telemetry.funnel(player, "LevelThreeCleared")
			end
			Remotes.send(player, "LevelCleared", {
				tier = tier,
				name = def.name,
				mode = run.mode,
				seconds = seconds,
				catches = member.catchesThisLevel,
				reward = reward,
				total = total,
				balance = profile.static,
				loreNext = loreRoom ~= nil,
				invite = showInvite,
				endless = Difficulty.isEndless(nextTier),
			})
			sendProfile(member)
			if run.mode == "daily" then
				Remotes.send(player, "DailyBoard", {
					day = Daily.key(day),
					yourMs = seconds * 1000,
					bestMs = dailyBest,
					rows = Leaderboard.top(day, player),
				})
			end
		end
	end

	Director.walkPassage(function()
		if loreRoom ~= nil then
			enterLore(loreRoom, nextTier)
		else
			beginLevel(nextTier)
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Joining and starting

local function joinRun(member: Member, mode: string)
	local profile = profileOf(member)
	if not run.active then
		run.active = true
		run.mode = if mode == "daily" then "daily" else "run"
		run.seedBase = random:NextInteger(1, SEED_SPAN)
		run.plateFound = false
		run.weeklyShown = false
		profile.stats.runs += 1
		Data.touch(member.player)
		member.stage = "level"
		local tier = if mode == "daily"
			then Config.Daily.tier
			elseif mode == "continue" then profile.checkpointTier
			else 1
		beginLevel(tier)
		return
	end
	-- A run is already going: drop in where the party is.
	if run.phase == "lore" and run.lore then
		member.stage = "lore"
		Director.placeMember(member, run.lore.spawnCFrame)
	elseif run.level then
		member.stage = "level"
		member.caughtThisLevel = false
		member.catchesThisLevel = 0
		member.graceUntil = os.clock() + Config.World.respawnGraceSeconds
		Director.placeMember(member, run.level.startCFrame)
		Telemetry.levelStarted(member.player, run.tier, run.level.plan.def.name)
	end
	toast(member.player, "Joined the survey in progress.", "info")
	sendStateAll()
end

local function leaveTutorial(member: Member)
	local tutorial = member.tutorial
	member.tutorial = nil
	local profile = profileOf(member)
	profile.tutorialDone = true
	Data.touch(member.player)
	Telemetry.funnel(member.player, "TutorialComplete")
	joinRun(member, "new")
	if tutorial then
		tutorial.model:Destroy()
	end
end

local function startTutorial(member: Member)
	local base = Vector3.new(table.unpack(Config.World.tutorialOrigin))
	local tutorial =
		TutorialRoom.build(base + Vector3.new(member.slot * Config.World.tutorialSpacing, 0, 0))
	member.tutorial = tutorial
	member.stage = "tutorial"
	local used = false
	tutorial.exitPrompt.Triggered:Connect(function(player: Player)
		if
			used
			or player ~= member.player
			or member.stage ~= "tutorial"
			or not nearEnough(player, tutorial.exitDoor)
		then
			return
		end
		used = true
		leaveTutorial(member)
	end)
	Director.placeMember(member, tutorial.spawnCFrame)
	sendState(member)
end

local function onStart(player: Player, mode: string)
	local member = members[player]
	if member == nil or member.stage ~= "title" or member.starting then
		return
	end
	member.starting = true
	Telemetry.funnel(player, "PressedPlay")
	while run.phase == "transition" do
		task.wait(TRANSITION_POLL_SECONDS) -- a level is being built: join once it is ready
	end
	if members[player] ~= member then
		return
	end
	if Party.isLobby() then
		Party.launch(Players:GetPlayers())
		return
	end
	if not profileOf(member).tutorialDone then
		startTutorial(member)
	else
		joinRun(member, mode)
	end
end

local function freeSlot(): number
	local used: { [number]: boolean } = {}
	for _, member in members do
		used[member.slot] = true
	end
	for slot = 1, Config.Coop.maxPlayers do
		if not used[slot] then
			return slot
		end
	end
	return 1
end

local function onPlayerAdded(player: Player)
	local profile, persistent = Data.load(player)
	if not player:IsDescendantOf(Players) then
		return
	end
	local member: Member = {
		player = player,
		stage = "title",
		starting = false,
		slot = freeSlot(),
		scanFiring = false,
		scanSweeping = false,
		crouching = false,
		scanLook = Vector3.new(0, 0, -1),
		scanAt = 0,
		graceUntil = 0,
		caughtThisLevel = false,
		catchesThisLevel = 0,
		reviveProgress = 0,
		respawnCFrame = nil,
		tutorial = nil,
		lastPosition = nil,
		lastPingAt = 0,
		ownsKit = false,
		effects = Progression.effects(profile),
		sessionStatic = 0,
		sessionLevels = 0,
		sessionCatches = 0,
		sessionLore = 0,
		sessionDistance = 0,
		endingOffered = false,
	}
	members[player] = member
	Telemetry.funnel(player, "Joined")

	local streakBonus = Progression.applyStreak(profile, Daily.dayNumber(os.time()))
	if streakBonus > 0 then
		grant(member, streakBonus, "Streak")
	end
	sendProfile(member)
	sendState(member)
	if streakBonus > 0 then
		toast(player, `Visit {profile.streak.count}: +{streakBonus} Static.`, "good")
	end
	if not persistent then
		toast(
			player,
			"Saving is unavailable right now. Progress this session will not be kept.",
			"warn"
		)
	end

	if Config.Monetization.surveyorKitPassId ~= 0 then
		task.spawn(function()
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(
					player.UserId,
					Config.Monetization.surveyorKitPassId
				)
			end)
			if ok and owns and members[player] == member then
				member.ownsKit = true
				sendProfile(member)
			end
		end)
	end
end

local function endRunIfEmpty()
	for _, member in members do
		if member.stage ~= "title" and member.stage ~= "tutorial" then
			return
		end
	end
	Enemies.clear()
	if run.level then
		run.level.model:Destroy()
	end
	if run.lore then
		run.lore.model:Destroy()
	end
	if run.passage then
		run.passage.model:Destroy()
		run.passage = nil
	end
	run.level = nil
	run.lore = nil
	run.active = false
	run.phase = "idle"
	run.respawning = false
	run.epoch += 1
end

local function onPlayerRemoving(player: Player)
	local member = members[player]
	if member == nil then
		return
	end
	members[player] = nil
	Telemetry.custom(player, "QuitAtTier", if member.stage == "title" then 0 else run.tier)
	Telemetry.forget(player)
	if member.tutorial then
		member.tutorial.model:Destroy()
	end
	Data.release(player)
	if member.stage == "level" and countStage("level") == 0 and countStage("downed") > 0 then
		respawnParty() -- the last standing player left: do not strand the downed ones
	end
	endRunIfEmpty()
	sendStateAll()
end

--------------------------------------------------------------------------------------------
-- Remotes

local function onScanState(
	player: Player,
	firing: boolean,
	sweeping: boolean,
	crouching: boolean,
	look: Vector3,
	origin: Vector3,
	spread: number
)
	local member = members[player]
	local root = rootOf(player)
	if member == nil or root == nil or look.Magnitude < 0.5 then
		return
	end
	local standing = member.stage ~= "downed"
	member.scanFiring = firing and standing
	member.scanSweeping = sweeping and standing
	member.crouching = crouching
	member.scanLook = look.Unit
	member.scanAt = os.clock()
	-- Teammates redraw each other's dots; never relay a position far from the body.
	if (origin - root.Position).Magnitude > Config.Coop.reviveDistance then
		origin = root.Position
	end
	for otherPlayer, other in members do
		if otherPlayer ~= player and inLevel(other) and inLevel(member) then
			Remotes.send(
				otherPlayer,
				"ScanRelay",
				player.UserId,
				member.scanFiring,
				member.scanSweeping,
				member.scanLook,
				origin,
				spread
			)
		end
	end
end

local function onPing(player: Player, position: Vector3)
	local member = members[player]
	local root = rootOf(player)
	local level = run.level
	local now = os.clock()
	if
		member == nil
		or root == nil
		or member.stage ~= "level"
		or now - member.lastPingAt < Config.Coop.pingCooldown
		or (position - root.Position).Magnitude > Config.Lidar.maxRange + PROMPT_SLACK
	then
		return
	end
	member.lastPingAt = now
	for otherPlayer, other in members do
		if inLevel(other) then
			Remotes.send(
				otherPlayer,
				"PingMarker",
				player.UserId,
				position,
				member.effects.pingLifetime
			)
		end
	end
	if member.effects.decoy and level ~= nil then
		local relative = (position - level.origin) / CELL
		table.insert(run.decoys, {
			x = relative.X,
			z = relative.Z,
			noise = Config.Noise.ping,
			expires = now + Config.Noise.pingSeconds,
		})
	end
end

-- A client says it has put enough dots on a hidden recorder. The scanning itself cannot be
-- checked here (dots are local), so the only test is that the player could plausibly reach it.
local function onReveal(player: Player, echoId: number)
	local member = members[player]
	local root = rootOf(player)
	local level = run.level
	-- A dark haven has one beacon: scanned enough, it lights the room for everyone inside.
	local beacon = if run.lore ~= nil then run.lore.beacon else nil
	if
		member ~= nil
		and root ~= nil
		and member.stage == "lore"
		and beacon ~= nil
		and echoId == beacon.id
	then
		if
			not beacon.revealed
			and (beacon.position - root.Position).Magnitude
				<= Config.Lidar.maxRange + Config.Lidar.lightReach + PROMPT_SLACK
		then
			beacon.reveal()
			for otherPlayer, other in members do
				if other.stage == "lore" then
					Remotes.send(
						otherPlayer,
						"Echo",
						beacon.id,
						beacon.position,
						beacon.title,
						beacon.subtitle
					)
				end
			end
		end
		return
	end
	if member == nil or root == nil or level == nil or member.stage ~= "level" then
		return
	end
	local echo = level.echoes[echoId]
	if
		echo == nil
		or echo.revealed
		or (echo.position - root.Position).Magnitude
			> Config.Lidar.maxRange + Config.Lidar.lightReach + PROMPT_SLACK
	then
		return
	end
	World.revealEcho(level, echo)
	local counted = echo.kind == "recorder" or echo.kind == "reveal"
	if counted then
		run.collected.echoes += 1
		Telemetry.custom(player, "EchoRevealed", run.tier)
	end
	-- Everyone in the level hears it. A recorder plays each player's own next tape, so the
	-- story stays in order for each; every other hidden thing says its own few lines.
	local own = table.concat(echo.lines, " ")
	for otherPlayer, other in members do
		if inLevel(other) then
			local speaker, line = "", own
			if echo.kind == "recorder" then
				local profile = profileOf(other)
				local tape = Lore.echoes[profile.echoes % #Lore.echoes + 1]
				profile.echoes += 1
				speaker = if tape.speaker ~= "" then tape.speaker else Lore.echoSpeaker
				line = tape.line
			end
			if counted then
				other.sessionLore += 1
				grant(other, Config.Economy.echoBonus, "Echo")
				sendProfile(other)
			end
			Remotes.send(
				otherPlayer,
				"Echo",
				echo.id,
				echo.position,
				speaker,
				line,
				echo.thought or ""
			)
		end
	end
	sendStateAll()
end

local function onEmote(player: Player, index: number)
	local member = members[player]
	if member == nil or member.stage == "title" then
		return
	end
	for otherPlayer, other in members do
		if other.stage ~= "title" then
			Remotes.send(otherPlayer, "EmoteShown", player.UserId, index)
		end
	end
end

local function onBuyUpgrade(player: Player, id: string)
	local member = members[player]
	if member == nil or member.stage ~= "lore" then
		return
	end
	local profile = profileOf(member)
	local cost = Progression.cost(profile, id)
	local ok, message = Progression.buyUpgrade(profile, id)
	if ok and cost ~= nil then
		Data.touch(player)
		Telemetry.spent(player, cost, profile.static, id)
		sendProfile(member)
	end
	toast(player, message, if ok then "good" else "warn")
end

local function onEquipCosmetic(player: Player, slot: string, id: string)
	local member = members[player]
	if member == nil or member.stage ~= "lore" then
		return
	end
	local profile = profileOf(member)
	local before = profile.static
	local ok, message = Progression.equipCosmetic(profile, slot, id)
	if ok then
		Data.touch(player)
		if profile.static < before then
			Telemetry.spent(player, before - profile.static, profile.static, id)
		end
		sendProfile(member)
	end
	toast(player, message, if ok then "good" else "warn")
end

local function onToggleUpgrade(player: Player, id: string, on: boolean)
	local member = members[player]
	if
		member ~= nil
		and Upgrades.byId[id] ~= nil
		and Progression.setToggle(profileOf(member), id, on)
	then
		Data.touch(player)
		sendProfile(member)
	end
end

local function onSetSetting(player: Player, key: string, value: any)
	local member = members[player]
	local check = SETTINGS[key]
	if member == nil or check == nil or not check(value) then
		return
	end
	local settings = profileOf(member).settings :: { [string]: any }
	settings[key] = value
	Data.touch(player)
end

-- The finale's choice, answered once. "stay" keeps the lamp: the Lamp Room's door leads on
-- into the Relay, as it always has. "up" climbs the ladder: this player's run ends and they
-- return to the title. Their checkpoint is kept, so they can go back down when they like.
local function onChoose(player: Player, choice: string)
	local member = members[player]
	local lore = run.lore
	if
		member == nil
		or not member.endingOffered
		or member.stage ~= "lore"
		or lore == nil
		or lore.room.id ~= "stairwell"
	then
		return
	end
	member.endingOffered = false
	Telemetry.custom(player, if choice == "up" then "EndingUp" else "EndingStay", run.tier)
	if choice ~= "up" then
		return
	end
	member.stage = "title"
	member.starting = false
	member.reviveProgress = 0
	member.respawnCFrame = nil
	run.epoch += 1
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
	task.spawn(Data.save, player)
	endRunIfEmpty()
	sendStateAll()
end

local function onFunnel(player: Player, step: string)
	-- The only step the server cannot observe for itself.
	if step == "TutorialFirstScan" and members[player] ~= nil then
		Telemetry.funnel(player, step)
	end
end

--------------------------------------------------------------------------------------------
-- Periodic logic

local function tickMembers()
	local level = run.level
	for player, member in members do
		local root = rootOf(player)
		if root ~= nil and member.stage ~= "title" then
			local last = member.lastPosition
			if last ~= nil then
				local moved = (root.Position - last) * Vector3.new(1, 0, 1)
				if moved.Magnitude <= MAX_STEP_DISTANCE then
					member.sessionDistance += moved.Magnitude
					local stats = profileOf(member).stats
					stats.distance = math.floor(stats.distance + moved.Magnitude)
				end
			end
			member.lastPosition = root.Position
			if
				level ~= nil
				and member.ownsKit
				and member.stage == "level"
				and member.respawnCFrame == nil
				and (root.Position - level.beaconPosition).Magnitude <= BEACON_RADIUS
			then
				member.respawnCFrame = CFrame.new(level.beaconPosition)
				toast(player, "Checkpoint beacon set.", "good")
			end
		end
	end
end

-- Pits and alarm plates. Checked every frame: a sprinting player crosses a plate in a few.
local function tickHazards()
	local level = run.level
	if level == nil or run.phase ~= "level" then
		return
	end
	local now = os.clock()
	local function alarm(
		kind: string,
		position: Vector3,
		userId: number,
		noise: number,
		seconds: number
	)
		local relative = (position - level.origin) / CELL
		table.insert(
			run.decoys,
			{ x = relative.X, z = relative.Z, noise = noise, expires = now + seconds }
		)
		for otherPlayer, other in members do
			if inLevel(other) then
				Remotes.send(otherPlayer, "Hazard", kind, position, userId)
			end
		end
	end
	for player, member in members do
		local root = rootOf(player)
		if member.stage ~= "level" or root == nil then
			continue
		end
		local position = root.Position
		if position.Y < level.origin.Y - Config.World.pitFallDepth then
			alarm(
				"pit",
				position,
				player.UserId,
				Config.World.pitNoise,
				Config.World.pitNoiseSeconds
			)
			member.graceUntil = now + Config.World.respawnGraceSeconds
			Director.placeMember(member, member.respawnCFrame or level.startCFrame)
			toast(player, "The floor was not there. Back to the start of the level.", "warn")
			continue
		end
		for _, plate in level.plates do
			local offset = position - plate.position
			if
				now >= plate.rearmAt
				and offset.Y < PLATE_REACH
				and Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.World.plateRadius
			then
				plate.rearmAt = now + Config.World.plateRearmSeconds
				alarm(
					"plate",
					plate.position,
					player.UserId,
					Config.Noise.plate,
					Config.Noise.plateSeconds
				)
				toastStage("Alarm plate. Everything heard that.", "warn", "level", "downed")
			end
		end
	end
end

--------------------------------------------------------------------------------------------
-- Playtest shortcuts. Only server/Dev calls these, and only in Studio.

Director.dev = {}

local function devPullEveryoneIn()
	for _, member in members do
		if member.tutorial then
			member.tutorial.model:Destroy()
			member.tutorial = nil
		end
		profileOf(member).tutorialDone = true
		if member.stage == "title" or member.stage == "tutorial" then
			member.stage = "level"
		end
	end
	if not run.active then
		run.active = true
		run.mode = "run"
		run.seedBase = random:NextInteger(1, SEED_SPAN)
		run.plateFound = false
		run.weeklyShown = false
	end
end

function Director.dev.jumpToTier(tier: number)
	if run.phase ~= "transition" then
		devPullEveryoneIn()
		beginLevel(tier)
	end
end

function Director.dev.enterLore(roomId: string)
	if run.phase ~= "transition" and Lore.rooms[roomId] ~= nil then
		devPullEveryoneIn()
		for _, member in members do
			member.stage = "level"
		end
		enterLore(roomId, run.tier + 1)
	end
end

function Director.dev.clearLevel()
	if run.phase == "level" then
		completeLevel()
	end
end

-- Reveals the next hidden recorder as if the first player in the level had scanned it.
function Director.dev.revealEcho()
	local level = run.level
	if level == nil then
		return
	end
	for player, member in members do
		if member.stage == "level" then
			for _, echo in level.echoes do
				if not echo.revealed then
					Director.placeMember(member, CFrame.new(echo.position + Vector3.new(0, 3, 0)))
					onReveal(player, echo.id)
					return
				end
			end
		end
	end
end

function Director.dev.grant(amount: number)
	for _, member in members do
		grant(member, amount, "Dev")
		sendProfile(member)
	end
end

function Director.start()
	Players.CharacterAutoLoads = false

	Remotes.on("Start", onStart)
	Remotes.on("ScanState", onScanState)
	Remotes.on("Ping", onPing)
	Remotes.on("Reveal", onReveal)
	Remotes.on("Emote", onEmote)
	Remotes.on("BuyUpgrade", onBuyUpgrade)
	Remotes.on("EquipCosmetic", onEquipCosmetic)
	Remotes.on("ToggleUpgrade", onToggleUpgrade)
	Remotes.on("SetSetting", onSetSetting)
	Remotes.on("Funnel", onFunnel)
	Remotes.on("Choose", onChoose)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local accumulator = 0
	local interval = 1 / LOGIC_HZ
	RunService.Heartbeat:Connect(function(dt: number)
		tickHazards()
		accumulator += dt
		if accumulator >= interval then
			tickRevives(accumulator)
			tickMembers()
			accumulator = 0
		end
	end)
end

return Director
