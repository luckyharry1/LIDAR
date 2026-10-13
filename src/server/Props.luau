--!strict
-- Furniture and landmarks, each described as a kit of boxes relative to a base CFrame.
-- The base sits on the floor with its back at local z = 0; the prop extends toward local -z,
-- so a wall prop is placed with CFrame.lookAt(pointOnWall, pointOnWall + inwardDirection).
-- New props are data: add a kit and it can be placed anywhere.

local Build = require(script.Parent.Build)

type Piece = {
	size: { number },
	at: { number },
	rot: { number }?, -- degrees, XYZ
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
local FABRIC = { 150, 62, 52 }
local LEAF = { 74, 136, 66 }
local CLAY = { 156, 94, 62 }
local WARM = { 255, 226, 170 }
local BRASS = { 196, 160, 84 }
local PINK = { 255, 170, 210 }

local wood = Enum.Material.Wood
local metal = Enum.Material.Metal
local plastic = Enum.Material.SmoothPlastic
local fabric = Enum.Material.Fabric
local neon = Enum.Material.Neon
local cylinder = Enum.PartType.Cylinder
local ball = Enum.PartType.Ball

local Props = {}

Props.kits = {
	-- Maze landmarks: shapes chosen to make distinctive dot patterns.
	cabinet = {
		{ size = { 2.6, 6.2, 1.7 }, at = { 0, 3.1, -0.85 }, color = DARK_METAL, material = metal },
		{ size = { 1, 0.16, 0.2 }, at = { 0, 5.3, -1.8 }, color = METAL, material = metal },
		{ size = { 1, 0.16, 0.2 }, at = { 0, 3.8, -1.8 }, color = METAL, material = metal },
		{ size = { 1, 0.16, 0.2 }, at = { 0, 2.3, -1.8 }, color = METAL, material = metal },
		{ size = { 1, 0.16, 0.2 }, at = { 0, 0.8, -1.8 }, color = METAL, material = metal },
	},
	crates = {
		{
			size = { 2.6, 2.6, 2.6 },
			at = { -1.2, 1.3, -1.6 },
			rot = { 0, 8, 0 },
			color = DARK_WOOD,
			material = wood,
		},
		{
			size = { 2.2, 2.2, 2.2 },
			at = { 1.4, 1.1, -1.5 },
			rot = { 0, -14, 0 },
			color = WOOD,
			material = wood,
		},
		{
			size = { 1.8, 1.8, 1.8 },
			at = { -1.0, 3.5, -1.5 },
			rot = { 0, 26, 0 },
			color = WOOD,
			material = wood,
		},
	},
	pipes = {
		{
			size = { 13, 0.8, 0.8 },
			at = { 0, 8.2, -0.7 },
			color = DARK_METAL,
			material = metal,
			shape = cylinder,
			collide = false,
		},
		{
			size = { 13, 0.5, 0.5 },
			at = { 0, 9.3, -0.6 },
			color = METAL,
			material = metal,
			shape = cylinder,
			collide = false,
		},
		{
			size = { 0.4, 1.9, 0.9 },
			at = { -4, 8.7, -0.5 },
			color = DARK_METAL,
			material = metal,
			collide = false,
		},
		{
			size = { 0.4, 1.9, 0.9 },
			at = { 4, 8.7, -0.5 },
			color = DARK_METAL,
			material = metal,
			collide = false,
		},
	},
	stairs = {
		{ size = { 5, 1, 4.8 }, at = { 0, 0.5, -2.4 }, color = DARK_METAL },
		{ size = { 5, 1, 3.6 }, at = { 0, 1.5, -1.8 }, color = DARK_METAL },
		{ size = { 5, 1, 2.4 }, at = { 0, 2.5, -1.2 }, color = DARK_METAL },
		{ size = { 5, 1, 1.2 }, at = { 0, 3.5, -0.6 }, color = DARK_METAL },
		{ size = { 3.4, 6, 0.3 }, at = { 0, 7, -0.15 }, color = DARK_WOOD, material = wood },
		{ size = { 0.3, 3.2, 0.3 }, at = { -2.6, 3, -4.6 }, color = METAL, material = metal },
	},
	hum = {
		{ size = { 2.2, 2.8, 0.9 }, at = { 0, 5, -0.45 }, color = DARK_METAL, material = metal },
		{ size = { 0.35, 4.8, 0.35 }, at = { -0.6, 8.6, -0.3 }, color = METAL, material = metal },
		{ size = { 0.35, 4.8, 0.35 }, at = { 0.6, 8.6, -0.3 }, color = METAL, material = metal },
		{ size = { 0.5, 0.5, 0.2 }, at = { 0, 5.4, -1 }, color = METAL, material = metal },
	},
	-- Lit-room furniture.
	desk = {
		{ size = { 5.2, 0.3, 2.6 }, at = { 0, 2.9, -1.5 }, color = WOOD, material = wood },
		{ size = { 0.3, 2.8, 0.3 }, at = { -2.3, 1.4, -0.4 }, color = DARK_WOOD, material = wood },
		{ size = { 0.3, 2.8, 0.3 }, at = { -2.3, 1.4, -2.6 }, color = DARK_WOOD, material = wood },
		{ size = { 1.5, 2.2, 2.3 }, at = { 1.7, 1.6, -1.5 }, color = DARK_WOOD, material = wood },
		{
			size = { 1.2, 0.08, 1.6 },
			at = { -0.9, 3.1, -1.4 },
			rot = { 0, 12, 0 },
			color = PAPER,
			material = plastic,
			collide = false,
		},
	},
	chair = {
		{ size = { 1.7, 0.25, 1.7 }, at = { 0, 1.7, -0.9 }, color = FABRIC, material = fabric },
		{ size = { 1.7, 2, 0.25 }, at = { 0, 2.8, -0.15 }, color = FABRIC, material = fabric },
		{
			size = { 0.2, 1.6, 0.2 },
			at = { -0.7, 0.8, -0.2 },
			color = DARK_METAL,
			material = metal,
		},
		{ size = { 0.2, 1.6, 0.2 }, at = { 0.7, 0.8, -0.2 }, color = DARK_METAL, material = metal },
		{
			size = { 0.2, 1.6, 0.2 },
			at = { -0.7, 0.8, -1.6 },
			color = DARK_METAL,
			material = metal,
		},
		{ size = { 0.2, 1.6, 0.2 }, at = { 0.7, 0.8, -1.6 }, color = DARK_METAL, material = metal },
	},
	lamp = {
		{
			size = { 0.3, 1.6, 1.6 },
			at = { 0, 0.15, -0.9 },
			rot = { 0, 0, 90 },
			color = DARK_METAL,
			material = metal,
			shape = cylinder,
		},
		{ size = { 0.2, 5.6, 0.2 }, at = { 0, 3, -0.9 }, color = BRASS, material = metal },
		{
			size = { 1.5, 1.7, 1.7 },
			at = { 0, 6.2, -0.9 },
			rot = { 0, 0, 90 },
			color = WARM,
			material = neon,
			shape = cylinder,
			collide = false,
			light = { color = WARM, brightness = 1.4, range = 26 },
		},
	},
	shelf = {
		{ size = { 4.4, 7, 0.2 }, at = { 0, 3.5, -0.1 }, color = DARK_WOOD, material = wood },
		{ size = { 0.25, 7, 1.4 }, at = { -2.2, 3.5, -0.7 }, color = WOOD, material = wood },
		{ size = { 0.25, 7, 1.4 }, at = { 2.2, 3.5, -0.7 }, color = WOOD, material = wood },
		{ size = { 4.4, 0.2, 1.4 }, at = { 0, 1.4, -0.7 }, color = WOOD, material = wood },
		{ size = { 4.4, 0.2, 1.4 }, at = { 0, 3.4, -0.7 }, color = WOOD, material = wood },
		{ size = { 4.4, 0.2, 1.4 }, at = { 0, 5.4, -0.7 }, color = WOOD, material = wood },
		{ size = { 1.4, 1.5, 1 }, at = { -1.2, 2.3, -0.7 }, color = PAPER, material = plastic },
		{ size = { 1.1, 1.3, 1 }, at = { 0.9, 4.2, -0.7 }, color = FABRIC, material = plastic },
		{ size = { 1.6, 1.2, 1 }, at = { -0.8, 6.1, -0.7 }, color = BRASS, material = plastic },
	},
	table = {
		{ size = { 5, 0.3, 3.4 }, at = { 0, 2.8, -1.7 }, color = WOOD, material = wood },
		{ size = { 0.3, 2.7, 0.3 }, at = { -2.2, 1.35, -0.4 }, color = DARK_WOOD, material = wood },
		{ size = { 0.3, 2.7, 0.3 }, at = { 2.2, 1.35, -0.4 }, color = DARK_WOOD, material = wood },
		{ size = { 0.3, 2.7, 0.3 }, at = { -2.2, 1.35, -3 }, color = DARK_WOOD, material = wood },
		{ size = { 0.3, 2.7, 0.3 }, at = { 2.2, 1.35, -3 }, color = DARK_WOOD, material = wood },
	},
	plant = {
		{
			size = { 1.2, 1.3, 1.3 },
			at = { 0, 0.6, -0.9 },
			rot = { 0, 0, 90 },
			color = CLAY,
			material = plastic,
			shape = cylinder,
		},
		{
			size = { 2.3, 2.3, 2.3 },
			at = { 0, 2.3, -0.9 },
			color = LEAF,
			material = Enum.Material.Grass,
			shape = ball,
			collide = false,
		},
		{
			size = { 1.5, 1.5, 1.5 },
			at = { 0.5, 3.5, -0.7 },
			color = LEAF,
			material = Enum.Material.Grass,
			shape = ball,
			collide = false,
		},
	},
	rug = {
		{
			size = { 9, 0.12, 6 },
			at = { 0, 0.06, -3 },
			color = FABRIC,
			material = fabric,
			collide = false,
		},
		{
			size = { 7.6, 0.14, 4.6 },
			at = { 0, 0.07, -3 },
			color = { 190, 150, 110 },
			material = fabric,
			collide = false,
		},
	},
	board = {
		{
			size = { 5.4, 3.4, 0.2 },
			at = { 0, 5.4, -0.1 },
			color = { 176, 140, 96 },
			material = Enum.Material.Cardboard,
			collide = false,
		},
		{
			size = { 1.3, 1.6, 0.06 },
			at = { -1.6, 5.7, -0.24 },
			rot = { 0, 0, 4 },
			color = PAPER,
			material = plastic,
			collide = false,
		},
		{
			size = { 1.1, 1.3, 0.06 },
			at = { 0.1, 5.2, -0.24 },
			rot = { 0, 0, -6 },
			color = PAPER,
			material = plastic,
			collide = false,
		},
		{
			size = { 1.2, 1.5, 0.06 },
			at = { 1.7, 5.6, -0.24 },
			rot = { 0, 0, 3 },
			color = { 250, 236, 150 },
			material = plastic,
			collide = false,
		},
		{
			size = { 0.18, 0.18, 0.18 },
			at = { -1.6, 6.4, -0.3 },
			color = { 200, 50, 50 },
			material = plastic,
			shape = ball,
			collide = false,
		},
		{
			size = { 0.18, 0.18, 0.18 },
			at = { 0.1, 5.8, -0.3 },
			color = { 50, 90, 200 },
			material = plastic,
			shape = ball,
			collide = false,
		},
		{
			size = { 0.18, 0.18, 0.18 },
			at = { 1.7, 6.3, -0.3 },
			color = { 60, 160, 80 },
			material = plastic,
			shape = ball,
			collide = false,
		},
	},
	kettle = {
		{ size = { 2.2, 3, 1.6 }, at = { 0, 1.5, -0.8 }, color = METAL, material = metal },
		{
			size = { 0.9, 0.8, 0.8 },
			at = { 0, 3.45, -0.8 },
			rot = { 0, 0, 90 },
			color = DARK_METAL,
			material = metal,
			shape = cylinder,
		},
		{
			size = { 0.5, 0.15, 0.5 },
			at = { 0.6, 3.6, -0.8 },
			color = { 30, 30, 30 },
			material = plastic,
		},
		{
			size = { 0.5, 0.6, 0.5 },
			at = { -0.6, 3.3, -0.8 },
			rot = { 0, 0, 90 },
			color = PAPER,
			material = plastic,
			shape = cylinder,
		},
	},
	vending = {
		{
			size = { 3, 6.6, 2.2 },
			at = { 0, 3.3, -1.1 },
			color = { 60, 90, 110 },
			material = metal,
		},
		{
			size = { 2.2, 3.4, 0.1 },
			at = { -0.2, 4.4, -2.25 },
			color = { 190, 220, 230 },
			material = neon,
			collide = false,
			light = { color = { 190, 220, 235 }, brightness = 0.5, range = 12 },
		},
		{
			size = { 2.2, 0.9, 0.2 },
			at = { -0.2, 1.2, -2.25 },
			color = { 30, 34, 40 },
			material = plastic,
			collide = false,
		},
	},
	seedlings = {
		{ size = { 6, 0.3, 2.4 }, at = { 0, 2.8, -1.2 }, color = METAL, material = metal },
		{
			size = { 0.25, 2.7, 0.25 },
			at = { -2.8, 1.35, -0.3 },
			color = DARK_METAL,
			material = metal,
		},
		{
			size = { 0.25, 2.7, 0.25 },
			at = { 2.8, 1.35, -0.3 },
			color = DARK_METAL,
			material = metal,
		},
		{
			size = { 0.25, 2.7, 0.25 },
			at = { -2.8, 1.35, -2.1 },
			color = DARK_METAL,
			material = metal,
		},
		{
			size = { 0.25, 2.7, 0.25 },
			at = { 2.8, 1.35, -2.1 },
			color = DARK_METAL,
			material = metal,
		},
		{
			size = { 5.4, 0.4, 1.8 },
			at = { 0, 3.15, -1.2 },
			color = { 60, 44, 34 },
			material = Enum.Material.Ground,
		},
		{
			size = { 0.5, 0.7, 0.5 },
			at = { -2, 3.6, -1.2 },
			color = LEAF,
			material = Enum.Material.Grass,
			shape = ball,
			collide = false,
		},
		{
			size = { 0.6, 0.9, 0.6 },
			at = { -1, 3.7, -0.9 },
			color = LEAF,
			material = Enum.Material.Grass,
			shape = ball,
			collide = false,
		},
		{
			size = { 0.5, 0.6, 0.5 },
			at = { 0, 3.6, -1.4 },
			color = LEAF,
			material = Enum.Material.Grass,
			shape = ball,
			collide = false,
		},
		{
			size = { 0.7, 1.1, 0.7 },
			at = { 1, 3.8, -1.1 },
			color = LEAF,
			material = Enum.Material.Grass,
			shape = ball,
			collide = false,
		},
		{
			size = { 0.5, 0.8, 0.5 },
			at = { 2, 3.7, -1.3 },
			color = LEAF,
			material = Enum.Material.Grass,
			shape = ball,
			collide = false,
		},
		{
			size = { 5.6, 0.25, 1 },
			at = { 0, 6.2, -1.2 },
			color = PINK,
			material = neon,
			collide = false,
			light = { color = PINK, brightness = 1.1, range = 18 },
		},
		{
			size = { 0.15, 3, 0.15 },
			at = { -2.6, 7.8, -1.2 },
			color = DARK_METAL,
			material = metal,
			collide = false,
		},
		{
			size = { 0.15, 3, 0.15 },
			at = { 2.6, 7.8, -1.2 },
			color = DARK_METAL,
			material = metal,
			collide = false,
		},
	},
	bench = {
		{ size = { 6.4, 0.4, 2.8 }, at = { 0, 3, -1.4 }, color = DARK_WOOD, material = wood },
		{
			size = { 0.4, 2.8, 2.6 },
			at = { -2.9, 1.4, -1.4 },
			color = DARK_METAL,
			material = metal,
		},
		{ size = { 0.4, 2.8, 2.6 }, at = { 2.9, 1.4, -1.4 }, color = DARK_METAL, material = metal },
		{
			size = { 6.4, 3, 0.25 },
			at = { 0, 5, -0.12 },
			color = { 96, 102, 108 },
			material = metal,
		},
		{
			size = { 1.6, 0.9, 1.1 },
			at = { -1.8, 3.65, -1.4 },
			color = DARK_METAL,
			material = metal,
		},
		{
			size = { 0.3, 0.3, 1.6 },
			at = { 0.4, 3.35, -1.5 },
			rot = { 0, 20, 0 },
			color = BRASS,
			material = metal,
			collide = false,
		},
		{
			size = { 0.5, 0.5, 0.5 },
			at = { 2.2, 3.5, -1.2 },
			color = { 120, 255, 170 },
			material = neon,
			shape = ball,
			collide = false,
			light = { color = { 140, 255, 190 }, brightness = 0.8, range = 10 },
		},
	},
	cradle = {
		{ size = { 2.4, 0.5, 1.6 }, at = { 0, 0.25, -0.8 }, color = DARK_METAL, material = metal },
		{ size = { 0.4, 1.2, 0.4 }, at = { -0.8, 1.1, -0.8 }, color = BRASS, material = metal },
		{ size = { 0.4, 1.2, 0.4 }, at = { 0.8, 1.1, -0.8 }, color = BRASS, material = metal },
	},
} :: { [string]: { Piece } }

-- Builds a kit at a base CFrame. Returns the model; its PrimaryPart is the first piece.
function Props.place(kind: string, base: CFrame, parent: Instance): Model
	local kit = Props.kits[kind]
	assert(kit ~= nil, "unknown prop " .. kind)
	local model = Build.model(kind, parent)
	for index, piece in kit do
		local offset = CFrame.new(piece.at[1], piece.at[2], piece.at[3])
		if piece.rot then
			offset *= CFrame.Angles(
				math.rad(piece.rot[1]),
				math.rad(piece.rot[2]),
				math.rad(piece.rot[3])
			)
		end
		local part = Build.part({
			name = "Piece" .. index,
			size = Vector3.new(piece.size[1], piece.size[2], piece.size[3]),
			cframe = base * offset,
			color = Build.rgb(piece.color),
			material = piece.material,
			shape = piece.shape,
			collide = piece.collide,
			parent = model,
		})
		if piece.light then
			Build.pointLight(
				part,
				Build.rgb(piece.light.color),
				piece.light.brightness,
				piece.light.range
			)
		end
		if index == 1 then
			model.PrimaryPart = part
		end
	end
	return model
end

return Props
