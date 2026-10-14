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
export type Reveal = { id: string, kit: string, lines: { string }, glow: Glow }
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
	["rev.annex.lamp"] = "desklamp",
	["rev.annex.whiteboard"] = "whiteboard",
	["rev.annex.kettle"] = "teabags",
	["rev.annex.coat"] = "coat",
	["rev.flood.headphones"] = "headphones",
	["rev.flood.valve"] = "valvestation",
	["rev.flood.boat"] = "dinghy",
	["rev.flood.lifering"] = "lifering",
	["rev.over.greenhouse"] = "growlight",
	["rev.over.tapcode"] = "tapplate",
	["rev.over.camp"] = "campstove",
	["rev.found.camera"] = "camera",
	["rev.found.stone"] = "cornerstone",
	["rev.found.chalk"] = "chalkarrows",
}

-- Per tier: hidden objects (one own cell each) and signs (on a wall, in the cell they name).
Places.tiers = {
	[1] = {
		reveals = { "rev.annex.lamp", "rev.annex.whiteboard" },
		signs = {
			{ id = "sign.intake.1", at = "start" },
			{ id = "sign.intake.2", at = "start" },
			{ id = "sign.intake.5", at = "start" },
			{ id = "sign.annex.1", at = "any" },
		},
	},
	[2] = {
		reveals = { "rev.annex.kettle", "rev.annex.coat" },
		signs = {
			{ id = "sign.annex.2", at = "any" },
			{ id = "sign.annex.3", at = "any" },
			{ id = "sign.pit.1", at = "pit" },
		},
	},
	[3] = {
		reveals = { "rev.flood.headphones", "rev.flood.valve" },
		signs = {
			{ id = "sign.flood.1", at = "any" },
			{ id = "sign.plate.1", at = "plate" },
			{ id = "sign.flood.grate", at = "pit" },
		},
	},
	[4] = {
		reveals = { "rev.flood.boat", "rev.flood.lifering" },
		signs = {
			{ id = "sign.flood.2", at = "any" },
			{ id = "rule.09", at = "any" },
			{ id = "sign.plate.1", at = "plate" },
		},
	},
	[5] = {
		reveals = { "rev.over.greenhouse", "rev.over.tapcode" },
		signs = {
			{ id = "sign.over.1", at = "any" },
			{ id = "sign.over.2", at = "any" },
			{ id = "sign.pit.2", at = "pit" },
			{ id = "sign.plate.2", at = "plate" },
		},
	},
	[6] = {
		reveals = { "rev.over.camp" },
		signs = {
			{ id = "sign.over.1", at = "any" },
			{ id = "sign.pit.2", at = "pit" },
			{ id = "sign.plate.2", at = "plate" },
		},
	},
	[7] = {
		reveals = { "rev.found.chalk", "rev.found.camera" },
		signs = {
			{ id = "sign.found.1", at = "start" },
			{ id = "sign.found.2", at = "any" },
			{ id = "sign.pit.3", at = "pit" },
		},
	},
	[8] = {
		reveals = { "rev.found.stone", "rev.found.chalk" },
		signs = {
			{ id = "sign.found.3", at = "any" },
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
