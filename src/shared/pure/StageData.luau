--!strict
-- The sets and shots of every filmed cutscene, as plain numbers. Stage.luau builds Parts and
-- aims the camera from this data and nothing else, so tests/StageTests.luau can check every
-- shot with plain maths: nobody can see these pictures from the cloud, and a camera that sits
-- on the floor or inside a wall is exactly the kind of mistake maths can find.
--
-- A room is a list of blocks (axis-aligned boxes, except where marked), a light, and cues. A
-- cue is what a `stage` beat in a scene asks for: it may carry camera segments, a hold (the
-- seconds the scene waits before the next beat), and subjects (points that must be in frame).
-- Blocks marked `decor` are small or rotated and never block a camera or a line of sight;
-- blocks marked `hidden` are never drawn (they exist so the scanner's dots have walls to land
-- on).

export type Vec = { number }
export type Color = { number }
export type Block = {
	name: string,
	size: Vec,
	at: Vec,
	color: Color,
	neon: boolean?,
	shape: string?, -- "ball" or "cylinder" (a cylinder's long axis is its x axis before `rot`)
	alpha: number?, -- starting transparency
	decor: boolean?,
	hidden: boolean?,
	rot: Vec?, -- degrees about x, y, z
	rod: { Vec }?, -- {from, to}: a thin bar between two points (`size.x` is its thickness)
	dot: string?, -- the dot kind this block's scan dots take (default "wall")
	weight: number?, -- how many more dots than its area earns land on it
}
export type Subject = { Vec } -- {point} or {point at the start, point at the end}
export type Seg = {
	seconds: number,
	from: Vec,
	at: Vec,
	toFrom: Vec?,
	toAt: Vec?,
	ease: string?, -- "smooth" (default) or "linear"
	roll: number?, -- degrees
	toRoll: number?,
	subjects: { Subject }?,
}
export type Cue = {
	segs: { Seg }?,
	hold: number?, -- seconds the scene waits for this cue
	after: { any }?, -- {cue, seconds}: starts no earlier than this long after that cue began
	fill: { bottom: number, top: number, x: number, z: number }?, -- the speaker, for the framing test
	subjects: { Subject }?, -- extra points that must be in the frame of the room's main shot
}
export type Scan = {
	origin: Vec,
	dir: Vec,
	count: number,
	seed: number,
	order: string, -- "sweep" (left to right), "radial" (near to far) or "mix"
	half: number, -- degrees either side of `dir`, sideways
	vhalf: number, -- and up or down
	maxDist: number,
	seconds: number,
	size: number,
}
export type Room = {
	id: string,
	fov: number,
	ambient: Color,
	light: Color,
	blocks: { Block },
	cues: { [string]: Cue },
	start: string, -- the cue whose first frame is the opening shot
	scan: Scan?,
	bottom: number?, -- for tapes: the lowest point of the speaker that shows (the desk top)
}
export type Dot = { x: number, y: number, z: number, t: number, kind: string }

local StageData = {}

--------------------------------------------------------------------------------------------
-- Maths on plain vectors

local function sub(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function dot(a: Vec, b: Vec): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function cross(a: Vec, b: Vec): Vec
	return {
		a[2] * b[3] - a[3] * b[2],
		a[3] * b[1] - a[1] * b[3],
		a[1] * b[2] - a[2] * b[1],
	}
end

local function length(a: Vec): number
	return math.sqrt(dot(a, a))
end

local function normal(a: Vec): Vec
	local size = length(a)
	if size < 1e-9 then
		return { 0, 0, -1 }
	end
	return { a[1] / size, a[2] / size, a[3] / size }
end

local function lerp(a: Vec, b: Vec, t: number): Vec
	return {
		a[1] + (b[1] - a[1]) * t,
		a[2] + (b[2] - a[2]) * t,
		a[3] + (b[3] - a[3]) * t,
	}
end

StageData.sub = sub
StageData.dot = dot
StageData.length = length
StageData.lerp = lerp

--------------------------------------------------------------------------------------------
-- Camera

local function ease(kind: string?, u: number): number
	if kind == "linear" then
		return u
	end
	return u * u * (3 - 2 * u)
end

StageData.ease = ease

function StageData.duration(segs: { Seg }): number
	local total = 0
	for _, seg in segs do
		total += seg.seconds
	end
	return total
end

-- Where the camera is `t` seconds into a list of segments: position, the point it looks at,
-- its roll (degrees), the index of the segment, and how far through that segment it is (eased).
function StageData.cameraAt(segs: { Seg }, t: number): (Vec, Vec, number, number, number)
	local left = math.max(t, 0)
	for index, seg in segs do
		if left <= seg.seconds or index == #segs then
			local u = math.clamp(left / math.max(seg.seconds, 0.001), 0, 1)
			local e = ease(seg.ease, u)
			local roll = (seg.roll or 0) + ((seg.toRoll or seg.roll or 0) - (seg.roll or 0)) * e
			return lerp(seg.from, seg.toFrom or seg.from, e),
				lerp(seg.at, seg.toAt or seg.at, e),
				roll,
				index,
				e
		end
		left -= seg.seconds
	end
	local last = segs[#segs]
	return last.from, last.at, 0, #segs, 1
end

-- Where a point lands on a screen of the given aspect ratio: x and y run -1..1 from the centre,
-- depth is the distance along the view direction (negative: behind the camera).
function StageData.project(
	position: Vec,
	lookAt: Vec,
	fov: number,
	aspect: number,
	point: Vec
): (number, number, number)
	local forward = normal(sub(lookAt, position))
	local right = normal(cross(forward, { 0, 1, 0 }))
	local up = cross(right, forward)
	local rel = sub(point, position)
	local depth = dot(rel, forward)
	if depth < 1e-6 then
		return 0, 0, depth
	end
	local scale = math.tan(math.rad(fov) / 2)
	return dot(rel, right) / (depth * scale * aspect), dot(rel, up) / (depth * scale), depth
end

--------------------------------------------------------------------------------------------
-- Boxes

function StageData.isSolid(block: Block): boolean
	return not block.decor and not block.hidden and block.rot == nil and block.rod == nil
end

local function bounds(block: Block, margin: number): (Vec, Vec)
	local half = block.size
	return {
		block.at[1] - half[1] / 2 - margin,
		block.at[2] - half[2] / 2 - margin,
		block.at[3] - half[3] / 2 - margin,
	}, {
		block.at[1] + half[1] / 2 + margin,
		block.at[2] + half[2] / 2 + margin,
		block.at[3] + half[3] / 2 + margin,
	}
end

function StageData.insideBlock(block: Block, point: Vec, margin: number): boolean
	local low, high = bounds(block, margin)
	for axis = 1, 3 do
		if point[axis] < low[axis] or point[axis] > high[axis] then
			return false
		end
	end
	return true
end

-- Does the segment a-b pass through the box (shrunk by `shrink`, so grazing a face is not a hit)?
function StageData.segmentHits(block: Block, a: Vec, b: Vec, shrink: number): boolean
	local low, high = bounds(block, -shrink)
	local first, last = 0, 1
	for axis = 1, 3 do
		local from = a[axis]
		local delta = b[axis] - a[axis]
		if math.abs(delta) < 1e-9 then
			if from < low[axis] or from > high[axis] then
				return false
			end
		else
			local t1 = (low[axis] - from) / delta
			local t2 = (high[axis] - from) / delta
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			first = math.max(first, t1)
			last = math.min(last, t2)
			if first > last then
				return false
			end
		end
	end
	return true
end

--------------------------------------------------------------------------------------------
-- Building blocks of the data

type Flags = {
	neon: boolean?,
	shape: string?,
	alpha: number?,
	decor: boolean?,
	hidden: boolean?,
	rot: Vec?,
	dot: string?,
	weight: number?,
}

local function box(name: string, size: Vec, at: Vec, color: Color, flags: Flags?): Block
	local block: Block = { name = name, size = size, at = at, color = color }
	if flags then
		block.neon = flags.neon
		block.shape = flags.shape
		block.alpha = flags.alpha
		block.decor = flags.decor
		block.hidden = flags.hidden
		block.rot = flags.rot
		block.dot = flags.dot
		block.weight = flags.weight
	end
	return block
end

local function rod(name: string, from: Vec, to: Vec, thickness: number, color: Color, flags: Flags?)
	local block = box(name, { thickness, thickness, 0 }, lerp(from, to, 0.5), color, flags)
	block.rod = { from, to }
	block.decor = true
	return block
end

local DECOR: Flags = { decor = true }
local NEON: Flags = { neon = true }
local NEON_DECOR: Flags = { neon = true, decor = true }
local HIDDEN_DECOR: Flags = { hidden = true, decor = true }

local function append(into: { Block }, from: { Block })
	for _, block in from do
		table.insert(into, block)
	end
end

--------------------------------------------------------------------------------------------
-- Faces and figures

StageData.coats = {
	Theo = { 214, 124, 46 },
	Ines = { 60, 112, 82 },
	Pike = { 124, 92, 60 },
	Hollis = { 110, 114, 132 },
	Tobi = { 128, 62, 62 },
	Ravi = { 60, 92, 142 },
	Quill = { 94, 72, 114 },
	Joss = { 168, 124, 66 },
	Hana = { 92, 128, 126 },
	Lena = { 86, 140, 96 },
	Pim = { 196, 96, 64 },
	Echo = { 226, 226, 236 },
	Announcer = { 124, 92, 60 },
} :: { [string]: Color }

-- Small parts that tell one person from another. `to` is the part they ride on ("head" or
-- "torso"); `at` is relative to that part's centre; the face looks along -z.
export type Feature =
	{ size: Vec, at: Vec, color: Color, to: string, shape: string?, alpha: number? }

local function feature(
	to: string,
	size: Vec,
	at: Vec,
	color: Color,
	shape: string?,
	alpha: number?
): Feature
	return { to = to, size = size, at = at, color = color, shape = shape, alpha = alpha }
end

local DARK_HAIR = { 44, 34, 30 }
local GREY_HAIR = { 170, 168, 164 }
local BROWN_HAIR = { 98, 66, 40 }

local function hair(color: Color, scale: number?): Feature
	local s = 1.32 * (scale or 1)
	return feature("head", { s, s, s }, { 0, 0.14, 0.14 }, color, "ball")
end

local function glasses(color: Color): { Feature }
	return {
		feature("head", { 0.38, 0.3, 0.04 }, { -0.26, 0.1, -0.6 }, color, nil, 0.55),
		feature("head", { 0.38, 0.3, 0.04 }, { 0.26, 0.1, -0.6 }, color, nil, 0.55),
		feature("head", { 0.2, 0.05, 0.04 }, { 0, 0.14, -0.6 }, color),
	}
end

local function capOn(color: Color): { Feature }
	return {
		feature("head", { 1.34, 0.5, 1.34 }, { 0, 0.5, 0.02 }, color),
		feature("head", { 1.1, 0.1, 0.7 }, { 0, 0.34, -0.8 }, color),
	}
end

local function concat(...: { Feature }): { Feature }
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end

StageData.features = {
	Theo = concat({ hair(DARK_HAIR) }, {
		feature("torso", { 2.0, 0.34, 1.0 }, { 0, 0.95, 0 }, { 238, 238, 232 }),
	}),
	Ines = concat({
		hair(GREY_HAIR),
		feature("head", { 0.5, 0.5, 0.5 }, { 0, 0.66, 0.34 }, GREY_HAIR, "ball"),
	}, glasses({ 40, 40, 46 })),
	Joss = concat(capOn({ 90, 70, 40 }), { hair(BROWN_HAIR, 0.9) }),
	Hana = {
		hair(DARK_HAIR),
		feature("head", { 0.34, 1.0, 0.34 }, { 0, -0.3, 0.74 }, DARK_HAIR),
	},
	Lena = {
		hair(BROWN_HAIR),
		feature("torso", { 2.0, 0.55, 1.1 }, { 0, 1.0, 0 }, { 230, 214, 140 }),
	},
	Ravi = {
		hair(DARK_HAIR, 0.95),
		feature("head", { 1.5, 0.12, 0.12 }, { 0, 0.62, 0 }, { 40, 40, 44 }),
		feature("head", { 0.28, 0.6, 0.6 }, { -0.7, 0.05, 0.04 }, { 40, 40, 44 }),
		feature("head", { 0.28, 0.6, 0.6 }, { 0.7, 0.05, 0.04 }, { 40, 40, 44 }),
	},
	Pim = {
		feature("head", { 1.36, 0.62, 1.36 }, { 0, 0.5, 0.02 }, { 214, 70, 70 }),
		feature("head", { 0.46, 0.46, 0.46 }, { 0, 0.98, 0 }, { 240, 232, 220 }, "ball"),
	},
	Hollis = concat(capOn({ 36, 40, 56 }), {
		feature("torso", { 0.16, 0.42, 0.1 }, { 0.95, -0.7, -0.5 }, { 230, 200, 80 }),
		feature("torso", { 0.16, 0.42, 0.1 }, { 0.7, -0.7, -0.5 }, { 200, 200, 206 }),
	}),
	Tobi = {
		hair(DARK_HAIR, 1.08),
		feature("torso", { 1.9, 0.55, 1.1 }, { 0, 1.0, 0.35 }, { 128, 62, 62 }),
	},
	Quill = concat({
		hair(BROWN_HAIR),
		feature("torso", { 2.0, 0.55, 1.1 }, { 0, 1.0, 0 }, { 150, 70, 80 }),
	}, glasses({ 30, 30, 34 })),
	Pike = {
		feature("head", { 1.4, 0.4, 1.4 }, { 0, 0.52, 0 }, { 240, 200, 50 }),
		feature("head", { 1.0, 0.1, 0.6 }, { 0, 0.34, -0.8 }, { 240, 200, 50 }),
		feature("torso", { 0.3, 0.38, 0.05 }, { 0, 0.4, -0.48 }, { 240, 240, 236 }),
	},
	Echo = {},
	Announcer = {},
} :: { [string]: { Feature } }

--------------------------------------------------------------------------------------------
-- Scanning: where a scanner's dots land

local function rng(seed: number): () -> number
	local state = (seed * 7919 + 12345) % 4294967296
	return function(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

local FACES = {
	{ axis = 1, sign = 1 },
	{ axis = 1, sign = -1 },
	{ axis = 2, sign = 1 },
	{ axis = 2, sign = -1 },
	{ axis = 3, sign = 1 },
	{ axis = 3, sign = -1 },
}

-- `count` dots on the faces of the room's blocks that the scanner at `origin` can see, each with
-- a time (0..1) at which the sweep reaches it, sorted by that time.
function StageData.scanDots(blocks: { Block }, scan: Scan): { Dot }
	local random = rng(scan.seed)
	local occluders: { Block } = {}
	for _, block in blocks do
		if not block.decor and block.rot == nil then
			table.insert(occluders, block)
		end
	end
	local forward = normal(scan.dir)
	local flat = normal({ forward[1], 0, forward[3] })
	local right = { -flat[3], 0, flat[1] }
	local cosHalf = math.cos(math.rad(math.min(scan.half, 89)))
	local faces: { { block: Block, axis: number, sign: number, weight: number } } = {}
	local total = 0
	for _, block in occluders do
		for _, face in FACES do
			local center = { block.at[1], block.at[2], block.at[3] }
			center[face.axis] += face.sign * block.size[face.axis] / 2
			local toOrigin = sub(scan.origin, center)
			if face.sign * toOrigin[face.axis] > 0.05 and length(toOrigin) <= scan.maxDist + 6 then
				local u, v = (face.axis % 3) + 1, ((face.axis + 1) % 3) + 1
				local weight = block.size[u] * block.size[v] * (block.weight or 1)
				table.insert(
					faces,
					{ block = block, axis = face.axis, sign = face.sign, weight = weight }
				)
				total += weight
			end
		end
	end
	local dots: { Dot } = {}
	if total <= 0 then
		return dots
	end
	local tries = 0
	while #dots < scan.count and tries < scan.count * 14 do
		tries += 1
		local pick = random() * total
		local chosen = faces[#faces]
		for _, face in faces do
			pick -= face.weight
			if pick <= 0 then
				chosen = face
				break
			end
		end
		local block = chosen.block
		local point = { block.at[1], block.at[2], block.at[3] }
		for axis = 1, 3 do
			if axis == chosen.axis then
				point[axis] += chosen.sign * (block.size[axis] / 2 + 0.03)
			else
				point[axis] += (random() - 0.5) * block.size[axis] * 0.96
			end
		end
		local rel = sub(point, scan.origin)
		local distance = length(rel)
		local direction = normal(rel)
		local sideways = math.atan2(dot(rel, right), dot(rel, flat))
		local vertical = math.asin(math.clamp(direction[2], -1, 1))
			- math.asin(math.clamp(forward[2], -1, 1))
		local ahead = dot(direction, forward)
		if
			distance <= scan.maxDist
			and distance > 0.5
			and ahead > cosHalf
			and math.abs(math.deg(sideways)) <= scan.half
			and math.abs(math.deg(vertical)) <= scan.vhalf
		then
			local hidden = false
			for _, other in occluders do
				if other ~= block and StageData.segmentHits(other, scan.origin, point, 0.04) then
					hidden = true
					break
				end
			end
			if not hidden then
				local across = math.clamp(0.5 + math.deg(sideways) / (2 * scan.half), 0, 1)
				local far = math.clamp(distance / scan.maxDist, 0, 1)
				local time: number
				if scan.order == "sweep" then
					time = across * 0.93 + random() * 0.07
				elseif scan.order == "radial" then
					time = far * 0.9 + random() * 0.1
				else
					time = across * 0.5 + far * 0.4 + random() * 0.1
				end
				table.insert(dots, {
					x = point[1],
					y = point[2],
					z = point[3],
					t = time,
					kind = block.dot or "wall",
				})
			end
		end
	end
	table.sort(dots, function(a: Dot, b: Dot): boolean
		return a.t < b.t
	end)
	return dots
end

--------------------------------------------------------------------------------------------
-- The chalkboard in the lamp room: white dots for every scan the Survey made, and a gap in the
-- shape of a corridor that is left dark and then lit gold.

export type BoardDot = { x: number, y: number, t: number }
StageData.board = {
	width = 16,
	height = 9,
	-- rectangles {x0, y0, x1, y1} in studs from the board's centre: the corridor
	gap = {
		{ -5.6, -1.0, 5.6, 0.4 },
		{ 3.8, 0.4, 5.6, 3.4 },
		{ -6.8, -2.0, -4.4, 1.4 },
	},
}

local function inGap(x: number, y: number, margin: number): boolean
	for _, rect in StageData.board.gap do
		if
			x >= rect[1] - margin
			and x <= rect[3] + margin
			and y >= rect[2] - margin
			and y <= rect[4] + margin
		then
			return true
		end
	end
	return false
end

function StageData.boardDots(
	count: number,
	gapCount: number,
	seed: number
): ({ BoardDot }, { BoardDot })
	local random = rng(seed)
	local board = StageData.board
	local filled: { BoardDot } = {}
	local tries = 0
	while #filled < count and tries < count * 20 do
		tries += 1
		local x = (random() - 0.5) * (board.width - 1.2)
		local y = (random() - 0.5) * (board.height - 1.2)
		if not inGap(x, y, 0.35) then
			table.insert(
				filled,
				{ x = x, y = y, t = (x / board.width + 0.5) * 0.9 + random() * 0.1 }
			)
		end
	end
	table.sort(filled, function(a: BoardDot, b: BoardDot): boolean
		return a.t < b.t
	end)
	local gap: { BoardDot } = {}
	tries = 0
	while #gap < gapCount and tries < gapCount * 40 do
		tries += 1
		local rect = board.gap[1 + math.floor(random() * #board.gap)]
		local x = rect[1] + random() * (rect[3] - rect[1])
		local y = rect[2] + random() * (rect[4] - rect[2])
		table.insert(gap, { x = x, y = y, t = random() })
	end
	return filled, gap
end

--------------------------------------------------------------------------------------------
-- Rooms

StageData.rooms = {} :: { [string]: Room }
local rooms = StageData.rooms

local function room(definition: Room)
	rooms[definition.id] = definition
end

-- The office on floor three ----------------------------------------------------------------

local WALL = { 164, 144, 80 }
local SCANNER_AT = { 6, 4.2, -6 }
local HOLE_X = -0.75

local function officeShell(): { Block }
	local blocks: { Block } = {
		box("Floor", { 40, 1, 56 }, { 0, -0.5, 2 }, { 104, 98, 84 }),
		box("WallBack", { 40, 14, 1 }, { 0, 7, -26 }, WALL),
		box("WallL", { 1, 14, 56 }, { -20, 7, 2 }, WALL),
		box("WallR", { 1, 14, 56 }, { 20, 7, 2 }, WALL),
		box("Ceiling", { 40, 1, 56 }, { 0, 14.5, 2 }, { 132, 130, 120 }),
		box("Pillar", { 2, 14, 2 }, { -15, 7, 0 }, { 150, 134, 84 }),
		box("Pillar", { 2, 14, 2 }, { 14, 7, -14 }, { 150, 134, 84 }),
		box("Desk", { 6, 3, 3 }, { -13, 1.5, -6 }, { 96, 82, 62 }),
		box("Desk", { 6, 3, 3 }, { 12, 1.5, 4 }, { 96, 82, 62 }),
		box("Chair", { 2, 2.4, 2 }, { -13, 1.2, -3 }, { 50, 52, 58 }),
		box("Partition", { 0.4, 5, 7 }, { -8, 2.5, -14 }, { 120, 116, 104 }),
		box("Partition", { 7, 5, 0.4 }, { -11.5, 2.5, -17.4 }, { 120, 116, 104 }),
		box("Cabinet", { 2, 5, 3 }, { -18.5, 2.5, -20 }, { 110, 112, 116 }),
		box("Cabinet", { 2, 5, 3 }, { -18.5, 2.5, -16 }, { 110, 112, 116 }),
		box("Copier", { 3, 3.6, 2.4 }, { 17, 1.8, -20 }, { 190, 186, 176 }),
		box("Cooler", { 1.4, 4, 1.4 }, { 18, 2, 10 }, { 150, 190, 210 }),
		box("Papers", { 1.6, 0.1, 1.2 }, { -13, 3.1, -6 }, { 236, 230, 210 }, DECOR),
	}
	-- The scanner: a tripod, a head, a lens. Never a blocker, never a place dots land.
	for index, angle in { 0, 120, 240 } do
		local direction = { math.sin(math.rad(angle)), 0, math.cos(math.rad(angle)) }
		table.insert(
			blocks,
			rod(
				"TripodLeg" .. index,
				{ 6 + direction[1] * 1.4, 0, -6 + direction[3] * 1.4 },
				{ 6, 3.6, -6 },
				0.18,
				{ 40, 40, 44 }
			)
		)
	end
	table.insert(blocks, box("ScannerHead", { 1.3, 1.1, 1.3 }, SCANNER_AT, { 70, 74, 80 }, DECOR))
	table.insert(
		blocks,
		box("ScannerLens", { 0.5, 0.5, 0.3 }, { 6, 4.2, -6.7 }, { 235, 240, 255 }, NEON_DECOR)
	)
	return blocks
end

local function ceilingLights(color: Color, neon: boolean): { Block }
	local blocks: { Block } = {}
	for index, z in { 14, 2, -10, -22 } do
		table.insert(
			blocks,
			box("CeilingLight" .. index, { 6, 0.2, 2 }, { 0, 13.9, z }, color, { neon = neon })
		)
	end
	return blocks
end

local function meltParts(): { Block }
	local blocks = {
		box("MeltStain", { 8, 9.6, 0.03 }, { HOLE_X, 4.8, -25.485 }, { 196, 164, 72 }, {
			decor = true,
			alpha = 1,
		}),
		box("MeltRim", { 1, 1, 0.06 }, { HOLE_X, 4, -25.46 }, { 52, 36, 20 }, HIDDEN_DECOR),
		box("MeltHole", { 1, 1, 0.06 }, { HOLE_X, 4, -25.4 }, { 255, 240, 196 }, {
			neon = true,
			decor = true,
			hidden = true,
		}),
		box("MeltFloor", { 2, 0.05, 2 }, { HOLE_X, 0.04, -23.6 }, { 255, 218, 140 }, {
			neon = true,
			decor = true,
			hidden = true,
		}),
	}
	for index, offset in { -2.3, -2.8, -3.3, 2.1, 2.6, 3.1 } do
		table.insert(
			blocks,
			box(
				"MeltDrip" .. index,
				{ 0.3 + (index % 3) * 0.08, 0.2, 0.1 },
				{ HOLE_X + offset, 8.5, -25.38 },
				{ 214, 176, 74 },
				HIDDEN_DECOR
			)
		)
	end
	return blocks
end

local officeBlocks = officeShell()
append(officeBlocks, ceilingLights({ 236, 255, 226 }, true))
append(officeBlocks, meltParts())

local THEO_CHEST = { 3, 3.2, -4 }

room({
	id = "office",
	fov = 58,
	ambient = { 160, 156, 142 },
	light = { 210, 204, 184 },
	blocks = officeBlocks,
	start = "office",
	scan = {
		origin = { 6, 4.2, -6.9 },
		dir = { 0, 0, -1 },
		count = 520,
		seed = 11,
		order = "sweep",
		half = 88,
		vhalf = 70,
		maxDist = 60,
		seconds = 4.2,
		size = 0.4,
	},
	cues = {
		office = {
			hold = 5,
			segs = {
				{
					seconds = 14,
					ease = "linear",
					from = { -16, 6.5, 16 },
					at = { 3, 3.6, -6 },
					toFrom = { -8, 5, 6 },
					toAt = { 3.5, 3.6, -8 },
					subjects = { { THEO_CHEST }, { SCANNER_AT } },
				},
			},
		},
		-- Theo walks to the back wall, puts his hand on it, and the wall begins to run. The cue
		-- holds until the melt is well under way; the rest plays on under his line.
		lean = {
			hold = 4.8,
			segs = {
				{
					seconds = 3.4,
					ease = "linear",
					from = { 10, 5, -1 },
					at = { 3, 3.5, -6 },
					toFrom = { 10, 4.7, -11 },
					toAt = { -1, 4, -21 },
					subjects = { { THEO_CHEST, { -2, 3.2, -23.4 } } },
				},
				{
					seconds = 2.4,
					from = { 10, 4.7, -11 },
					at = { -1, 4, -21 },
					toFrom = { 7.5, 4.4, -14 },
					toAt = { -1.2, 4.2, -25 },
					subjects = {
						{ { -2, 3.2, -23.4 }, { -2, 3.2, -24.2 } },
						{ { HOLE_X, 4, -25.4 } },
					},
				},
			},
		},
		-- Once he has said his half-line: he is pulled through, the lights stutter and die, and
		-- only the glowing hole is left. Never earlier than the end of the melt.
		dark = {
			hold = 2.5,
			after = { "lean", 5.8 },
			segs = {
				{
					seconds = 1,
					from = { 7.5, 4.4, -14 },
					at = { -1.2, 4.2, -25 },
					toFrom = { 6.5, 4.3, -16 },
					toAt = { -1, 4.2, -25.4 },
					subjects = { { { HOLE_X, 4, -25.4 } } },
				},
				{
					seconds = 1.5,
					from = { 6.5, 4.3, -16 },
					at = { -1, 4.2, -25.4 },
					toFrom = { 6.1, 4.3, -16.6 },
					subjects = { { { HOLE_X, 4, -25.4 } } },
				},
			},
		},
	},
})

-- The wake-up: a different room, drawn out of the dark by the scanner's dots -------------------

local DOOR_AT = { 0, 3.5, -20.2 }
local TV_AT = { -5, 2.6, -8 }

local function wakeBlocks(): { Block }
	local hidden: Flags = { hidden = true }
	local frame: Flags = { hidden = true, dot = "objective", weight = 10 }
	return {
		box("Floor", { 18, 1, 34 }, { 0, -0.5, -3 }, { 60, 60, 60 }, hidden),
		box("Ceiling", { 18, 1, 34 }, { 0, 9.5, -3 }, { 60, 60, 60 }, hidden),
		box("WallL", { 1, 9, 34 }, { -9.5, 4.5, -3 }, { 60, 60, 60 }, hidden),
		box("WallR", { 1, 9, 34 }, { 9.5, 4.5, -3 }, { 60, 60, 60 }, hidden),
		box("WallRear", { 18, 9, 1 }, { 0, 4.5, 14.5 }, { 60, 60, 60 }, hidden),
		box("WallFarL", { 7, 9, 1 }, { -5.5, 4.5, -20.5 }, { 60, 60, 60 }, hidden),
		box("WallFarR", { 7, 9, 1 }, { 5.5, 4.5, -20.5 }, { 60, 60, 60 }, hidden),
		box("Lintel", { 4, 2, 1 }, { 0, 8, -20.5 }, { 60, 60, 60 }, hidden),
		box("JambL", { 0.4, 7, 0.8 }, { -2.2, 3.5, -20.2 }, { 255, 205, 80 }, frame),
		box("JambR", { 0.4, 7, 0.8 }, { 2.2, 3.5, -20.2 }, { 255, 205, 80 }, frame),
		box("DoorHead", { 4.8, 0.4, 0.8 }, { 0, 7.2, -20.2 }, { 255, 205, 80 }, frame),
		box("FloorC", { 4.4, 1, 14 }, { 0, -0.5, -27.5 }, { 60, 60, 60 }, hidden),
		box("CeilingC", { 4.4, 1, 14 }, { 0, 7.5, -27.5 }, { 60, 60, 60 }, hidden),
		box("WallCL", { 1, 8, 14 }, { -2.7, 4, -27.5 }, { 60, 60, 60 }, hidden),
		box("WallCR", { 1, 8, 14 }, { 2.7, 4, -27.5 }, { 60, 60, 60 }, hidden),
		box("CorridorEnd", { 4.4, 8, 1 }, { 0, 4, -34.5 }, { 60, 60, 60 }, hidden),
		box(
			"Cart",
			{ 2.6, 1.6, 1.8 },
			{ -5, 0.8, -9 },
			{ 60, 60, 60 },
			{ hidden = true, weight = 3 }
		),
		box(
			"TVBody",
			{ 2.6, 2, 2 },
			{ -5, 2.6, -9 },
			{ 60, 60, 60 },
			{ hidden = true, weight = 5 }
		),
		box(
			"TVScreen",
			{ 2, 1.5, 0.1 },
			{ -5, 2.6, -7.95 },
			{ 60, 60, 60 },
			{ hidden = true, weight = 6 }
		),
		box(
			"Pillar",
			{ 1.6, 9, 1.6 },
			{ 5, 4.5, -6 },
			{ 60, 60, 60 },
			{ hidden = true, weight = 2 }
		),
		box("Crate", { 2, 2, 2 }, { 6, 1, -14 }, { 60, 60, 60 }, { hidden = true, weight = 2 }),
		box(
			"Crate",
			{ 1.4, 1.4, 1.4 },
			{ 7.4, 0.7, -12 },
			{ 60, 60, 60 },
			{ hidden = true, weight = 2 }
		),
		-- the warm smear of the wall he fell through, on the left wall: it fades
		box("Smear", { 0.1, 7, 3 }, { -8.92, 3.5, -2 }, { 255, 210, 140 }, {
			neon = true,
			decor = true,
			alpha = 0.55,
		}),
	}
end

room({
	id = "wake",
	fov = 58,
	ambient = { 6, 6, 8 },
	light = { 8, 8, 10 },
	blocks = wakeBlocks(),
	start = "wake",
	scan = {
		origin = { 1.1, 3.4, 9.6 },
		dir = { -0.03, 0, -1 },
		count = 560,
		seed = 29,
		order = "mix",
		half = 62,
		vhalf = 42,
		maxDist = 48,
		seconds = 5.2,
		size = 0.34,
	},
	cues = {
		wake = {
			hold = 3.8,
			segs = {
				{
					seconds = 10,
					ease = "linear",
					from = { 0, 4.6, 10 },
					at = { -0.5, 3.6, -14 },
					toFrom = { 0.3, 4.5, 6.8 },
					toAt = { -0.5, 3.6, -14 },
					subjects = { { DOOR_AT }, { TV_AT } },
				},
			},
		},
	},
})

-- The same office in the cold, when it is over --------------------------------------------------

local function morningBlocks(): { Block }
	local blocks = officeShell()
	-- the lens is dull until the scanner wakes by itself
	for _, block in blocks do
		if block.name == "ScannerLens" then
			block.neon = false
			block.color = { 50, 54, 62 }
		end
	end
	append(blocks, ceilingLights({ 150, 150, 146 }, false))
	for index, z in { -18, -8, 2, 12 } do
		table.insert(
			blocks,
			box("Window" .. index, { 0.1, 6, 5 }, { -19.4, 8, z }, { 214, 232, 255 }, NEON_DECOR)
		)
	end
	return blocks
end

room({
	id = "morning",
	fov = 58,
	ambient = { 138, 156, 186 },
	light = { 196, 212, 236 },
	blocks = morningBlocks(),
	start = "morning",
	scan = {
		origin = { 6, 4.2, -6.9 },
		dir = { 0, 0, -1 },
		count = 460,
		seed = 42,
		order = "sweep",
		half = 88,
		vhalf = 70,
		maxDist = 60,
		seconds = 5,
		size = 0.4,
	},
	cues = {
		morning = {
			hold = 2.6,
			segs = {
				{
					seconds = 8,
					from = { 6, 4.6, -2 },
					at = { 0, 3.8, -22 },
					toFrom = { 3, 4.4, -8 },
					toAt = { 0, 3.8, -22.5 },
					subjects = { { { 0, 3.2, -22.2 } } },
				},
			},
		},
		scan42 = {
			hold = 4,
			segs = {
				{
					seconds = 7,
					ease = "linear",
					from = { 3.8, 5, -1.5 },
					at = { 5, 4.2, -14 },
					toFrom = { 4.4, 4.9, -2.6 },
					toAt = { 5.5, 4.2, -14 },
					subjects = { { SCANNER_AT } },
				},
			},
		},
	},
})

-- The tapes -----------------------------------------------------------------------------------
--
-- Every tape but the Halden promo is one medium shot: the speaker behind a counter, filmed from
-- about 6 studs away through a narrow lens, so that their head and shoulders fill most of the
-- screen. Props live in the narrow window the lens sees: within about +-5 studs of the middle at
-- the back wall, and within +-2 near the speaker.

local TAPE_FOV = 34
local SPEAKER_EXTENT = { bottom = 3, top = 5.4, x = 0, z = -5.6 }
local MAIN_SEG: Seg = {
	seconds = 40,
	ease = "linear",
	from = { 0, 4.35, 0.9 },
	at = { 0, 4.3, -5.6 },
	toFrom = { 0.25, 4.45, 0.2 },
	toAt = { 0, 4.3, -5.6 },
	roll = 1.2,
	toRoll = -0.6,
	subjects = { { { 0, 4.5, -5.6 } } },
}

type Look = { wall: Color, floor: Color, ambient: Color, light: Color }

local function tapeShell(look: Look): { Block }
	return {
		box("Floor", { 60, 1, 44 }, { 0, -0.5, 0 }, look.floor),
		box("WallBack", { 60, 16, 1 }, { 0, 8, -12 }, look.wall),
		box("WallL", { 1, 16, 44 }, { -16, 8, 0 }, look.wall),
		box("WallR", { 1, 16, 44 }, { 16, 8, 0 }, look.wall),
	}
end

local WOOD = { 120, 92, 62 }

local function counter(width: number, color: Color): Block
	return box("Counter", { width, 3, 3.6 }, { 0, 1.5, -3.5 }, color)
end

local function bankerLamp(at: Vec): { Block }
	return {
		box("LampBase", { 0.9, 0.3, 0.9 }, at, { 40, 70, 52 }, DECOR),
		box("LampStem", { 0.2, 1.6, 0.2 }, { at[1], at[2] + 0.85, at[3] }, { 40, 70, 52 }, DECOR),
		box("LampShade", { 0.6, 1.6, 1.6 }, { at[1], at[2] + 1.75, at[3] }, { 34, 96, 66 }, {
			decor = true,
			shape = "cylinder",
			rot = { 0, 0, 90 },
		}),
		box("LampBulb", { 0.5, 0.5, 0.5 }, { at[1], at[2] + 1.35, at[3] }, { 255, 232, 160 }, {
			neon = true,
			decor = true,
			shape = "ball",
		}),
	}
end

local function tape(id: string, look: Look, extra: { Block }, cues: { [string]: Cue }?)
	local blocks = tapeShell(look)
	append(blocks, extra)
	local allCues: { [string]: Cue } = {
		tape = { segs = { MAIN_SEG }, fill = SPEAKER_EXTENT },
	}
	if cues then
		for name, cue in cues do
			allCues[name] = cue
		end
	end
	room({
		id = id,
		fov = TAPE_FOV,
		ambient = look.ambient,
		light = look.light,
		blocks = blocks,
		cues = allCues,
		start = "tape",
		bottom = SPEAKER_EXTENT.bottom,
	})
end

-- Ines's office ---------------------------------------------------------------------------------
do
	local extra = {
		box("Map", { 10, 6.5, 0.3 }, { 0, 6.2, -11.4 }, { 226, 218, 186 }),
		box("Map", { 3, 4, 0.3 }, { -4.3, 5.2, -11.3 }, { 212, 204, 176 }),
		counter(7, WOOD),
		box("Papers", { 1.4, 0.1, 1.1 }, { -1.2, 3.1, -3.4 }, { 236, 230, 210 }, DECOR),
	}
	for index = 1, 7 do
		table.insert(
			extra,
			box(
				"MapLine",
				{ 2 + (index % 3) * 1.4, 0.14, 0.2 },
				{ -3 + (index % 4) * 1.6, 3.8 + index * 0.55, -11.2 },
				{ 176, 52, 44 },
				{ decor = true, rot = { 0, 0, index * 11 - 30 } }
			)
		)
	end
	append(extra, bankerLamp({ 1.5, 3, -3.7 }))
	tape(
		"tape.orientation",
		{
			wall = { 104, 124, 112 },
			floor = { 78, 86, 80 },
			ambient = { 172, 180, 168 },
			light = { 230, 214, 170 },
		},
		extra,
		{
			reach = { hold = 1.4 },
			static = { hold = 0.9 },
		}
	)
end

-- The Halden promo: a lobby, a ribbon, and a door that is not on the plan -------------------------
do
	local look = {
		wall = { 120, 176, 214 },
		floor = { 226, 220, 206 },
		ambient = { 205, 205, 210 },
		light = { 255, 250, 236 },
	}
	local blocks = tapeShell(look)
	append(blocks, {
		box("Fountain", { 7, 1.2, 7 }, { 7, 0.6, -3 }, { 200, 200, 206 }),
		box("FountainWater", { 4, 1, 4 }, { 7, 1.6, -3 }, { 160, 210, 255 }),
		box("FountainJet", { 1, 5, 1 }, { 7, 3.8, -3 }, { 190, 235, 255 }, NEON),
		box("Reception", { 8, 3.4, 2.6 }, { -1, 1.7, -7.5 }, { 170, 150, 120 }),
		box("Ribbon", { 14, 0.5, 0.2 }, { -2, 3.4, 3 }, { 220, 40, 50 }, DECOR),
		box("PostL", { 0.3, 4, 0.3 }, { -9, 2, 3 }, { 210, 210, 214 }),
		box("PostR", { 0.3, 4, 0.3 }, { 5, 2, 3 }, { 210, 210, 214 }),
		box("Banner", { 16, 3, 0.3 }, { -9, 10, -11.4 }, { 255, 214, 90 }),
		box("Glass", { 6, 9, 0.2 }, { 1.5, 5.5, -11.4 }, { 150, 205, 240 }, DECOR),
		box("Glass", { 6, 9, 0.2 }, { 8, 5.5, -11.4 }, { 150, 205, 240 }, DECOR),
		box("Door", { 3, 7, 0.4 }, { -10, 3.5, -11.5 }, { 255, 226, 150 }, {
			neon = true,
			alpha = 1,
		}),
	})
	room({
		id = "tape.halden",
		fov = 46,
		ambient = look.ambient,
		light = look.light,
		blocks = blocks,
		start = "tape",
		cues = {
			tape = {
				segs = {
					{
						seconds = 14,
						from = { -9, 4.6, 9 },
						at = { -4, 4.5, -5 },
						toFrom = { 8, 4.6, 8 },
						toAt = { 4, 4.5, -5 },
						subjects = { { { -1, 3.8, -7.5 }, { 7, 2, 0.8 } } },
					},
				},
			},
			door = {
				hold = 3,
				segs = {
					{
						seconds = 6,
						from = { 3, 4.4, 6 },
						at = { -4, 4, -5 },
						toFrom = { -6, 3.8, -2 },
						toAt = { -10, 3.6, -11.5 },
						subjects = { { { -10, 3.5, -11.2 } } },
					},
				},
			},
			static = { hold = 0.9 },
		},
	})
end

-- Hollis: a corridor on a security monitor -------------------------------------------------------
do
	local extra = {
		counter(8, { 96, 98, 104 }),
		box("Pendant", { 1.4, 0.2, 1.4 }, { 0, 7.4, -7 }, { 230, 240, 255 }, NEON_DECOR),
		box("Carpet", { 60, 0.1, 6 }, { 0, 0.05, -8.5 }, { 70, 80, 90 }, DECOR),
	}
	for index, x in { -4.8, -1.6, 1.6, 4.8 } do
		table.insert(
			extra,
			box("DoorGrey", { 2.4, 6.4, 0.3 }, { x, 3.2, -11.4 }, { 70 + index * 4, 72, 78 })
		)
	end
	tape(
		"tape.hollis",
		{
			wall = { 118, 120, 126 },
			floor = { 92, 94, 98 },
			ambient = { 158, 160, 166 },
			light = { 200, 204, 214 },
		},
		extra,
		{
			fade = {},
			gone = {},
			static = { hold = 0.9 },
		}
	)
end

-- Tobi: a pump room and a cassette player ----------------------------------------------------------
do
	local extra = {
		counter(7, WOOD),
		box("Player", { 1.8, 1, 0.9 }, { -1.2, 3.5, -3.5 }, { 30, 32, 36 }, DECOR),
		box(
			"RecordLight",
			{ 0.25, 0.25, 0.1 },
			{ -0.65, 3.75, -3.02 },
			{ 255, 60, 50 },
			NEON_DECOR
		),
		box("Puddle", { 6, 0.12, 6 }, { 3, 0.06, -5 }, { 90, 160, 190 }, DECOR),
	}
	for index, y in { 4, 7 } do
		table.insert(
			extra,
			box("Pipe", { 60, 0.9, 0.9 }, { 0, y, -11 }, { 120 + index * 10, 140, 130 }, {
				decor = true,
				shape = "cylinder",
			})
		)
	end
	for index = 1, 5 do
		table.insert(
			extra,
			box(
				"Drip",
				{ 0.3, 0.45, 0.3 },
				{ 2 + index * 0.5, 9, -7 + (index % 3) },
				{ 170, 225, 255 },
				{ neon = true, decor = true, shape = "ball" }
			)
		)
	end
	tape(
		"tape.tobi",
		{
			wall = { 66, 110, 114 },
			floor = { 50, 76, 80 },
			ambient = { 138, 172, 178 },
			light = { 170, 220, 226 },
		},
		extra,
		{
			dim = {},
			static = { hold = 0.9 },
		}
	)
end

-- Ravi: a ward day room, with the Echo waiting behind him -----------------------------------------------
do
	local extra = {
		counter(7, { 190, 176, 150 }),
		box("Radio", { 1.8, 1, 0.8 }, { 1.5, 3.5, -3.4 }, { 60, 52, 44 }, DECOR),
		box("RadioLight", { 0.3, 0.3, 0.1 }, { 1.8, 3.6, -2.97 }, { 255, 190, 70 }, NEON_DECOR),
	}
	for index = 0, 9 do
		table.insert(
			extra,
			box(
				"Curtain",
				{ 1.4, 10, 0.4 },
				{ -6.1 + index * 1.35, 5.5, -11.2 },
				{ 110 + (index % 2) * 14, 150, 190 }
			)
		)
	end
	tape(
		"tape.ravi",
		{
			wall = { 160, 182, 160 },
			floor = { 124, 136, 122 },
			ambient = { 182, 192, 182 },
			light = { 230, 238, 220 },
		},
		extra,
		{
			echo = { subjects = { { { 2.4, 4.5, -8.8 } } } },
			static = { hold = 0.9 },
		}
	)
end

-- Quill: a slide projector and the corridor it throws -----------------------------------------------------
do
	local dark = { 60, 56, 52 }
	local extra = {
		counter(7, WOOD),
		box("Projector", { 2, 1.4, 2.2 }, { -2, 3.7, -3.5 }, { 40, 42, 48 }, DECOR),
		box("Slide", { 6, 4.2, 0.3 }, { 0, 5, -11.2 }, { 236, 230, 212 }),
		rod("Beam", { -2, 4.2, -3.4 }, { 0, 5, -11 }, 0.6, { 250, 246, 220 }, {
			neon = true,
			alpha = 0.9,
		}),
		box("VanishingDoor", { 0.7, 1.4, 0.05 }, { 2, 4.7, -11.02 }, dark, DECOR),
	}
	for index, rock in { { -4.6, 2.8 }, { -3, 3.6 }, { 3.6, 3.2 }, { 4.8, 4.2 } } do
		table.insert(
			extra,
			box("Rock", { 2.4, rock[2], 2.5 }, { rock[1], rock[2] / 2, -10.5 }, {
				86 + index * 6,
				72,
				62,
			})
		)
	end
	for index, corner in { { -2.8, 3.1 }, { 2.8, 3.1 }, { -2.8, 6.9 }, { 2.8, 6.9 } } do
		table.insert(
			extra,
			rod(
				"Perspective" .. index,
				{ corner[1], corner[2], -11.04 },
				{ 2, 4.7, -11.04 },
				0.07,
				dark
			)
		)
	end
	tape(
		"tape.quill",
		{
			wall = { 96, 80, 68 },
			floor = { 70, 60, 52 },
			ambient = { 150, 134, 122 },
			light = { 240, 208, 156 },
		},
		extra,
		{
			shape = { subjects = { { { 2.4, 4.2, -10.9 } } } },
			static = { hold = 0.9 },
		}
	)
end

-- Pike: the garage ------------------------------------------------------------------------------------------
do
	local extra = {
		counter(7, { 164, 168, 172 }),
		box("Car", { 5.5, 2.4, 3.4 }, { -3.4, 1.2, -9.5 }, { 70, 72, 84 }),
		box("CarRoof", { 3.4, 1.4, 3.2 }, { -3.2, 3.1, -9.5 }, { 60, 62, 74 }),
		box("Pillar", { 1.6, 16, 1.6 }, { 4, 8, -9 }, { 150, 144, 130 }),
		box("SodiumLamp", { 4, 0.3, 1 }, { 0, 7.2, -10.8 }, { 255, 176, 70 }, NEON_DECOR),
	}
	append(extra, bankerLamp({ 1.5, 3, -3.7 }))
	tape(
		"tape.pike",
		{
			wall = { 122, 100, 64 },
			floor = { 76, 68, 56 },
			ambient = { 190, 156, 96 },
			light = { 255, 196, 110 },
		},
		extra,
		{
			static = { hold = 0.9 },
		}
	)
end

-- The lamp room ------------------------------------------------------------------------------------------------

local LAMP_BULB = { 0, 10.4, -12 }
local BAR_Z = -9.6
local BOARD_AT = { -15.5, 6.2, -21 }

local function lampBlocks(): { Block }
	local brass = { 190, 150, 70 }
	local stone = { 46, 42, 38 }
	local blocks: { Block } = {
		-- the floor, with a shaft in it behind the Lamp (x -4..4, z -26..-16)
		box("FloorFront", { 60, 1, 40 }, { 0, -0.5, 4 }, stone),
		box("FloorBack", { 60, 1, 20 }, { 0, -0.5, -36 }, stone),
		box("FloorLeft", { 26, 1, 10 }, { -17, -0.5, -21 }, stone),
		box("FloorRight", { 26, 1, 10 }, { 17, -0.5, -21 }, stone),
		box("Desk", { 7, 3, 2.6 }, { 0, 1.5, -5.6 }, { 86, 62, 40 }),
		box("Papers", { 1.6, 0.1, 1.2 }, { 1.4, 3.1, -5.4 }, { 236, 230, 210 }, DECOR),
		box("Pedestal", { 4, 2.4, 4 }, { 0, 1.2, -12 }, { 92, 70, 36 }),
		box("LampBase", { 4.2, 0.6, 4.2 }, { 0, 2.7, -12 }, brass, DECOR),
		box("LampBody", { 7, 3.2, 3.2 }, { 0, 6, -12 }, brass, {
			decor = true,
			shape = "cylinder",
			rot = { 0, 0, 90 },
		}),
		box("LampBulb", { 4.8, 4.8, 4.8 }, LAMP_BULB, { 255, 247, 205 }, {
			neon = true,
			decor = true,
			shape = "ball",
		}),
		box("LampHalo", { 8.5, 8.5, 8.5 }, LAMP_BULB, { 255, 230, 160 }, {
			neon = true,
			decor = true,
			shape = "ball",
			alpha = 0.86,
		}),
		box("LampCrown", { 3.6, 0.6, 3.6 }, { 0, 13.2, -12 }, brass, DECOR),
		box("HandleBar", { 3.6, 0.4, 0.4 }, { 0, 3.95, BAR_Z }, brass, DECOR),
		box("HandlePost", { 0.4, 0.4, 0.9 }, { -1.5, 3.95, -10.1 }, brass, DECOR),
		box("HandlePost", { 0.4, 0.4, 0.9 }, { 1.5, 3.95, -10.1 }, brass, DECOR),
		box("LampPool", { 14, 0.05, 14 }, { 0, 0.03, -9 }, { 120, 98, 58 }, NEON_DECOR),
		-- the chalkboard rig
		box("Board", { 16, 9, 0.6 }, BOARD_AT, { 30, 44, 38 }),
		box("BoardPost", { 0.5, 6, 0.5 }, { -23.2, 3, -21 }, { 60, 50, 40 }),
		box("BoardPost", { 0.5, 6, 0.5 }, { -7.8, 3, -21 }, { 60, 50, 40 }),
		-- the ladder in its shaft
		box("ShaftBack", { 4.6, 36, 0.4 }, { 14, 18, -14.8 }, { 26, 24, 24 }),
		box("RailL", { 0.35, 32, 0.35 }, { 13.2, 16, -14 }, { 150, 120, 70 }, DECOR),
		box("RailR", { 0.35, 32, 0.35 }, { 14.8, 16, -14 }, { 150, 120, 70 }, DECOR),
		box("LadderLight", { 0.25, 1, 0.25 }, { 14, 0.6, -14.5 }, { 255, 240, 190 }, {
			neon = true,
			decor = true,
			alpha = 1,
		}),
		box("DoorL", { 0.2, 3.6, 0.2 }, { 12.9, 32.4, -14.5 }, { 214, 236, 255 }, {
			neon = true,
			decor = true,
			alpha = 1,
		}),
		box("DoorR", { 0.2, 3.6, 0.2 }, { 15.1, 32.4, -14.5 }, { 214, 236, 255 }, {
			neon = true,
			decor = true,
			alpha = 1,
		}),
		box("DoorHead", { 2.4, 0.2, 0.2 }, { 14, 34.3, -14.5 }, { 214, 236, 255 }, {
			neon = true,
			decor = true,
			alpha = 1,
		}),
	}
	for index = 0, 19 do
		table.insert(
			blocks,
			box(
				"Rung",
				{ 1.6, 0.18, 0.18 },
				{ 14, 1.2 + index * 1.5, -14 },
				{ 150, 120, 70 },
				DECOR
			)
		)
	end
	for index, spot in
		{ { -26, -6 }, { 26, -6 }, { -26, -34 }, { 26, -34 }, { -18, 14 }, { 18, 14 } }
	do
		table.insert(
			blocks,
			box("Column" .. index, { 2, 40, 2 }, { spot[1], 20, spot[2] }, { 30, 28, 28 })
		)
	end
	for index = 1, 6 do
		table.insert(
			blocks,
			box("Relay" .. index, { 0.9, 0.9, 0.9 }, { 0, -6 * index, -21 }, { 255, 214, 130 }, {
				neon = true,
				decor = true,
				shape = "ball",
				alpha = 1,
			})
		)
	end
	append(blocks, bankerLamp({ -2.4, 3, -5.4 }))
	return blocks
end

local INES_HEAD = { 0, 4.5, -7.4 }

room({
	id = "lamp",
	fov = 58,
	ambient = { 58, 54, 52 },
	light = { 150, 128, 96 },
	blocks = lampBlocks(),
	start = "lamp",
	cues = {
		-- a slow push in on Ines at her desk, the Lamp burning behind her
		lamp = {
			segs = {
				{
					seconds = 9,
					from = { 0, 5.6, 8 },
					at = { 0, 6, -9 },
					toFrom = { 0.4, 4.9, 1.4 },
					toAt = { 0, 5.6, -9 },
					subjects = { { INES_HEAD }, { LAMP_BULB } },
				},
			},
		},
		-- the board fills with dots; a corridor-shaped gap stays dark, then glows gold
		board = {
			hold = 3,
			segs = {
				{
					seconds = 4,
					from = { -2, 5.5, 2 },
					at = { -12, 6, -21 },
					toFrom = { -8, 5.8, -6 },
					toAt = { -15, 6.2, -21 },
					subjects = {
						{ { -15.5, 6.2, -20.6 } },
						{ { -22.5, 6.2, -20.6 } },
						{ { -8.5, 6.2, -20.6 } },
					},
				},
			},
		},
		-- a line of light runs up the shaft to a door edged in daylight
		ladder = {
			hold = 3,
			segs = {
				{
					seconds = 3.4,
					from = { 4, 5.5, 2 },
					at = { 14, 4, -14 },
					toFrom = { 4, 16, 6 },
					toAt = { 14, 24, -14 },
					subjects = { { { 14, 2, -14 }, { 14, 30, -14.2 } } },
				},
			},
		},
		climb = {
			hold = 5.4,
			segs = {
				{
					seconds = 5.2,
					ease = "linear",
					from = { 8, 3.5, -3 },
					at = { 14, 4, -13.6 },
					toFrom = { 9, 29, -2 },
					toAt = { 14, 31, -13.6 },
					subjects = { { { 14, 4, -13.6 }, { 14, 31, -13.6 } } },
				},
			},
		},
		take = {
			hold = 4.4,
			segs = {
				{
					seconds = 2.6,
					from = { -1, 5.5, 2 },
					at = { 0, 4.5, -8.5 },
					toFrom = { 0.5, 5.4, -1.6 },
					toAt = { 0, 4.4, -9.4 },
					subjects = { { { 0, 3.95, BAR_Z } }, { { 2.6, 3.2, -8.4 } } },
				},
				{
					seconds = 2,
					from = { 0.5, 5.4, -1.6 },
					at = { 0, 4.4, -9.4 },
					toFrom = { 0.8, 5.6, -2.6 },
					toAt = { 0, 5.4, -10 },
					subjects = { { { 0, 3.95, BAR_Z } } },
				},
			},
		},
		keep = {
			hold = 5.2,
			segs = {
				{
					seconds = 6.5,
					from = { 0, 6.5, -2.5 },
					at = { 0, 8.5, -12 },
					toFrom = { 0, 30, 2 },
					toAt = { 0, 3, -16 },
					subjects = { { LAMP_BULB }, { LAMP_BULB, { 0, -6, -21 } } },
				},
			},
		},
	},
})

--------------------------------------------------------------------------------------------
-- Which room a scene starts in

-- A `stage` set name and a scene id -> the id of the room to open. nil: no picture.
function StageData.roomFor(set: string, sceneId: string): string?
	if set == "office" then
		return "office"
	elseif set == "lamp" then
		return "lamp"
	elseif set == "tape" then
		if rooms[sceneId] and string.sub(sceneId, 1, 5) == "tape." then
			return sceneId
		end
		return "tape.orientation"
	end
	return nil
end

-- The room a cue switches to, for the cues that cut to somewhere else.
StageData.entries = { wake = "wake", morning = "morning" } :: { [string]: string }

return StageData
