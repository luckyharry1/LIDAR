--!strict
-- Permanent upgrades bought with Static at the lore-room bench, plus cosmetics.
-- Cost of the next level = round(baseCost * costGrowth ^ currentLevel).

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
	perLevel: number, -- meaning depends on the upgrade; see Progression.effects
	toggle: boolean?, -- true when the player can switch the effect on and off
}

export type CosmeticDef = {
	id: string,
	name: string,
	slot: "dots" | "gun",
	cost: number,
	color: { number }, -- RGB
}

local Upgrades = {}

Upgrades.list = {
	{
		id = "battery",
		name = "Deep Cell",
		description = "Focus runs longer before the gun overheats.",
		maxLevel = 4,
		baseCost = 40,
		costGrowth = 1.6,
		perLevel = 0.85, -- heat rate multiplier per level
	},
	{
		id = "cooling",
		name = "Heat Sink",
		description = "The gun cools down faster.",
		maxLevel = 3,
		baseCost = 50,
		costGrowth = 1.7,
		perLevel = 0.25, -- extra cooling per level
	},
	{
		id = "persistence",
		name = "Phosphor",
		description = "Dots linger longer before they fade.",
		maxLevel = 4,
		baseCost = 45,
		costGrowth = 1.6,
		perLevel = 0.22, -- extra lifetime per level
	},
	{
		id = "lens",
		name = "Wide Lens",
		description = "A wider cone you can switch on for open rooms.",
		maxLevel = 1,
		baseCost = 120,
		costGrowth = 1,
		perLevel = 1.6, -- cone multiplier while switched on
		toggle = true,
	},
	{
		id = "marker",
		name = "Echo Beacon",
		description = "Your pings last longer and their sound lures things that listen.",
		maxLevel = 3,
		baseCost = 60,
		costGrowth = 1.6,
		perLevel = 8, -- extra seconds of ping lifetime per level
	},
	{
		id = "wayfinder",
		name = "Wayfinder",
		description = "Level 1: a needle that finds the exit once you have scanned it. Level 2: a map of what you have scanned.",
		maxLevel = 2,
		baseCost = 150,
		costGrowth = 2,
		perLevel = 1,
	},
	{
		id = "soles",
		name = "Soft Soles",
		description = "Your footsteps carry less far.",
		maxLevel = 3,
		baseCost = 55,
		costGrowth = 1.6,
		perLevel = 0.7, -- movement noise multiplier per level
	},
} :: { UpgradeDef }

Upgrades.cosmetics = {
	{
		id = "dots_amber",
		name = "Amber Phosphor",
		slot = "dots",
		cost = 80,
		color = { 255, 196, 120 },
	},
	{
		id = "dots_violet",
		name = "Violet Phosphor",
		slot = "dots",
		cost = 80,
		color = { 200, 170, 255 },
	},
	{
		id = "dots_mint",
		name = "Mint Phosphor",
		slot = "dots",
		cost = 80,
		color = { 170, 255, 225 },
	},
	{
		id = "gun_brass",
		name = "Brass Housing",
		slot = "gun",
		cost = 100,
		color = { 190, 150, 70 },
	},
	{
		id = "gun_signal",
		name = "Signal Housing",
		slot = "gun",
		cost = 100,
		color = { 220, 70, 50 },
	},
} :: { CosmeticDef }

Upgrades.byId = {} :: { [string]: UpgradeDef }
for _, def in Upgrades.list do
	Upgrades.byId[def.id] = def
end

Upgrades.cosmeticById = {} :: { [string]: CosmeticDef }
for _, def in Upgrades.cosmetics do
	Upgrades.cosmeticById[def.id] = def
end

return Upgrades
