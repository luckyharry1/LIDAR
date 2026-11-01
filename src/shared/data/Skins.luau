--!strict
-- Scanner skins: a look for the dots and the gun, picked on the start screen and at the
-- workbench. Looks only, never power: every skin gives the same scanner, so a skinned player and
-- a plain one face the same dark (docs/MONETIZATION.md).
--
-- Phosphor is the name for all of this in the game: the dots (phosphor) and the scanner that
-- draws them. A skin is a colour AND a scanner model (the gun's shape, built in client/Viewmodel).
--
-- A skin is unlocked one of four ways:
--   free      always available (only the plain default, which is the empty id)
--   playtime  earned by time spent in the dark (profile.stats.playSeconds), nothing to buy
--   static    bought once with Static at the workbench (profile.ownedSkins)
--   robux     a game pass. `pass` is a key of Config.Monetization.skinPassIds; the "pack" pass
--             unlocks every robux skin at once
--
-- Colours stay clear of the meaning colours: green is a friend, red is a monster, gold is an
-- objective, bright purple is a hazard. A skin only recolours white terrain dots (the wall tint)
-- and the gun housing.
--
-- The standard (default) dots are a cool grey-white, (196, 200, 210). The playtime skins are
-- muted on purpose: a faint tint, close to the default, a quiet reward. The Robux skins are fully
-- saturated and bright so they pop at a glance, for the player and for teammates.

export type SkinDef = {
	id: string,
	name: string,
	blurb: string,
	wall: { number }, -- RGB of the terrain dots
	gun: { number }, -- RGB of the gun housing
	model: string, -- the scanner's shape: one of Skins.models
	kind: "playtime" | "static" | "robux",
	minutes: number?, -- playtime skins: minutes in the dark that unlock it
	cost: number?, -- static skins: Static to buy it
	pass: string?, -- robux skins: key into Config.Monetization.skinPassIds
}

local Skins = {}

Skins.packKey = "pack"

-- The scanner shapes client/Viewmodel knows how to build. A new model needs a spec there too.
Skins.models = { "classic", "lantern", "dish", "prism", "blossom" }

-- Order is the order on screen: earned skins first, in the order they arrive, then bought ones.
Skins.list = {
	{
		id = "tungsten",
		model = "classic",
		name = "Tungsten",
		blurb = "Cozy and glowy, like a night light.",
		wall = { 214, 196, 160 },
		gun = { 112, 100, 80 },
		kind = "playtime",
		minutes = 15,
	},
	{
		id = "glacier",
		model = "classic",
		name = "Glacier",
		blurb = "Cool mint-teal, like glowing ice!",
		wall = { 150, 214, 196 },
		gun = { 62, 98, 112 },
		kind = "playtime",
		minutes = 45,
	},
	{
		id = "orchid",
		model = "lantern",
		name = "Orchid",
		blurb = "Dreamy periwinkle dots and a NEW lantern gun!",
		wall = { 140, 165, 235 },
		gun = { 70, 84, 124 },
		kind = "playtime",
		minutes = 90,
	},
	{
		id = "blueprint",
		model = "classic",
		name = "Blueprint",
		blurb = "Deep ultramarine dots with a golden gun. Fancy!",
		wall = { 5, 60, 205 },
		gun = { 205, 165, 70 },
		kind = "playtime",
		minutes = 180,
	},
	{
		id = "ember",
		name = "Ember",
		blurb = "Warm coral dots. Bought with Static at the workbench.",
		model = "classic",
		wall = { 230, 120, 110 },
		gun = { 150, 62, 52 },
		kind = "static",
		cost = 120,
	},
	{
		id = "plum",
		name = "Plum",
		blurb = "Juicy plum dots. Bought with Static at the workbench.",
		model = "classic",
		wall = { 170, 100, 170 },
		gun = { 100, 52, 104 },
		kind = "static",
		cost = 120,
	},
	{
		id = "rose",
		model = "blossom",
		name = "Rose Quartz",
		blurb = "Hot pink dots and a NEW flower-petal gun!",
		wall = { 255, 80, 170 },
		gun = { 230, 60, 140 },
		kind = "robux",
		pass = "rose",
	},
	{
		id = "aurora",
		model = "dish",
		name = "Aurora",
		blurb = "Electric teal dots and a NEW radar-dish gun!",
		wall = { 0, 190, 170 },
		gun = { 0, 140, 125 },
		kind = "robux",
		pass = "aurora",
	},
	{
		id = "nightbloom",
		model = "prism",
		name = "Nightbloom",
		blurb = "Bright violet dots and a NEW crystal-fin gun!",
		wall = { 95, 45, 235 },
		gun = { 70, 30, 200 },
		kind = "robux",
		pass = "nightbloom",
	},
} :: { SkinDef }

Skins.byId = {} :: { [string]: SkinDef }
for _, def in Skins.list do
	Skins.byId[def.id] = def
end

return Skins
