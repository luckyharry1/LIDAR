--!strict
-- The dot cloud: the only picture of the maze there is. Dots are tiny local Neon cubes, never
-- replicated; every client draws its own.
--
-- There are two kinds of dot:
--  * World dots (walls, floor, ceiling, water, items, hazards) are permanent. They live in a
--    ring of `budget` parts: when the budget is full the oldest dot is moved to become the
--    newest, so the count can never exceed it. They are packed one per grid cell (a finer
--    grid for close surfaces and for items), so scanning the same wall twice costs nothing.
--    A permanent dot is never touched again after it lands, which is what makes tens of
--    thousands of them affordable.
--  * Marks (people, monsters, footprints, trails) fade. They live in a small separate pool
--    and are the only dots updated every few frames.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DotRules = require(ReplicatedStorage.Shared.pure.DotRules)

type Pending = { position: Vector3, kind: DotRules.DotKind, distance: number, at: number }

local lidar = Config.Lidar
local KEY_SPAN = 2 ^ 17 -- grid cells per axis a packing key can tell apart (three axes and
-- the grid level then fit exactly in the 53 bits a number holds)
local KEY_HALF = KEY_SPAN / 2
local GRID_LEVELS = #DotRules.gridSizes
local HIDDEN = 1
local DEFAULT_QUALITY = "medium"

local Dots = {}

Dots.spawned = 0 -- total dots ever landed this session (the tutorial watches this)

local root = Instance.new("Folder")
root.Name = "LidarDots"
local marks = Instance.new("Folder")
marks.Name = "Marks"
marks.Parent = root

local template = Instance.new("Part")
template.Name = "Dot"
template.Anchored = true
template.CanCollide = false
template.CanQuery = false
template.CanTouch = false
template.CastShadow = false
template.Material = Enum.Material.Neon
template.TopSurface = Enum.SurfaceType.Smooth
template.BottomSurface = Enum.SurfaceType.Smooth

local colors: { [string]: Color3 } = {}

-- World dots.
local budget = DotRules.budget(DEFAULT_QUALITY, 0)
local world: Folder
local worldParts: { Part } = {}
local worldKeys: { number } = {}
local worldNext = 1
local occupied: { [number]: boolean } = {}

