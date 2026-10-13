--!strict
-- The LIDAR gun. While the trigger is held it scatters rays inside a cone around the
-- crosshair; every hit becomes a dot (see Dots). Holding focus narrows the cone and raises
-- the rate, at the cost of heat. All of this is local: the server is only told whether the
-- scanner is on and where it points, which is what enemies react to.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DotRules = require(ReplicatedStorage.Shared.pure.DotRules)
local Dots = require(script.Parent.Dots)
local Input = require(script.Parent.Input)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

type Classified = { class: DotRules.DotClass, late: boolean, water: boolean, at: number }
type Teammate = {
	firing: boolean,
	focusing: boolean,
	look: Vector3,
	origin: Vector3,
	at: number,
	accumulator: number,
	params: RaycastParams,
}
type BatchListener = (
	count: number,
	meanDistance: number,
	enemy: boolean,
	friend: boolean,
	objective: boolean
) -> ()

local lidar = Config.Lidar
local CELL = Config.World.cellSize
local CLASS_CACHE_SECONDS = 0.4 -- tags are re-read this often (a Mimic's disguise can drop)
local SURFACE_OFFSET = 0.04 -- dots sit just proud of the surface
local WATER_SIZE = 0.6
local WATER_LIFE = 0.5
local WIDE_LENS_RATE = 1.25
local FOCUS_REARM_HEAT = 0.35 -- after an overheat, focus returns once heat falls to this
local RELAY_STALE_SECONDS = 0.5
local MAX_RAYS_PER_FRAME = 40
local BEAM_SECONDS = 0.09
local BEAM_WIDTH = 0.02
local MUZZLE_OFFSET = CFrame.new(0.5, -0.45, -1.72) -- matches the view model's emitter dish
local SCAN_CELL_HITS = 3 -- dots needed in a cell before the map counts it as scanned

local Lidar = {}

Lidar.heat = 0
Lidar.overheated = false
Lidar.firing = false -- true while dots are actually being produced
Lidar.focusing = false
Lidar.enabled = false -- controllers switch the gun off on the title screen and in menus

local player = Players.LocalPlayer
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local ignore: { Instance } = {}
local classCache: { [Instance]: Classified } = setmetatable({}, { __mode = "k" }) :: any
local accumulator = 0
local reportTimer = 0
local teammates: { [number]: Teammate } = {}
local batchListeners: { BatchListener } = {}
local cellHits: { [number]: number } = {}
local beams: { Beam } = {}
local beamBorn: { number } = {}
local nextBeam = 1
local beamFolder = Instance.new("Folder")
beamFolder.Name = "LidarBeams"
local beamAnchor = Instance.new("Part") -- holds the beams' attachments; never seen or hit
beamAnchor.Name = "Anchor"
beamAnchor.Anchored = true
beamAnchor.CanCollide = false
beamAnchor.CanQuery = false
beamAnchor.CanTouch = false
beamAnchor.Transparency = 1
beamAnchor.Size = Vector3.one
beamAnchor.Parent = beamFolder

local scanRemote = Net.get("ScanState") :: UnreliableRemoteEvent

-- Things the scanner must never hit: add local-only props here (view model, markers).
function Lidar.ignore(instance: Instance)
	table.insert(ignore, instance)
end

-- Called once per frame that produced dots, for the scan audio.
function Lidar.onBatch(listener: BatchListener)
	table.insert(batchListeners, listener)
end

-- A battery cell cools the scanner instantly.
function Lidar.cool()
	Lidar.heat = 0
	Lidar.overheated = false
end

local function classify(instance: Instance, now: number): Classified
	local cached = classCache[instance]
	if cached ~= nil and now - cached.at < CLASS_CACHE_SECONDS then
		return cached
	end
	local tags: { [string]: boolean } = {}
	local node: Instance? = instance
	while node ~= nil and node ~= workspace do
		for _, tag in CollectionService:GetTags(node) do
			tags[tag] = true
		end
		node = node.Parent
	end
	local class, late = DotRules.classify(tags)
	local result =
		{ class = class, late = late, water = instance:GetAttribute("Flooded") == true, at = now }
	classCache[instance] = result
	return result
end

local function coneDirection(look: CFrame, halfAngleDeg: number): Vector3
	-- sqrt keeps the scatter uniform over the cone's cross-section rather than bunched at the centre.
	local theta = math.rad(halfAngleDeg) * math.sqrt(math.random())
	local phi = math.random() * math.pi * 2
	return (look * CFrame.Angles(0, 0, phi) * CFrame.Angles(theta, 0, 0)).LookVector
end

-- A faint trace from the muzzle to a fresh dot. Beams are additive and camera-facing, so
-- they read as light rather than geometry.
local function showBeam(from: Vector3, to: Vector3, color: Color3, now: number)
	local beam = beams[nextBeam]
	if beam == nil then
		beam = Instance.new("Beam")
		beam.Attachment0 = Instance.new("Attachment")
		beam.Attachment1 = Instance.new("Attachment");
		(beam.Attachment0 :: Attachment).Parent = beamAnchor;
		(beam.Attachment1 :: Attachment).Parent = beamAnchor
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = BEAM_WIDTH
		beam.Width1 = BEAM_WIDTH * 2
		beam.Parent = beamAnchor
		beams[nextBeam] = beam
	end
	(beam.Attachment0 :: Attachment).WorldPosition = from;
	(beam.Attachment1 :: Attachment).WorldPosition = to
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(lidar.beamTransparency)
	beam.Enabled = true
	beamBorn[nextBeam] = now
	nextBeam = nextBeam % lidar.beamCount + 1
end

local function markScanned(position: Vector3, instance: Instance)
	local plan = State.plan
	if plan == nil or not State.inLevel() then
		return
	end
	local relative = (position - State.server.origin) / CELL
	if
		relative.X >= 0
		and relative.Z >= 0
		and relative.X < plan.maze.width
		and relative.Z < plan.maze.height
	then
		local cell = Maze.cellOf(plan.maze, relative.X, relative.Z)
		local index = Maze.index(plan.maze, cell.x, cell.y)
		local hits = (cellHits[index] or 0) + 1
		cellHits[index] = hits
		if hits == SCAN_CELL_HITS then
			State.scannedCells[index] = true
		end
	end
	if not State.exitScanned and instance.Name == "ExitDoor" then
		State.exitScanned = true
	end
end

-- Fires `count` rays from `look` and lands their dots. Returns batch statistics.
local function scan(
	look: CFrame,
	count: number,
	halfAngle: number,
	params: RaycastParams,
	now: number,
	muzzle: Vector3?
)
	local hits, distanceSum = 0, 0
	local sawEnemy, sawFriend, sawObjective = false, false, false
	local lifetimeMul = State.effects.lifetimeMul
	for _ = 1, count do
		local direction = coneDirection(look, halfAngle)
		local result = workspace:Raycast(look.Position, direction * lidar.maxRange, params)
		if result then
			local info = classify(result.Instance, now)
			local position = result.Position + result.Normal * SURFACE_OFFSET
			local distance = result.Distance
			if info.late then
				Dots.spawnLate(position, info.class, distance, lifetimeMul, lidar.mimicDotDelay)
			elseif info.water then
				Dots.spawn(position, info.class, distance, lifetimeMul * WATER_LIFE, WATER_SIZE)
			else
				Dots.spawn(position, info.class, distance, lifetimeMul, 1)
			end
			hits += 1
			distanceSum += distance
			sawEnemy = sawEnemy or (info.class == "enemy")
			sawFriend = sawFriend or (info.class == "friend" and not info.late)
			sawObjective = sawObjective or info.class == "objective"
			if muzzle ~= nil then
				markScanned(position, result.Instance)
				if hits <= lidar.beamCount then
					showBeam(muzzle, position, Dots.color(info.class), now)
				end
			end
		end
	end
	return hits, distanceSum, sawEnemy, sawFriend, sawObjective
end

local function refreshFilter()
	local list = table.clone(ignore)
	table.insert(list, Dots.folder())
	table.insert(list, beamFolder)
	if player.Character then
		table.insert(list, player.Character)
	end
	raycastParams.FilterDescendantsInstances = list
end

local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end

	for index, beam in beams do
		if beam.Enabled then
			local age = (now - beamBorn[index]) / BEAM_SECONDS
			if age >= 1 then
				beam.Enabled = false
			else
				beam.Transparency =
					NumberSequence.new(lidar.beamTransparency + (1 - lidar.beamTransparency) * age)
			end
		end
	end

	local stage = State.server.stage
	local canFire = Lidar.enabled
		and not State.menuOpen
		and (stage == "tutorial" or stage == "level" or stage == "lore")
	local firing = canFire and Input.firing
	local wantsFocus = firing and Input.focusing
	if Lidar.overheated and Lidar.heat <= FOCUS_REARM_HEAT then
		Lidar.overheated = false
	end
	local focusing = wantsFocus and not Lidar.overheated

	-- Heat: only focus costs anything, so the gun is never a free wallhack but never useless.
	local effects = State.effects
	local heatRate = lidar.heatPerSecondFocus * effects.heatRateMul * State.server.heatScale
	Lidar.heat =
		DotRules.stepHeat(Lidar.heat, focusing, dt, heatRate, lidar.coolPerSecond * effects.coolMul)
	if Lidar.heat >= 1 then
		Lidar.overheated = true
		focusing = false
	end
	Lidar.firing = firing
	Lidar.focusing = focusing

	-- Tell the server what enemies need to know, a few times a second.
	reportTimer -= dt
	if reportTimer <= 0 and stage ~= "title" then
		reportTimer = 1 / lidar.scanStateHz
		scanRemote:FireServer(firing, focusing, camera.CFrame.LookVector, camera.CFrame.Position)
	end

	refreshFilter()

	if firing then
		local rate = if focusing then lidar.focusDotsPerSecond else lidar.dotsPerSecond
		local halfAngle = if focusing then lidar.focusConeHalfAngleDeg else lidar.coneHalfAngleDeg
		if effects.wideLens and not focusing then
			halfAngle *= effects.coneMul
			rate *= WIDE_LENS_RATE
		end
		accumulator += rate * dt
		local count = math.min(math.floor(accumulator), MAX_RAYS_PER_FRAME)
		accumulator -= math.floor(accumulator)
		if count > 0 then
			local muzzle = (camera.CFrame * MUZZLE_OFFSET).Position
			local hits, distanceSum, enemy, friend, objective =
				scan(camera.CFrame, count, halfAngle, raycastParams, now, muzzle)
			if hits > 0 then
				for _, listener in batchListeners do
					listener(hits, distanceSum / hits, enemy, friend, objective)
				end
			end
		end
	else
		accumulator = 0
	end

	-- Teammates' scanners: draw a share of their dots so friends can see each other working.
	local spectating = stage == "downed"
	if State.inLevel() and (spectating or State.profile.settings.sharedScans) then
		local share = if spectating then 1 else lidar.sharedScanRate
		for _, mate in teammates do
			if mate.firing and now - mate.at < RELAY_STALE_SECONDS then
				local rate = if mate.focusing then lidar.focusDotsPerSecond else lidar.dotsPerSecond
				local halfAngle = if mate.focusing
					then lidar.focusConeHalfAngleDeg
					else lidar.coneHalfAngleDeg
				mate.accumulator += rate * share * dt
				local count = math.min(math.floor(mate.accumulator), MAX_RAYS_PER_FRAME)
				mate.accumulator -= math.floor(mate.accumulator)
				if count > 0 then
					scan(
						CFrame.lookAt(mate.origin, mate.origin + mate.look),
						count,
						halfAngle,
						mate.params,
						now,
						nil
					)
				end
			end
		end
	end
end

local function onRelay(
	userId: number,
	firing: boolean,
	focusing: boolean,
	look: Vector3,
	origin: Vector3
)
	local mate = teammates[userId]
	if mate == nil then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		mate = {
			firing = false,
			focusing = false,
			look = look,
			origin = origin,
			at = 0,
			accumulator = 0,
			params = params,
		}
		teammates[userId] = mate
	end
	mate.firing = firing
	mate.focusing = focusing
	mate.look = look
	mate.origin = origin
	mate.at = os.clock()
	-- Their rays start inside their own head: never let them hit their own body.
	local owner = Players:GetPlayerByUserId(userId)
	local list: { Instance } = { Dots.folder(), beamFolder }
	if owner and owner.Character then
		table.insert(list, owner.Character)
	end
	mate.params.FilterDescendantsInstances = list
end

-- Fires rays from an arbitrary point and lands their dots, with no heat, beams or reporting.
-- The title screen uses this to scan its own little scene.
function Lidar.sweep(look: CFrame, count: number, halfAngle: number, params: RaycastParams)
	scan(look, count, halfAngle, params, os.clock(), nil)
end

function Lidar.start()
	beamFolder.Parent = workspace
	RunService:BindToRenderStep("LidarGun", Enum.RenderPriority.Camera.Value + 1, step);
	(Net.get("ScanRelay") :: UnreliableRemoteEvent).OnClientEvent:Connect(onRelay)
	Players.PlayerRemoving:Connect(function(leaving: Player)
		teammates[leaving.UserId] = nil
	end)
	State.onLevel(function()
		table.clear(cellHits)
		Lidar.cool()
	end)
end

return Lidar
