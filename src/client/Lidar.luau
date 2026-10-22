--!strict
-- The LIDAR gun.
--  * Holding the trigger scatters a fast stream of rays inside a cone round the crosshair;
--    every hit lands a dot (see Dots). The cone's spread can be narrowed or widened.
--  * The sweep sends one line of rays from the top of the view to the bottom and draws a
--    whole grid at once. It is loud to anything that listens, and then has to recharge.
--  * With the Pulse Radar upgrade a ring of rays turns once round the player every few
--    seconds on its own.
-- All of it is local. The server is only told what monsters react to: whether the gun is
-- on, whether a sweep is running, where it points. Teammates' guns are redrawn here from
-- the same few numbers, so everyone sees everyone's dots without a single dot being sent.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Avatar = require(script.Parent.Avatar)
local Config = require(ReplicatedStorage.Shared.Config)
local DotRules = require(ReplicatedStorage.Shared.pure.DotRules)
local Dots = require(script.Parent.Dots)
local Input = require(script.Parent.Input)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)

type Target = {
	tags: { [string]: boolean },
	echoId: number?,
	light: boolean, -- a lamp or beacon: it wakes after a couple of dots
	exit: boolean,
	at: number,
}
type Stats = {
	hits: number,
	distance: number,
	enemy: boolean,
	friend: boolean,
	objective: boolean,
}
type BeamPool = { beams: { Beam }, born: { number }, next: number, size: number }
type Run = { index: number, rows: number, columns: number } -- a sweep in progress
type Teammate = {
	firing: boolean,
	sweeping: boolean,
	look: Vector3,
	origin: Vector3,
	spread: number,
	at: number,
	accumulator: number,
	params: RaycastParams,
	run: Run?,
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
local TARGET_CACHE_SECONDS = 0.4 -- tags are re-read this often (a Mimic's disguise can drop)
local SURFACE_OFFSET = 0.04 -- dots sit just proud of the surface
local RELAY_STALE_SECONDS = 0.5
local MAX_SCATTER_PER_FRAME = 150
local MAX_SWEEP_PER_FRAME = 400 -- a slow frame stretches the sweep rather than stalling on it
local SWEEP_JITTER = 0.15 -- of one grid step, so two sweeps never trace the exact same grid
local SWEEP_BEAM_EVERY = 3 -- one laser line for every few sweep rays
local RADAR_TURN_SECONDS = 0.5 -- the radar pulse takes this long to go once round
local BEAM_WIDTH = 0.02
local MUZZLE_OFFSET = CFrame.new(0.5, -0.45, -1.72) -- matches the view model's emitter dish
local TEAMMATE_MUZZLE = CFrame.new(0.6, -0.6, -1.4) -- roughly where a teammate holds theirs
local SCAN_CELL_HITS = 3 -- dots needed in a cell before the map counts it as scanned
local ECHO_LINGER_SECONDS = 1 -- recorder progress stays on screen this long after the last hit
local REVEAL_RETRY_SECONDS = 2
local SPARK_CHANCE = 0.03 -- share of the local scan's dots that flare as they land
local SPARK_SIZE = 2.6
local SPARK_SECONDS = 0.3
local EXIT_NAME = "ExitDoor"
local ECHO_ATTRIBUTE = "EchoId"
local LIGHT_ATTRIBUTE = "Light" -- set on lamps and beacons: they wake after a short scan
local LIGHT_REFRESH_SECONDS = 2
local LIGHT_CLEARANCE = 1.2 -- studs: a sight line to a lamp stops this far short of it

local Lidar = {}

Lidar.enabled = false -- controllers switch the gun off on the title screen
Lidar.firing = false -- the scatter stream is producing dots this frame
Lidar.sweeping = false -- a sweep is travelling down the view right now
Lidar.charge = 1 -- 0..1; the sweep can fire at 1
Lidar.spread = lidar.coneHalfAngleDeg -- cone half-angle in degrees
Lidar.echoProgress = 0 -- 0..1 progress on the hidden recorder being scanned

local player = Players.LocalPlayer
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local throughParams = RaycastParams.new() -- as above, but monsters do not stop the ray
throughParams.FilterType = Enum.RaycastFilterType.Exclude
local ignore: { Instance } = {}
local targetCache: { [Instance]: Target } = setmetatable({}, { __mode = "k" }) :: any
local accumulator = 0
local reportTimer = 0
local ownRun: Run? = nil
local radarTimer = 0
local radarRemaining = 0
local radarYaw = 0
local teammates: { [number]: Teammate } = {}
local batchListeners: { BatchListener } = {}
local poiListeners: { (position: Vector3) -> () } = {}
local hitListeners: { (position: Vector3) -> () } = {}
local seenListeners: { (instance: BasePart) -> () } = {}
local sweepListeners: { () -> () } = {}
local radarListeners: { () -> () } = {}
local cellHits: { [number]: number } = {}
local echoHits: { [number]: number } = {}
local echoAskedAt: { [number]: number } = {}
local echoSeenAt = 0
local lightSpots: { [number]: Vector3 } = {} -- unrevealed lamps and beacons, by echo id
local lightsCheckedAt = 0

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
local ownBeams: BeamPool = { beams = {}, born = {}, next = 1, size = lidar.beamCount }
local mateBeams: BeamPool = { beams = {}, born = {}, next = 1, size = lidar.teammateBeams }

local scanRemote = Net.get("ScanState") :: UnreliableRemoteEvent
local revealRemote = Net.get("Reveal") :: RemoteEvent

-- Things the scanner must never hit: add local-only props here (view model, markers).
function Lidar.ignore(instance: Instance)
	table.insert(ignore, instance)
end

-- Called once per frame that produced dots, for the scan audio.
function Lidar.onBatch(listener: BatchListener)
	table.insert(batchListeners, listener)
end

-- Called with the spot of every point of interest (an item, the exit) the local gun lands a
-- dot on.
function Lidar.onPoi(listener: (position: Vector3) -> ())
	table.insert(poiListeners, listener)
end

-- Called with the position of every dot the local gun lands.
function Lidar.onHit(listener: (position: Vector3) -> ())
	table.insert(hitListeners, listener)
end

-- Called with every part the local gun's rays land on.
function Lidar.onSeen(listener: (instance: BasePart) -> ())
	table.insert(seenListeners, listener)
end

-- Called when the local player's sweep fires.
function Lidar.onSweep(listener: () -> ())
	table.insert(sweepListeners, listener)
end

-- Called when the Pulse Radar fires.
function Lidar.onRadar(listener: () -> ())
	table.insert(radarListeners, listener)
end

-- A battery cell: the sweep is ready now.
function Lidar.recharge()
	Lidar.charge = 1
end

local function describe(instance: Instance, now: number): Target
	local cached = targetCache[instance]
	if cached ~= nil and now - cached.at < TARGET_CACHE_SECONDS then
		return cached
	end
	local tags: { [string]: boolean } = {}
	local echoId: number? = nil
	local light = false
	local node: Instance? = instance
	while node ~= nil and node ~= workspace do
		for _, tag in CollectionService:GetTags(node) do
			tags[tag] = true
		end
		local id = node:GetAttribute(ECHO_ATTRIBUTE)
		if type(id) == "number" then
			echoId = id
		end
		if node:GetAttribute(LIGHT_ATTRIBUTE) == true then
			light = true
		end
		node = node.Parent
	end
	local target = {
		tags = tags,
		echoId = if tags[Config.Tags.echo] then echoId else nil,
		light = light,
		exit = instance.Name == EXIT_NAME,
		at = now,
	}
	targetCache[instance] = target
	return target
end

-- A thin trace from the gun to a fresh dot. Beams are additive and camera-facing, so they
-- read as light rather than geometry.
local function showBeam(pool: BeamPool, from: Vector3, to: Vector3, color: Color3, now: number)
	local index = pool.next
	pool.next = index % pool.size + 1
	local beam = pool.beams[index]
	if beam == nil then
		beam = Instance.new("Beam")
		local a0 = Instance.new("Attachment")
		local a1 = Instance.new("Attachment")
		a0.Parent = beamAnchor
		a1.Parent = beamAnchor
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = BEAM_WIDTH
		beam.Width1 = BEAM_WIDTH * 2
		beam.Parent = beamAnchor
		pool.beams[index] = beam
	end
	(beam.Attachment0 :: Attachment).WorldPosition = from;
	(beam.Attachment1 :: Attachment).WorldPosition = to
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(lidar.beamTransparency)
	beam.Enabled = true
	pool.born[index] = now
end

local function fadeBeams(pool: BeamPool, now: number)
	for index, beam in pool.beams do
		if beam.Enabled then
			local age = (now - pool.born[index]) / lidar.beamSeconds
			if age >= 1 then
				beam.Enabled = false
			else
				beam.Transparency =
					NumberSequence.new(lidar.beamTransparency + (1 - lidar.beamTransparency) * age)
			end
		end
	end
end

-- One more dot on a hidden object; at `needed` dots it asks the server to reveal it.
local function countEcho(echoId: number, needed: number, now: number)
	local hits = (echoHits[echoId] or 0) + 1
	echoHits[echoId] = hits
	echoSeenAt = now
	if needed == lidar.echoRevealHits then
		Lidar.echoProgress = math.min(1, hits / needed)
	end
	if hits >= needed and now - (echoAskedAt[echoId] or 0) > REVEAL_RETRY_SECONDS then
		echoAskedAt[echoId] = now
		revealRemote:FireServer(echoId)
	end
end

-- Re-reads where the unrevealed lamps and beacons are. Revealing one removes its echo tag.
local function refreshLightSpots(now: number)
	if now - lightsCheckedAt < LIGHT_REFRESH_SECONDS then
		return
	end
	lightsCheckedAt = now
	table.clear(lightSpots)
	for _, instance in CollectionService:GetTagged(Config.Tags.echo) do
		local id = instance:GetAttribute(ECHO_ATTRIBUTE)
		if instance:GetAttribute(LIGHT_ATTRIBUTE) == true and type(id) == "number" then
			local spot = (instance :: any):GetPivot().Position
			lightSpots[id] = spot
		end
	end
end

-- The local player's own dots feed the map, the exit needle and hidden recorders.
-- Whether a ray from `origin` reaches `spot` without a wall in between (it stops a little short,
-- so the wall a lamp hangs on does not count). A dot that lands beside a lamp on the far side of
-- a wall must not wake it.
local function canSee(origin: Vector3, spot: Vector3, params: RaycastParams): boolean
	local offset = spot - origin
	local distance = offset.Magnitude
	if distance <= LIGHT_CLEARANCE then
		return true
	end
	return workspace:Raycast(origin, offset.Unit * (distance - LIGHT_CLEARANCE), params) == nil
end

local function noteOwnHit(
	position: Vector3,
	target: Target,
	now: number,
	origin: Vector3,
	params: RaycastParams
)
	local plan = State.plan
	if plan ~= nil and State.inLevel() then
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
	end
	if target.exit then
		State.exitScanned = true
	end
	local echoId = target.echoId
	if echoId ~= nil then
		local needed = if target.light then lidar.lightRevealHits else lidar.echoRevealHits
		countEcho(echoId, needed, now)
	end
	-- Lamps and beacons also wake to dots that land near them, so a casual sweep that passes
	-- by finds them: the player does not have to know exactly where they are.
	refreshLightSpots(now)
	for id, spot in lightSpots do
		if
			id ~= echoId
			and (position - spot).Magnitude <= lidar.lightReach
			and canSee(origin, spot, params)
		then
			countEcho(id, lidar.lightRevealHits, now)
		end
	end
end

-- Fires one ray and lands its dot. `beams` and `muzzle` draw the laser line; `own` is true
-- for the local player's gun.
local function castRay(
	origin: Vector3,
	direction: Vector3,
	params: RaycastParams,
	now: number,
	stats: Stats,
	own: boolean,
	beams: BeamPool?,
	muzzle: Vector3?
)
	local result = workspace:Raycast(origin, direction * lidar.maxRange, params)
	if result == nil then
		return
	end
	local target = describe(result.Instance, now)
	local kind, late = DotRules.classify(target.tags, result.Normal.Y)
	if kind == "enemy" and math.random() > lidar.enemyDotChance then
		-- Most rays pass straight through a monster and land on whatever is behind it, so a
		-- scan leaves a few red glimpses rather than an outline, and no shadow on the wall.
		stats.enemy = true
		result = workspace:Raycast(
			result.Position,
			direction * (lidar.maxRange - result.Distance),
			throughParams
		)
		if result == nil then
			return
		end
		target = describe(result.Instance, now)
		kind, late = DotRules.classify(target.tags, result.Normal.Y)
		if kind == "enemy" then
			return
		end
	end
	local position = result.Position + result.Normal * SURFACE_OFFSET
	local distance = (result.Position - origin).Magnitude
	if late then
		Dots.addLate(position, kind, distance, lidar.mimicDotDelay)
	else
		Dots.add(position, kind, distance)
	end
	stats.hits += 1
	stats.distance += distance
	stats.enemy = stats.enemy or kind == "enemy"
	stats.friend = stats.friend or (kind == "friend" and not late)
	stats.objective = stats.objective or kind == "objective"
	if own then
		noteOwnHit(position, target, now, origin, params)
		for _, listener in hitListeners do
			listener(position)
		end
		-- A few fresh dots flare for a moment before settling to their dim size: the scan
		-- crackles where it lands.
		if math.random() < SPARK_CHANCE then
			Dots.mark(position, kind, DotRules.size(kind, distance) * SPARK_SIZE, SPARK_SECONDS)
		end
		if kind == "objective" then
			for _, listener in poiListeners do
				listener(position)
			end
		end
	end
	-- Teammates' relayed rays count too, so a lamp one player finds shows for the whole party.
	for _, listener in seenListeners do
		listener(result.Instance)
	end
	if beams ~= nil and muzzle ~= nil then
		showBeam(beams, muzzle, position, Dots.color(kind), now)
	end
end

local function newStats(): Stats
	return { hits = 0, distance = 0, enemy = false, friend = false, objective = false }
end

local function coneDirection(look: CFrame, halfAngleDeg: number): Vector3
	-- sqrt keeps the scatter uniform over the cone's cross-section, not bunched at the centre.
	local theta = math.rad(halfAngleDeg) * math.sqrt(math.random())
	local phi = math.random() * math.pi * 2
	return (look * CFrame.Angles(0, 0, phi) * CFrame.Angles(theta, 0, 0)).LookVector
end

local function scatter(
	look: CFrame,
	count: number,
	halfAngle: number,
	params: RaycastParams,
	now: number,
	stats: Stats,
	own: boolean,
	beams: BeamPool?,
	muzzle: Vector3?
)
	for _ = 1, count do
		castRay(
			look.Position,
			coneDirection(look, halfAngle),
			params,
			now,
			stats,
			own,
			beams,
			muzzle
		)
	end
end

-- Advances a sweep by `dt`: its rays run left to right along a line that moves from the top
-- of the view to the bottom. Returns true once the last line has been drawn.
local function advanceSweep(
	run: Run,
	look: CFrame,
	dt: number,
	params: RaycastParams,
	now: number,
	stats: Stats,
	own: boolean,
	beams: BeamPool,
	muzzle: Vector3
): boolean
	local total = run.rows * run.columns
	local count =
		math.min(math.ceil(total / lidar.sweepSeconds * dt), MAX_SWEEP_PER_FRAME, total - run.index)
	local pitchSpan = lidar.sweepUpDeg + lidar.sweepDownDeg
	local yawSpan = lidar.sweepHalfWidthDeg * 2
	for _ = 1, count do
		local row = run.index // run.columns
		local column = run.index % run.columns
		local v = (row + (math.random() - 0.5) * SWEEP_JITTER) / (run.rows - 1)
		local u = (column + (math.random() - 0.5) * SWEEP_JITTER) / (run.columns - 1)
		local pitch = math.rad(lidar.sweepUpDeg - v * pitchSpan)
		local yaw = math.rad(lidar.sweepHalfWidthDeg - u * yawSpan)
		local direction = (look * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)).LookVector
		castRay(
			look.Position,
			direction,
			params,
			now,
			stats,
			own,
			if run.index % SWEEP_BEAM_EVERY == 0 then beams else nil,
			muzzle
		)
		run.index += 1
	end
	return run.index >= total
end

local function refreshFilters()
	local list = table.clone(ignore)
	table.insert(list, Dots.folder())
	table.insert(list, beamFolder)
	if player.Character then
		table.insert(list, player.Character)
	end
	raycastParams.FilterDescendantsInstances = list
	local through = table.clone(list)
	for _, enemy in CollectionService:GetTagged(Config.Tags.enemy) do
		table.insert(through, enemy)
	end
	throughParams.FilterDescendantsInstances = through
end

local function emit(stats: Stats)
	if stats.hits > 0 then
		for _, listener in batchListeners do
			listener(
				stats.hits,
				stats.distance / stats.hits,
				stats.enemy,
				stats.friend,
				stats.objective
			)
		end
	end
end

local function maxSpread(): number
	return if State.effects.wideLens then lidar.coneMaxWideDeg else lidar.coneMaxDeg
end

local function changeSpread(by: number)
	Lidar.spread = math.clamp(Lidar.spread + by, lidar.coneMinDeg, maxSpread())
end

-- Touch has one button for the spread: narrow, normal, wide, and round again.
local function cycleSpread()
	if Lidar.spread < lidar.coneHalfAngleDeg then
		Lidar.spread = lidar.coneHalfAngleDeg
	elseif Lidar.spread < maxSpread() then
		Lidar.spread = maxSpread()
	else
		Lidar.spread = lidar.coneMinDeg
	end
end

local function canFire(): boolean
	local stage = State.server.stage
	return Lidar.enabled
		and not State.menuOpen
		and (stage == "tutorial" or stage == "level" or stage == "lore" or stage == "passage")
end

local function report(camera: Camera)
	reportTimer = 1 / lidar.scanStateHz
	scanRemote:FireServer(
		Lidar.firing,
		Lidar.sweeping,
		Avatar.crouching,
		camera.CFrame.LookVector,
		camera.CFrame.Position,
		Lidar.spread
	)
end

local function startSweep()
	local camera = workspace.CurrentCamera
	if camera == nil or not canFire() or Lidar.sweeping or Lidar.charge < 1 then
		return
	end
	ownRun = { index = 0, rows = lidar.sweepRows, columns = lidar.sweepColumns }
	Lidar.sweeping = true
	Lidar.charge = 0
	report(camera) -- at once: the sweep is what monsters hear
	for _, listener in sweepListeners do
		task.spawn(listener)
	end
end

local function stepOwn(camera: Camera, dt: number, now: number)
	local firing = canFire() and Input.firing
	Lidar.firing = firing
	Lidar.spread = math.min(Lidar.spread, maxSpread())
	local look = camera.CFrame
	local muzzle = (look * MUZZLE_OFFSET).Position
	local stats = newStats()

	if firing then
		accumulator += lidar.dotsPerSecond * dt
		local count = math.min(math.floor(accumulator), MAX_SCATTER_PER_FRAME)
		accumulator -= math.floor(accumulator)
		scatter(look, count, Lidar.spread, raycastParams, now, stats, true, ownBeams, muzzle)
	else
		accumulator = 0
	end

	local run = ownRun
	if run ~= nil then
		if
			not canFire()
			or advanceSweep(run, look, dt, raycastParams, now, stats, true, ownBeams, muzzle)
		then
			ownRun = nil
			Lidar.sweeping = false
		end
	else
		local seconds = lidar.sweepRechargeSeconds
			* State.server.sweepScale
			* State.effects.sweepRechargeMul
		Lidar.charge = DotRules.stepCharge(Lidar.charge, dt, seconds)
	end

	-- Pulse Radar: a ring of rays that turns once round the player, on its own timer.
	local radarLevel = State.effects.radarLevel
	if radarLevel > 0 and State.server.stage == "level" and not State.menuOpen then
		radarTimer -= dt
		if radarTimer <= 0 then
			radarTimer = lidar.radarSeconds[math.min(radarLevel, #lidar.radarSeconds)]
			radarRemaining = lidar.radarRays
			radarYaw = math.random() * math.pi * 2
			for _, listener in radarListeners do
				task.spawn(listener)
			end
		end
		if radarRemaining > 0 then
			local count =
				math.min(math.ceil(lidar.radarRays / RADAR_TURN_SECONDS * dt), radarRemaining)
			local pitchLimit = math.rad(lidar.radarPitchDeg)
			for _ = 1, count do
				radarYaw += math.pi * 2 / lidar.radarRays
				local pitch = (math.random() * 2 - 1) * pitchLimit
				local direction = (CFrame.Angles(0, radarYaw, 0) * CFrame.Angles(pitch, 0, 0)).LookVector
				castRay(look.Position, direction, raycastParams, now, stats, true, nil, nil)
			end
			radarRemaining -= count
		end
	else
		radarRemaining = 0
	end

	emit(stats)
	if now - echoSeenAt > ECHO_LINGER_SECONDS then
		Lidar.echoProgress = 0
	end

	reportTimer -= dt
	if reportTimer <= 0 and State.server.stage ~= "title" then
		report(camera)
	end
end

-- Teammates' guns, redrawn from what the server relays about them.
local function stepTeammates(dt: number, now: number)
	local spectating = State.server.stage == "downed"
	if not State.inLevel() or not (spectating or State.profile.settings.sharedScans) then
		return
	end
	local share = if spectating then 1 else lidar.teammateShare
	local stats = newStats()
	for _, mate in teammates do
		if now - mate.at >= RELAY_STALE_SECONDS then
			mate.run = nil
			continue
		end
		local look = CFrame.lookAt(mate.origin, mate.origin + mate.look)
		local muzzle = (look * TEAMMATE_MUZZLE).Position
		if mate.firing then
			mate.accumulator += lidar.dotsPerSecond * share * dt
			local count = math.min(math.floor(mate.accumulator), MAX_SCATTER_PER_FRAME)
			mate.accumulator -= math.floor(mate.accumulator)
			scatter(look, count, mate.spread, mate.params, now, stats, false, mateBeams, muzzle)
		end
		local run = mate.run
		if run ~= nil then
			if advanceSweep(run, look, dt, mate.params, now, stats, false, mateBeams, muzzle) then
				mate.run = nil
			end
		end
	end
end

local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	fadeBeams(ownBeams, now)
	fadeBeams(mateBeams, now)
	refreshFilters()
	stepOwn(camera, dt, now)
	stepTeammates(dt, now)
end

local function onRelay(
	userId: number,
	firing: boolean,
	sweeping: boolean,
	look: Vector3,
	origin: Vector3,
	spread: number
)
	local mate = teammates[userId]
	if mate == nil then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		mate = {
			firing = false,
			sweeping = false,
			look = look,
			origin = origin,
			spread = spread,
			at = 0,
			accumulator = 0,
			params = params,
			run = nil,
		}
		teammates[userId] = mate
	end
	if sweeping and not mate.sweeping then
		-- Their sweep is redrawn as a coarser grid: the same picture for a share of the rays.
		local scale = math.sqrt(lidar.teammateShare)
		mate.run = {
			index = 0,
			rows = math.max(2, math.floor(lidar.sweepRows * scale)),
			columns = math.max(2, math.floor(lidar.sweepColumns * scale)),
		}
	end
	mate.firing = firing
	mate.sweeping = sweeping
	mate.look = look
	mate.origin = origin
	mate.spread = spread
	mate.at = os.clock()
	-- Their rays start inside their own head: never let them hit their own body.
	local owner = Players:GetPlayerByUserId(userId)
	local list: { Instance } = { Dots.folder(), beamFolder }
	if owner and owner.Character then
		table.insert(list, owner.Character)
	end
	mate.params.FilterDescendantsInstances = list
end

-- Fires rays from an arbitrary point and lands their dots, with no beams, sound or
-- reporting. The title screen uses this to scan its own little scene.
function Lidar.cast(look: CFrame, count: number, halfAngleDeg: number, params: RaycastParams)
	scatter(look, count, halfAngleDeg, params, os.clock(), newStats(), false, nil, nil)
end

function Lidar.start()
	beamFolder.Parent = workspace
	RunService:BindToRenderStep("LidarGun", Enum.RenderPriority.Camera.Value + 1, step);
	(Net.get("ScanRelay") :: UnreliableRemoteEvent).OnClientEvent:Connect(onRelay)
	Players.PlayerRemoving:Connect(function(leaving: Player)
		teammates[leaving.UserId] = nil
	end)
	Input.onAction("sweep", startSweep)
	Input.onAction("spreadIn", function()
		changeSpread(-lidar.coneStepDeg)
	end)
	Input.onAction("spreadOut", function()
		changeSpread(lidar.coneStepDeg)
	end)
	Input.onAction("spreadCycle", cycleSpread)
	State.onLevel(function()
		table.clear(cellHits)
		table.clear(echoHits)
		table.clear(echoAskedAt)
		ownRun = nil
		Lidar.sweeping = false
		Lidar.charge = 1
		Lidar.echoProgress = 0
		radarTimer = 0
		radarRemaining = 0
	end)
end

return Lidar
