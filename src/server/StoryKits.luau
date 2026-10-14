--!strict
-- Prop kits for the story's hidden objects (src/shared/data/Places) and the small things that
-- sit beside a lamp-bag. Same conventions as Props.kits: boxes relative to a base on the floor,
-- back at local z = 0, the prop reaching toward -z, so a wall prop is placed with
-- CFrame.lookAt(pointOnWall, pointOnWall + inwardDirection).
-- None of these has a light of its own: the maze builder puts one near each hidden object when
-- it reveals itself, so they only need a shape that makes a good dot pattern.

export type Piece = {
	name: string?,
	size: { number },
	at: { number },
	rot: { number }?,
	color: { number },
	material: Enum.Material?,
	shape: Enum.PartType?,
	collide: boolean?,
	light: { color: { number }, brightness: number, range: number }?,
}

local WOOD = { 122, 86, 56 }
local DARK_WOOD = { 84, 58, 40 }
local METAL = { 128, 134, 140 }
local DARK_METAL = { 70, 74, 80 }
local PAPER = { 236, 230, 212 }
local WHITE = { 232, 234, 232 }
local BRASS = { 196, 160, 84 }
local WARM = { 255, 226, 170 }
local RED = { 190, 56, 48 }
local RUBBER = { 54, 58, 58 }
local STONE = { 104, 112, 112 }
local LEAF = { 74, 136, 66 }
local CLAY = { 156, 94, 62 }
local COAT = { 96, 88, 62 }
local TWO_PI = math.pi * 2

local wood = Enum.Material.Wood
local metal = Enum.Material.Metal
local plastic = Enum.Material.SmoothPlastic
local fabric = Enum.Material.Fabric
local neon = Enum.Material.Neon
local slate = Enum.Material.Slate
local cylinder = Enum.PartType.Cylinder
local ball = Enum.PartType.Ball

type Options = {
	rot: { number }?,
	shape: Enum.PartType?,
	collide: boolean?,
	name: string?,
}

-- Most pieces are small and walked through; a piece that should stop feet says collide = true.
local function piece(
	size: { number },
	at: { number },
	color: { number },
	material: Enum.Material,
	options: Options?
): Piece
	local extra = options or {}
	return {
		name = extra.name,
		size = size,
		at = at,
		rot = extra.rot,
		color = color,
		material = material,
		shape = extra.shape,
		collide = extra.collide == true,
	}
end

-- A ring of `count` boxes round a point on the wall: a life ring, a wreath.
local function ring(centre: { number }, radius: number, count: number): { Piece }
	local pieces = {}
	for step = 0, count - 1 do
		local angle = step / count * TWO_PI
		table.insert(
			pieces,
			piece(
				{ 0.9, 0.7, 0.5 },
				{
					centre[1] + math.cos(angle) * radius,
					centre[2] + math.sin(angle) * radius,
					centre[3],
				},
				if step % 2 == 0 then RED else WHITE,
				plastic,
				{ rot = { 0, 0, math.deg(angle) + 90 } }
			)
		)
	end
	return pieces
end

local lifering = ring({ 0, 5.4, -0.5 }, 1.5, 12)
table.insert(lifering, 1, piece({ 0.3, 0.3, 0.3 }, { 0, 7.4, -0.2 }, BRASS, metal))

