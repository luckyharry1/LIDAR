--!strict
-- Where the story's objects go in the maze, tier by tier. The words are LoreText's (docs/story);
-- this module only says which hidden objects and wall signs a level carries, what each one
-- looks like (a prop kit in src/server/Props) and how it glows once it has been revealed.
-- Adding a poster or a hidden object is a data change: add a line here.
--
-- Hidden objects ("reveals") are invisible until a scanner has put enough dots on them. Then
-- they light up part of the nearby floor and wall and say a few lines. Signs work the same way
-- but are only paper on a wall, so they glow very little. Lamp-bags are separate: they are lit
-- from the start, and `rev.nook.*` is what scanning one says.

local LoreText = require("./LoreText")

export type SignAt = "start" | "exit" | "pit" | "plate" | "any"
export type Glow = { color: { number }, radius: number }
export type Reveal = { id: string, kit: string, lines: { string }, glow: Glow, thought: string? }
export type Sign = { id: string, at: SignAt }
export type TierPlaces = { reveals: { string }, signs: { Sign } }

local GLOW_COLORS: { [string]: { number } } = {
	["amber"] = { 255, 200, 120 },
	["dim amber"] = { 214, 150, 86 },
	["warm white"] = { 255, 238, 214 },
	["pale green-white"] = { 226, 255, 226 },
	["cold white"] = { 214, 234, 255 },
}
local DEFAULT_GLOW = GLOW_COLORS["amber"]

local Places = {}

-- The prop kit drawn for each hidden object.
local KITS: { [string]: string } = {
	["poi.l0.desk"] = "desklamp",
	["poi.l0.whiteboard"] = "whiteboard",
	["poi.l0.vending"] = "teabags",
	["poi.l0.coat"] = "coat",
	["poi.l1.headphones"] = "headphones",
	["poi.l1.valve"] = "valvestation",
	["poi.l1.dinghy"] = "dinghy",
	["poi.l1.lifering"] = "lifering",
	["poi.l2.tapcode"] = "tapplate",
	["poi.l2.chart"] = "cardindex",
	["poi.l2.gurney"] = "pottingbench",
	["poi.l2.pa"] = "growlight",
	["poi.l3.camera"] = "camera",
	["poi.l3.crystal"] = "growlight",
	["poi.l4.stone"] = "cornerstone",
	["poi.l4.chalk"] = "chalkarrows",
}

-- Per tier: hidden objects (one own cell each) and signs (on a wall, in the cell they name).
Places.tiers = {
	[1] = {
		reveals = { "poi.l0.desk", "poi.l0.whiteboard" },
		signs = {
			{ id = "plaque.l0", at = "start" },
			{ id = "rule.04", at = "start" },
			{ id = "rule.03", at = "start" },
			{ id = "rule.02", at = "any" },
		},
	},
	[2] = {
		reveals = { "poi.l0.vending", "poi.l0.coat" },
		signs = {
			{ id = "rule.05", at = "any" },
			{ id = "rule.06", at = "any" },
			{ id = "sign.pit.1", at = "pit" },
		},
	},
	[3] = {
		reveals = { "poi.l1.headphones", "poi.l1.valve" },
		signs = {
			{ id = "plaque.l1", at = "start" },
			{ id = "rule.07", at = "any" },
			{ id = "sign.plate.1", at = "plate" },
			{ id = "sign.flood.grate", at = "pit" },
		},
	},
	[4] = {
		reveals = { "poi.l1.dinghy", "poi.l1.lifering" },
		signs = {
			{ id = "rule.09", at = "any" },
			{ id = "rule.08", at = "any" },
			{ id = "sign.plate.1", at = "plate" },
		},
	},
	[5] = {
		reveals = { "poi.l2.tapcode", "poi.l2.chart" },
		signs = {
			{ id = "plaque.l2", at = "start" },
			{ id = "rule.08", at = "any" },
			{ id = "sign.pit.2", at = "pit" },
			{ id = "sign.plate.2", at = "plate" },
		},
	},
	[6] = {
		reveals = { "poi.l2.gurney", "poi.l2.pa" },
		signs = {
			{ id = "rule.10", at = "any" },
			{ id = "sign.pit.2", at = "pit" },
			{ id = "sign.plate.2", at = "plate" },
		},
	},
	[7] = {
		reveals = { "poi.l3.camera", "poi.l3.crystal" },
		signs = {
			{ id = "plaque.l3", at = "start" },
			{ id = "rule.10", at = "any" },
			{ id = "sign.pit.3", at = "pit" },
		},
	},
	[8] = {
		reveals = { "poi.l4.stone", "poi.l4.chalk" },
		signs = {
			{ id = "plaque.l4", at = "start" },
			{ id = "rule.11", at = "any" },
			{ id = "sign.plate.3", at = "plate" },
			{ id = "sign.pit.3", at = "pit" },
		},
	},
} :: { [number]: TierPlaces }

local NO_PLACES: TierPlaces = { reveals = {}, signs = {} }

-- The hidden objects and signs of a tier. Endless tiers have none of their own.
function Places.forTier(tier: number): TierPlaces
	return Places.tiers[tier] or NO_PLACES
end

local function linesOf(id: string): { string }
	local entry = LoreText.get(id)
	assert(entry ~= nil, "missing story text " .. id)
	return entry.lines
end

-- A hidden object's look, lines and glow, from the story text.
function Places.reveal(id: string): Reveal
	local entry = LoreText.get(id)
	assert(entry ~= nil, "missing story text " .. id)
	local kit = KITS[id]
	assert(kit ~= nil, "no prop for " .. id)
	local glow = entry.glow
	local color = if glow then GLOW_COLORS[glow.color] or DEFAULT_GLOW else DEFAULT_GLOW
	return {
		id = id,
		kit = kit,
		lines = entry.lines,
		thought = entry.thought,
		glow = { color = color, radius = if glow then glow.radius else 6 },
	}
end

-- What a lamp-bag says when it is scanned: four variants, the fourth one burnt out.
Places.nookCount = 4
Places.deadNook = 4

function Places.nookLines(variant: number): { string }
	return linesOf("rev.nook." .. math.clamp(variant, 1, Places.nookCount))
end

function Places.nookGlow(variant: number): Glow
	local entry = LoreText.get("rev.nook." .. math.clamp(variant, 1, Places.nookCount))
	local glow = if entry then entry.glow else nil
	return {
		color = if glow then GLOW_COLORS[glow.color] or DEFAULT_GLOW else DEFAULT_GLOW,
		radius = if glow then glow.radius else 6,
	}
end

-- The printed text of a sign (a notice, a stencil, a page of the manual).
function Places.signLines(id: string): { string }
	return linesOf(id)
end

Places.kits = KITS

return Places
