--!strict
-- The dot cloud. Dots are local Neon parts in a fixed-size ring buffer: when the cap is
-- reached the oldest dot is recycled, so the live count can never exceed Config.Lidar.maxLiveDots.
-- Nothing here is replicated; every client draws only its own picture of the dark.
--
-- Cost control: each dot's fade is refreshed once every `fadeStagger` frames, and only dots
-- younger than POP_SECONDS are touched every frame (for the landing "pop").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DotRules = require(ReplicatedStorage.Shared.pure.DotRules)

type Pending = {
	position: Vector3,
	class: DotRules.DotClass,
	distance: number,
	lifetimeMul: number,
	at: number,
}

local POP_SECONDS = 0.14
local POP_SCALE = 1.9 -- a new dot starts this much larger and settles to its real size
local HIDDEN = 1
local PREWARM_PER_FRAME = 40

local lidar = Config.Lidar
local capacity = lidar.maxLiveDots

local Dots = {}

Dots.spawned = 0 -- total dots ever spawned this session (the tutorial watches this)

local folder = Instance.new("Folder")
folder.Name = "LidarDots"
folder.Parent = workspace

local parts: { Part } = table.create(capacity)
local born: { number } = table.create(capacity, 0)
local life: { number } = table.create(capacity, 0)
local size: { number } = table.create(capacity, 0)
local alive: { boolean } = table.create(capacity, false)
local nextSlot = 1
local liveCount = 0
local frame = 0
local frozen = false
local clock = 0 -- dot time: stops while frozen so photo mode holds the picture
local fresh: { number } = {} -- slots still inside their landing pop
local pending: { Pending } = {} -- dots that will land late (the Mimic's tell)
local colors: { [string]: Color3 } = {}

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

-- Sets the palette ("default" or "alt") and an optional terrain tint from a cosmetic.
function Dots.setPalette(name: string, terrainTint: { number }?)
	local palette = Config.Palettes[name] or Config.Palettes.default
	colors.terrain = rgb(terrainTint or palette.terrain)
	colors.friend = rgb(palette.friend)
	colors.enemy = rgb(palette.enemy)
	colors.objective = rgb(palette.objective)
end
Dots.setPalette("default", nil)

function Dots.color(class: string): Color3
	return colors[class]
end

function Dots.folder(): Folder
	return folder
end

function Dots.liveCount(): number
	return liveCount
end

local function makePart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Ball
	part.Transparency = HIDDEN
	part.Parent = folder
	return part
end

-- Lands a dot now. `distance` is how far it is from the scanner (far dots are drawn larger);
-- `lifetimeMul` and `sizeScale` adjust its life and size (water swallows dots faster).
function Dots.spawn(
	position: Vector3,
	class: DotRules.DotClass,
	distance: number,
	lifetimeMul: number,
	sizeScale: number
)
	local slot = nextSlot
	nextSlot = nextSlot % capacity + 1
	local part = parts[slot]
	if part == nil then
		part = makePart()
		parts[slot] = part
	end
	if not alive[slot] then
		liveCount += 1
	end
	local dotSize = DotRules.size(class, distance) * sizeScale
	alive[slot] = true
	born[slot] = clock
	life[slot] = DotRules.lifetime(class, lifetimeMul)
	size[slot] = dotSize
	part.Position = position
	part.Color = colors[class]
	part.Size = Vector3.one * dotSize * POP_SCALE
	part.Transparency = 0
	table.insert(fresh, slot)
	Dots.spawned += 1
end

-- Lands a dot after a delay.
function Dots.spawnLate(
	position: Vector3,
	class: DotRules.DotClass,
	distance: number,
	lifetimeMul: number,
	delay: number
)
	table.insert(pending, {
		position = position,
		class = class,
		distance = distance,
		lifetimeMul = lifetimeMul,
		at = clock + delay,
	})
end

-- Photo mode: hold every dot exactly as it is.
function Dots.setFrozen(value: boolean)
	frozen = value
end

function Dots.isFrozen(): boolean
	return frozen
end

function Dots.clear()
	for slot = 1, capacity do
		if alive[slot] then
			alive[slot] = false
			parts[slot].Transparency = HIDDEN
		end
	end
	liveCount = 0
	table.clear(fresh)
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
			Dots.spawn(dot.position, dot.class, dot.distance, dot.lifetimeMul, 1)
		end
	end

	-- Landing pop: shrink new dots from POP_SCALE to their real size.
	for index = #fresh, 1, -1 do
		local slot = fresh[index]
		local age = clock - born[slot]
		if age >= POP_SECONDS or not alive[slot] then
			if alive[slot] then
				parts[slot].Size = Vector3.one * size[slot]
			end
			fresh[index] = fresh[#fresh]
			fresh[#fresh] = nil
		else
			local scale = POP_SCALE + (1 - POP_SCALE) * (age / POP_SECONDS)
			parts[slot].Size = Vector3.one * size[slot] * scale
		end
	end

	-- Fade: one stagger group per frame.
	local stagger = lidar.fadeStagger
	local first = frame % stagger + 1
	for slot = first, capacity, stagger do
		if alive[slot] then
			local age = (clock - born[slot]) / life[slot]
			if age >= 1 then
				alive[slot] = false
				liveCount -= 1
				parts[slot].Transparency = HIDDEN
			else
				parts[slot].Transparency = DotRules.fade(age)
			end
		end
	end
end

function Dots.start()
	RunService:BindToRenderStep("LidarDots", Enum.RenderPriority.Last.Value, update)
	-- Build the pool a little each frame up front, so the first sweep never hitches on it.
	task.spawn(function()
		for slot = 1, capacity do
			if parts[slot] == nil then
				parts[slot] = makePart()
			end
			if slot % PREWARM_PER_FRAME == 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

return Dots