local kits: { [string]: { Piece } } = {
	-- A desk lamp on an abandoned cubicle desk. Still warm.
	desklamp = {
		piece({ 4.4, 0.3, 2.4 }, { 0, 2.8, -1.3 }, WOOD, wood, { collide = true }),
		piece({ 0.3, 2.7, 2.2 }, { -2, 1.35, -1.3 }, DARK_WOOD, wood),
		piece({ 0.3, 2.7, 2.2 }, { 2, 1.35, -1.3 }, DARK_WOOD, wood),
		piece({ 1, 0.2, 1 }, { -1, 3.05, -1.3 }, DARK_METAL, metal),
		piece({ 0.15, 2.2, 0.15 }, { -1, 4.1, -1.3 }, DARK_METAL, metal, { rot = { 0, 0, 14 } }),
		piece({ 1.4, 0.5, 1.2 }, { -0.5, 5.3, -1.3 }, WARM, neon, { name = "Shade" }),
		piece({ 1.2, 0.05, 1.6 }, { 1.2, 3, -1.2 }, PAPER, plastic, { rot = { 0, 20, 0 } }),
	},
	-- A whiteboard in a meeting room: SURVEY RULES v1.
	whiteboard = {
		piece({ 6.6, 4.4, 0.2 }, { 0, 5.6, -0.1 }, METAL, metal),
		piece({ 6.2, 4, 0.12 }, { 0, 5.6, -0.26 }, WHITE, plastic),
		piece({ 3.8, 0.14, 0.06 }, { -0.8, 6.9, -0.34 }, DARK_METAL, plastic),
		piece({ 4.4, 0.14, 0.06 }, { -0.4, 6.3, -0.34 }, DARK_METAL, plastic),
		piece({ 2.6, 0.14, 0.06 }, { -1.5, 5.7, -0.34 }, DARK_METAL, plastic),
		piece({ 1.6, 0.14, 0.06 }, { -1.9, 5.1, -0.34 }, DARK_METAL, plastic),
		piece({ 5.2, 0.2, 0.45 }, { 0, 3.45, -0.3 }, METAL, metal),
	},
	-- A kettle on its side beside a shelf, a row of tea bags.
	teabags = {
		piece({ 5.4, 0.25, 1.4 }, { 0, 4, -0.7 }, DARK_WOOD, wood),
		piece(
			{ 1.6, 1.6, 1.6 },
			{ 1.6, 0.8, -1.4 },
			METAL,
			metal,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece({ 0.7, 0.4, 0.3 }, { -2.2, 4.35, -0.7 }, PAPER, plastic),
		piece({ 0.7, 0.4, 0.3 }, { -1.5, 4.35, -0.7 }, PAPER, plastic),
		piece({ 0.7, 0.4, 0.3 }, { -0.8, 4.35, -0.7 }, PAPER, plastic),
		piece({ 0.7, 0.4, 0.3 }, { -0.1, 4.35, -0.7 }, PAPER, plastic),
		piece({ 0.7, 0.4, 0.3 }, { 0.6, 4.35, -0.7 }, PAPER, plastic),
		piece({ 0.7, 0.4, 0.3 }, { 1.3, 4.35, -0.7 }, PAPER, plastic),
		piece({ 0.7, 0.4, 0.3 }, { 2, 4.35, -0.7 }, PAPER, plastic),
		piece({ 0.3, 3.2, 1.2 }, { -2.6, 2.4, -0.6 }, DARK_WOOD, wood),
		piece({ 0.3, 3.2, 1.2 }, { 2.6, 2.4, -0.6 }, DARK_WOOD, wood),
	},
	-- A custodian's coat on a hook, name tag HOLLIS.
	coat = {
		piece({ 1.6, 0.2, 0.6 }, { 0, 7, -0.3 }, DARK_METAL, metal),
		piece({ 2.1, 4.2, 0.7 }, { 0, 4.7, -0.6 }, COAT, fabric),
		piece({ 0.5, 0.3, 0.06 }, { 0.5, 5.9, -1 }, PAPER, plastic),
		piece({ 0.7, 0.9, 0.2 }, { -0.5, 3.8, -1 }, DARK_WOOD, fabric),
	},
	-- Headphones draped on a pipe, gain all the way up.
	headphones = {
		piece({ 6, 0.9, 0.9 }, { 0, 6.6, -0.7 }, DARK_METAL, metal, { shape = cylinder }),
		piece({ 0.25, 1.9, 0.25 }, { -0.8, 5.6, -0.7 }, RUBBER, plastic),
		piece({ 0.25, 1.9, 0.25 }, { 0.8, 5.6, -0.7 }, RUBBER, plastic),
		piece(
			{ 0.9, 0.9, 0.5 },
			{ -0.8, 4.5, -0.7 },
			RUBBER,
			plastic,
			{ shape = cylinder, rot = { 0, 90, 0 } }
		),
		piece(
			{ 0.9, 0.9, 0.5 },
			{ 0.8, 4.5, -0.7 },
			RUBBER,
			plastic,
			{ shape = cylinder, rot = { 0, 90, 0 } }
		),
		piece({ 0.1, 0.1, 2.4 }, { 0, 3.3, -1.4 }, RUBBER, plastic),
	},
	-- A valve wheel station with the wheel missing: a bare stem and a clean patch in the dust.
	valvestation = {
		piece(
			{ 5.4, 1.2, 1.2 },
			{ -2, 2.7, -0.8 },
			DARK_METAL,
			metal,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece({ 5, 0.9, 0.9 }, { 0.2, 5.4, -0.8 }, DARK_METAL, metal, { shape = cylinder }),
		piece({ 0.4, 1.4, 0.4 }, { 2.7, 6.1, -0.8 }, METAL, metal),
		piece(
			{ 0.2, 2.8, 2.8 },
			{ 2.7, 5.4, -0.9 },
			{ 150, 146, 138 },
			Enum.Material.Concrete,
			{ shape = cylinder, rot = { 0, 90, 0 } }
		),
		piece({ 0.1, 0.4, 1.4 }, { 2.7, 7.2, -0.4 }, BRASS, metal),
	},
	-- A half-sunk rubber dinghy. The oars are gone, and so is the third seat.
	dinghy = {
		piece({ 6.4, 1.1, 3 }, { 0, 0.55, -2 }, RUBBER, plastic, { collide = true }),
		piece(
			{ 6.4, 1.1, 1 },
			{ 0, 1.3, -0.8 },
			{ 82, 88, 88 },
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece(
			{ 6.4, 1.1, 1 },
			{ 0, 1.3, -3.2 },
			{ 82, 88, 88 },
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece({ 0.3, 0.2, 2.2 }, { -1.5, 1.2, -2 }, WOOD, wood),
		piece({ 0.3, 0.2, 2.2 }, { 0.2, 1.2, -2 }, WOOD, wood),
		piece({ 0.6, 0.1, 0.5 }, { 2.4, 1.1, -2 }, PAPER, plastic),
	},
	-- A life ring painted B3, hung before the water came.
	lifering = lifering,
	-- A grow light still humming over one living plant.
	growlight = {
		piece({ 4, 0.7, 2 }, { 0, 0.35, -1.2 }, CLAY, Enum.Material.Ground, { collide = true }),
		piece({ 2.2, 2.2, 2.2 }, { 0, 1.9, -1.2 }, LEAF, Enum.Material.Grass, { shape = ball }),
		piece({ 0.3, 6.4, 0.3 }, { -1.8, 3.2, -0.5 }, DARK_METAL, metal),
		piece({ 0.3, 6.4, 0.3 }, { 1.8, 3.2, -0.5 }, DARK_METAL, metal),
		piece({ 4.4, 0.3, 1.4 }, { 0, 6.5, -0.9 }, { 226, 255, 226 }, neon),
		piece({ 0.9, 0.9, 0.9 }, { 1, 2.9, -1.2 }, LEAF, Enum.Material.Grass, { shape = ball }),
	},
	-- A brass plate on a pillar: two taps, wait, one.
	tapplate = {
		piece({ 2.6, 11, 2.6 }, { 0, 5.5, -1.3 }, STONE, slate, { collide = true }),
		piece({ 1.7, 1.1, 0.1 }, { 0, 5, -2.65 }, BRASS, metal),
		piece({ 0.16, 0.16, 0.1 }, { -0.4, 5.1, -2.74 }, DARK_METAL, metal, { shape = ball }),
		piece({ 0.16, 0.16, 0.1 }, { 0.1, 5.1, -2.74 }, DARK_METAL, metal, { shape = ball }),
		piece({ 0.16, 0.16, 0.1 }, { 0.6, 4.9, -2.74 }, DARK_METAL, metal, { shape = ball }),
	},
	-- A cold camp stove with four mugs. Three are chipped.
	campstove = {
		piece({ 1.8, 1, 1.8 }, { 0, 0.5, -1.4 }, DARK_METAL, metal, { collide = true }),
		piece(
			{ 0.6, 0.5, 0.5 },
			{ 2.2, 0.2, -0.9 },
			PAPER,
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece(
			{ 0.6, 0.5, 0.5 },
			{ 2.9, 0.2, -1.7 },
			PAPER,
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece(
			{ 0.6, 0.5, 0.5 },
			{ -2.3, 0.2, -1.2 },
			PAPER,
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece(
			{ 0.6, 0.5, 0.5 },
			{ -1.6, 0.2, -2.3 },
			{ 220, 90, 90 },
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece({ 1.6, 0.15, 1.6 }, { 0, 1.1, -1.4 }, METAL, metal),
		piece({ 0.4, 0.3, 0.15 }, { -1.6, 0.6, -2.3 }, BRASS, metal),
	},
	-- A camera on a tripod, facing the corridor, the shutter half pressed.
	camera = {
		piece({ 0.2, 4.4, 0.2 }, { -0.9, 2.1, -1.2 }, DARK_METAL, metal, { rot = { 0, 0, 12 } }),
		piece({ 0.2, 4.4, 0.2 }, { 0.9, 2.1, -1.2 }, DARK_METAL, metal, { rot = { 0, 0, -12 } }),
		piece({ 0.2, 4.4, 0.2 }, { 0, 2.1, -2.2 }, DARK_METAL, metal, { rot = { 12, 0, 0 } }),
		piece({ 1.4, 1, 1 }, { 0, 4.7, -1.4 }, RUBBER, plastic),
		piece(
			{ 0.7, 0.7, 0.8 },
			{ 0, 4.7, -2.1 },
			DARK_METAL,
			metal,
			{ shape = cylinder, rot = { 0, 90, 0 } }
		),
		piece({ 0.25, 0.2, 0.25 }, { 0.4, 5.3, -1.4 }, { 190, 56, 48 }, plastic),
	},
	-- The foundation stone: the first thing built.
	cornerstone = {
		piece({ 3.4, 2.4, 3.4 }, { 0, 1.2, -1.8 }, STONE, slate, { collide = true }),
		piece({ 1.8, 1.1, 0.12 }, { 0, 1.4, -3.55 }, BRASS, metal),
		piece({ 3.8, 0.3, 3.8 }, { 0, 0.15, -1.8 }, { 82, 88, 88 }, slate),
	},
	-- Chalk arrows on the floor, still fresh.
	chalkarrows = {
		piece({ 3.2, 0.06, 0.22 }, { -2, 0.03, -1.6 }, WHITE, plastic, { rot = { 0, 20, 0 } }),
		piece({ 1, 0.06, 0.22 }, { -0.6, 0.03, -1.15 }, WHITE, plastic, { rot = { 0, 65, 0 } }),
		piece({ 1, 0.06, 0.22 }, { -0.7, 0.03, -1.95 }, WHITE, plastic, { rot = { 0, -25, 0 } }),
		piece({ 3.2, 0.06, 0.22 }, { 2.4, 0.03, -2.8 }, WHITE, plastic, { rot = { 0, 5, 0 } }),
		piece({ 1, 0.06, 0.22 }, { 3.8, 0.03, -2.65 }, WHITE, plastic, { rot = { 0, 50, 0 } }),
		piece({ 1, 0.06, 0.22 }, { 3.8, 0.03, -2.95 }, WHITE, plastic, { rot = { 0, -50, 0 } }),
		piece({ 0.9, 0.06, 0.35 }, { -2.8, 0.03, -3.4 }, WHITE, plastic, { rot = { 0, 70, 0 } }),
	},

	-- The Copy Room's copier, still warm; its output tray is where the page lies (note spot).
	copier = {
		piece({ 5, 3, 2.6 }, { 0, 1.5, -1.5 }, { 200, 200, 196 }, plastic, { collide = true }),
		piece(
			{ 4.8, 0.35, 2.4 },
			{ 0, 3.18, -1.5 },
			{ 168, 170, 168 },
			plastic,
			{ collide = true }
		),
		piece({ 1.4, 0.2, 0.8 }, { -1.4, 3.42, -0.9 }, DARK_METAL, plastic),
		piece({ 4, 0.12, 0.06 }, { 0, 2.2, -2.82 }, WARM, neon),
		piece({ 3, 0.12, 1.4 }, { 0, 2.4, -3.5 }, { 168, 170, 168 }, plastic, { collide = true }),
	},
	-- A pressure gauge on a panel, in the pump house.
	gauge = {
		piece({ 4.4, 3.6, 0.3 }, { 0, 5, -0.15 }, DARK_METAL, metal),
		piece(
			{ 0.2, 2.2, 2.2 },
			{ 0, 5.3, -0.4 },
			WHITE,
			plastic,
			{ shape = cylinder, rot = { 0, 90, 0 } }
		),
		piece({ 0.06, 1, 0.08 }, { 0.2, 5.5, -0.55 }, RED, plastic, { rot = { 0, 0, -25 } }),
		piece({ 0.7, 3.2, 0.7 }, { -1.8, 1.6, -0.6 }, DARK_METAL, metal, { collide = true }),
		piece({ 0.7, 3.2, 0.7 }, { 1.8, 1.6, -0.6 }, DARK_METAL, metal, { collide = true }),
	},
	-- A potting bench with clay pots, soil and seedlings.
	pottingbench = {
		piece({ 6.2, 0.3, 2.6 }, { 0, 3, -1.4 }, WOOD, wood, { collide = true }),
		piece({ 0.3, 2.9, 0.3 }, { -2.8, 1.45, -0.4 }, DARK_WOOD, wood),
		piece({ 0.3, 2.9, 0.3 }, { 2.8, 1.45, -0.4 }, DARK_WOOD, wood),
		piece({ 0.3, 2.9, 0.3 }, { -2.8, 1.45, -2.4 }, DARK_WOOD, wood),
		piece({ 0.3, 2.9, 0.3 }, { 2.8, 1.45, -2.4 }, DARK_WOOD, wood),
		piece({ 5.8, 0.2, 2.2 }, { 0, 1.2, -1.4 }, DARK_WOOD, wood),
		piece(
			{ 0.9, 0.9, 0.9 },
			{ -2.2, 3.6, -0.9 },
			CLAY,
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece(
			{ 0.9, 0.9, 0.9 },
			{ -1.1, 3.6, -1.3 },
			CLAY,
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece(
			{ 0.9, 0.9, 0.9 },
			{ 2.3, 3.6, -1 },
			CLAY,
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
		piece({ 0.8, 0.8, 0.8 }, { -2.2, 4.3, -0.9 }, LEAF, Enum.Material.Grass, { shape = ball }),
		piece({ 0.7, 0.7, 0.7 }, { 2.3, 4.2, -1 }, LEAF, Enum.Material.Grass, { shape = ball }),
		piece({ 1.6, 0.25, 1.2 }, { 0.6, 3.25, -1.7 }, { 60, 44, 34 }, Enum.Material.Ground),
	},
	-- A card index, one drawer open (the note lies on top).
	cardindex = {
		piece({ 4.4, 4.6, 2 }, { 0, 2.3, -1 }, DARK_WOOD, wood, { collide = true }),
		piece({ 1.3, 1.1, 0.1 }, { -1.5, 1, -2.05 }, WOOD, wood),
		piece({ 1.3, 1.1, 0.1 }, { 0, 1, -2.05 }, WOOD, wood),
		piece({ 1.3, 1.1, 0.1 }, { 1.5, 1, -2.05 }, WOOD, wood),
		piece({ 1.3, 1.1, 0.1 }, { -1.5, 2.5, -2.05 }, WOOD, wood),
		piece({ 1.3, 1.1, 0.1 }, { 1.5, 2.5, -2.05 }, WOOD, wood),
		piece({ 1.3, 1.1, 0.1 }, { -1.5, 4, -2.05 }, WOOD, wood),
		piece({ 1.3, 1.1, 0.1 }, { 0, 4, -2.05 }, WOOD, wood),
		piece({ 1.3, 1.1, 0.1 }, { 1.5, 4, -2.05 }, WOOD, wood),
		piece({ 1.3, 1, 1.3 }, { 0, 2.5, -2.7 }, WOOD, wood),
		piece({ 1.1, 0.12, 1.1 }, { 0, 3.05, -2.7 }, PAPER, plastic),
	},

	-- Beside a lamp-bag: a mug on the floor under it, a folding stool, a paper tag.
	nookmug = {
		piece(
			{ 0.7, 0.7, 0.7 },
			{ -1.2, 0.35, -1.6 },
			PAPER,
			plastic,
			{ shape = cylinder, rot = { 0, 0, 90 } }
		),
	},
	nookstool = {
		piece({ 1.6, 0.18, 1.6 }, { 2, 1.9, -1.6 }, WOOD, wood),
		piece({ 0.16, 1.8, 0.16 }, { 1.4, 0.9, -1.1 }, DARK_METAL, metal),
		piece({ 0.16, 1.8, 0.16 }, { 2.6, 0.9, -1.1 }, DARK_METAL, metal),
		piece({ 0.16, 1.8, 0.16 }, { 1.4, 0.9, -2.1 }, DARK_METAL, metal),
		piece({ 0.16, 1.8, 0.16 }, { 2.6, 0.9, -2.1 }, DARK_METAL, metal),
	},
	nooktag = {
		piece({ 0.5, 0.7, 0.05 }, { 0.5, 1.2, -1.45 }, PAPER, plastic),
	},
}

return kits
