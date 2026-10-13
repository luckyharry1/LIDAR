--!strict
-- Permanent upgrades bought with Static at the safe-room bench, plus cosmetics.
-- Cost of the next level = round(baseCost * costGrowth ^ currentLevel).

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
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

-- What each level does is defined in Progression.effects and tuned in Config.
Upgrades.list = {
	{
		id = "battery",
		name = "Capacitor",
		description = "The sweep recharges faster.",
		maxLevel = 4,
		baseCost = 40,
		costGrowth = 1.6,
	},
	{
		id = "cooling",
		name = "Quiet Shutter",
		description = "The sweep is quieter, so fewer things hear it.",
		maxLevel = 3,
		baseCost = 50,
		costGrowth = 1.7,
	},
	{
		id = "persistence",
		name = "Phosphor",
		description = "The world holds more dots before the oldest ones fade.",
		maxLevel = 4,
		baseCost = 45,
		costGrowth = 1.6,
	},
	{
		id = "lens",
		name = "Wide Lens",
		description = "Lets you open the spread much wider.",
		maxLevel = 1,
		baseCost = 120,
		costGrowth = 1,
	},
	{
		id = "radar",
		name = "Pulse Radar",
		description = "Every few seconds a ring of dots pulses out around you on its own. Level 2 pulses more often.",
		maxLevel = 2,
		baseCost = 130,
		costGrowth = 1.8,
		toggle = true,
	},
	{
		id = "marker",
		name = "Echo Beacon",
		description = "Your pings last longer and their sound lures things that listen.",
		maxLevel = 3,
		baseCost = 60,
		costGrowth = 1.6,
	},
	{
		id = "wayfinder",
		name = "Wayfinder",
		description = "Level 1: a needle that finds the exit once you have scanned it. Level 2: a map of what you have scanned.",
		maxLevel = 2,
		baseCost = 150,
		costGrowth = 2,
	},
	{
		id = "soles",
		name = "Soft Soles",
		description = "Your footsteps carry less far.",
		maxLevel = 3,
		baseCost = 55,
		costGrowth = 1.6,
	},
} :: { UpgradeDef }

Upgrades.cosmetics = {
	{
		id = "dots_amber",
		name = "Amber Phosphor",
		slot = "dots",
		cost = 80,
		color = { 235, 180, 110 },
	},
	{
		id = "dots_violet",
		name = "Violet Phosphor",
		slot = "dots",
		cost = 80,
		color = { 180, 150, 235 },
	},
	{
		id = "dots_mint",
		name = "Mint Phosphor",
		slot = "dots",
		cost = 80,
		color = { 150, 230, 205 },
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
