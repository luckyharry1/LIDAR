--!strict
-- AnalyticsService events for tuning retention in the Creator Hub. Everything is gated by
-- Config.Telemetry.enabled and wrapped in pcall, so analytics can never break the game.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CURRENCY = "Static"
local PROGRESSION_PATH = "Run"

local Telemetry = {}

-- Onboarding funnel, in order. A step is logged at most once per player per session.
Telemetry.funnelSteps = {
	"Joined",
	"PressedPlay",
	"TutorialFirstScan",
	"TutorialComplete",
	"LevelOneCleared",
	"LoreRoomReached",
	"LevelThreeCleared",
}

local stepIndex: { [string]: number } = {}
for index, name in Telemetry.funnelSteps do
	stepIndex[name] = index
end

local logged: { [Player]: { [string]: boolean } } = {}

local function safely(action: () -> ())
	if not Config.Telemetry.enabled then
		return
	end
	local ok, message = pcall(action)
	if not ok then
		warn("[Telemetry] " .. tostring(message))
	end
end

function Telemetry.funnel(player: Player, stepName: string)
	local index = stepIndex[stepName]
	if index == nil then
		return
	end
	local seen = logged[player]
	if seen == nil then
		seen = {}
		logged[player] = seen
	end
	if seen[stepName] then
		return
	end
	seen[stepName] = true
	safely(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, index, stepName)
	end)
end

function Telemetry.levelStarted(player: Player, tier: number, name: string)
	safely(function()
		AnalyticsService:LogProgressionEvent(
			player,
			PROGRESSION_PATH,
			Enum.AnalyticsProgressionType.Start,
			tier,
			name
		)
	end)
end

function Telemetry.levelCleared(player: Player, tier: number, name: string)
	safely(function()
		AnalyticsService:LogProgressionEvent(
			player,
			PROGRESSION_PATH,
			Enum.AnalyticsProgressionType.Complete,
			tier,
			name
		)
	end)
end

function Telemetry.caught(player: Player, tier: number, name: string, enemyKind: string)
	safely(function()
		AnalyticsService:LogProgressionEvent(
			player,
			PROGRESSION_PATH,
			Enum.AnalyticsProgressionType.Fail,
			tier,
			name,
			{ [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = enemyKind }
		)
	end)
end

function Telemetry.earned(player: Player, amount: number, balance: number, reason: string)
	safely(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			CURRENCY,
			amount,
			balance,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			reason
		)
	end)
end

function Telemetry.spent(player: Player, amount: number, balance: number, item: string)
	safely(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			CURRENCY,
			amount,
			balance,
			Enum.AnalyticsEconomyTransactionType.Shop.Name,
			item
		)
	end)
end

-- A named counter, e.g. where players were when they quit.
function Telemetry.custom(player: Player, eventName: string, value: number)
	safely(function()
		AnalyticsService:LogCustomEvent(player, eventName, value)
	end)
end

function Telemetry.forget(player: Player)
	logged[player] = nil
end

return Telemetry