-- Marks.
local markCapacity = lidar.fadingDots
local markParts: { Part } = table.create(markCapacity)
local markBorn: { number } = table.create(markCapacity, 0)
local markLife: { number } = table.create(markCapacity, 1)
local markAlive: { boolean } = table.create(markCapacity, false)
local markNext = 1
local markCount = 0
local frame = 0
local frozen = false
local clock = 0 -- mark time: stops while frozen so photo mode holds the picture
local pending: { Pending } = {} -- dots that will land late (the Mimic's tell)

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

local function newWorld(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "World"
	folder.Parent = root
	return folder
end
world = newWorld()

-- Sets the palette ("default" or "alt") and an optional wall tint from a cosmetic.
function Dots.setPalette(name: string, wallTint: { number }?)
	local palette = Config.Palettes[name] or Config.Palettes.default
	for kind, triple in palette do
		colors[kind] = rgb(triple)
	end
	if wallTint then
		colors.wall = rgb(wallTint)
	end
end
Dots.setPalette("default", nil)

function Dots.color(kind: DotRules.DotKind): Color3
	return colors[kind]
end

-- The one folder that holds every dot. It never changes, so ray filters can keep it.
function Dots.folder(): Folder
	return root
end

function Dots.liveCount(): number
	return #worldParts + markCount
end

-- Changes how many permanent dots the world may hold. Shrinking drops the newest slots.
function Dots.setBudget(count: number)
	count = math.max(1, math.floor(count))
	for slot = #worldParts, count + 1, -1 do
		occupied[worldKeys[slot]] = nil
		worldParts[slot]:Destroy()
		worldParts[slot] = nil
		worldKeys[slot] = nil
	end
	budget = count
	if worldNext > budget then
		worldNext = 1
	end
end

local function packingKey(position: Vector3, level: number): number
	local grid = DotRules.gridSizes[level]
	local x = (math.floor(position.X / grid) + KEY_HALF) % KEY_SPAN
	local y = (math.floor(position.Y / grid) + KEY_HALF) % KEY_SPAN
	local z = (math.floor(position.Z / grid) + KEY_HALF) % KEY_SPAN
	return ((x * KEY_SPAN + y) * KEY_SPAN + z) * GRID_LEVELS + (level - 1)
end

local function addWorld(position: Vector3, kind: DotRules.DotKind, distance: number): boolean
	local key = packingKey(position, DotRules.gridLevel(kind, distance))
	if occupied[key] then
		return false
	end
	local slot = worldNext
	worldNext = worldNext % budget + 1
	local size = DotRules.size(kind, distance)
	local part = worldParts[slot]
	if part == nil then
		part = template:Clone()
		part.Size = Vector3.one * size
		part.Color = colors[kind]
		part.Position = position
		part.Parent = world
		worldParts[slot] = part
	else
		occupied[worldKeys[slot]] = nil
		part.Size = Vector3.one * size
		part.Color = colors[kind]
		part.Position = position
	end
	worldKeys[slot] = key
	occupied[key] = true
	Dots.spawned += 1
	return true
end

-- A fading dot with an explicit size (studs) and lifetime (seconds): footprints, trails,
-- rings. Never permanent, never packed.
function Dots.mark(position: Vector3, kind: DotRules.DotKind, size: number, lifetime: number)
	local slot = markNext
	markNext = markNext % markCapacity + 1
	local part = markParts[slot]
	if part == nil then
		part = template:Clone()
		part.Parent = marks
		markParts[slot] = part
	end
	if not markAlive[slot] then
		markCount += 1
	end
	markAlive[slot] = true
	markBorn[slot] = clock
	markLife[slot] = lifetime
	part.Size = Vector3.one * size
	part.Color = colors[kind]
	part.Position = position
	part.Transparency = 0
	Dots.spawned += 1
end

-- Lands a dot. `distance` is how far the surface was from the scanner. World kinds are
-- permanent and packed one per grid cell: returns false when that cell already has a dot.
-- People and monsters get a mark that fades on its own.
function Dots.add(position: Vector3, kind: DotRules.DotKind, distance: number): boolean
	if DotRules.isPermanent(kind) then
		return addWorld(position, kind, distance)
	end
	Dots.mark(position, kind, DotRules.size(kind, distance), DotRules.lifetime(kind))
	return true
end

-- Lands a dot after a delay.
function Dots.addLate(position: Vector3, kind: DotRules.DotKind, distance: number, delay: number)
	table.insert(
		pending,
		{ position = position, kind = kind, distance = distance, at = clock + delay }
	)
end

-- Photo mode: hold every dot exactly as it is.
function Dots.setFrozen(value: boolean)
	frozen = value
end

function Dots.isFrozen(): boolean
	return frozen
end

-- Wipes the picture: a new level starts undrawn.
function Dots.clear()
	local old = world
	world = newWorld()
	old:Destroy()
	table.clear(worldParts)
	table.clear(worldKeys)
	table.clear(occupied)
	worldNext = 1
	for slot = 1, markCapacity do
		if markAlive[slot] then
			markAlive[slot] = false
			markParts[slot].Transparency = HIDDEN
		end
	end
	markCount = 0
	table.clear(pending)
end

local function update(dt: number)
	if frozen then
		return
	end
	clock += dt
	frame += 1

	for index = #pending, 1, -1 do
		local dot = pending[index]
		if clock >= dot.at then
			table.remove(pending, index)
			Dots.add(dot.position, dot.kind, dot.distance)
		end
	end

	-- Fade the marks: one stagger group per frame.
	local stagger = lidar.fadeStagger
	for slot = frame % stagger + 1, markCapacity, stagger do
		if markAlive[slot] then
			local age = (clock - markBorn[slot]) / markLife[slot]
			if age >= 1 then
				markAlive[slot] = false
				markCount -= 1
				markParts[slot].Transparency = HIDDEN
			else
				markParts[slot].Transparency = DotRules.fade(age)
			end
		end
	end
end

function Dots.start()
	root.Parent = workspace
	RunService:BindToRenderStep("LidarDots", Enum.RenderPriority.Last.Value, update)
end

return Dots
