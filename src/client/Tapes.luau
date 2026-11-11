--!strict
-- Tape screens in the world. Any part tagged Lidar_Tape with a string attribute Scene (a tape id
-- from LoreText) and a ProximityPrompt under it is a screen: a TV and VCR in Joss's closet, the
-- security monitor at the Night Desk, the intake room's television. Using its prompt plays that
-- tape. The player chooses it; nothing here ever starts a tape by itself, so a camp's surveyor
-- always gets to talk first (Surveyors waits for a scene to end, this waits for none to be
-- playing). A tape can be watched again.
-- A screen that is awake also flickers a little, so it draws the eye in a dark room.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cutscene = require(script.Parent.Cutscene)
local State = require(script.Parent.State)

local FLICKER_GAP = { 0.06, 0.4 } -- seconds between two flickers of one screen
local FLICKER_COLOR = 0.18 -- how far toward white the screen's colour wanders
local FLICKER_RANGE = 0.12 -- how much its light's reach wanders, as a share
local HIDDEN = 1 -- transparency of a screen the dark has not given back yet

type Screen = { part: BasePart, color: Color3, nextAt: number, baseRange: number? }

local Tapes = {}

local screens: { [BasePart]: Screen } = {}

local function track(instance: Instance)
	if not instance:IsA("BasePart") or screens[instance] ~= nil then
		return
	end
	screens[instance] = { part = instance, color = instance.Color, nextAt = 0, baseRange = nil }
	instance.Destroying:Connect(function()
		screens[instance] = nil
	end)
end

-- The tape a triggered prompt belongs to, if it sits under a tape screen.
local function sceneOf(prompt: ProximityPrompt): string?
	local part = prompt.Parent
	if part == nil or not CollectionService:HasTag(part, Config.Tags.tape) then
		return nil
	end
	local scene = part:GetAttribute("Scene")
	return if type(scene) == "string" and scene ~= "" then scene else nil
end

local function flicker(now: number)
	for part, screen in screens do
		if now >= screen.nextAt and part.Transparency < HIDDEN then
			screen.nextAt = now + FLICKER_GAP[1] + math.random() * (FLICKER_GAP[2] - FLICKER_GAP[1])
			part.Color = screen.color:Lerp(Color3.new(1, 1, 1), math.random() * FLICKER_COLOR)
			-- Only the reach of the light moves, never its brightness: the level's own light
			-- stutter (Immersion) keeps the brightness it first saw.
			local light = part:FindFirstChildOfClass("PointLight")
			if light ~= nil then
				if screen.baseRange == nil then
					screen.baseRange = light.Range
				end
				light.Range = screen.baseRange :: number
					* (1 + (math.random() - 0.5) * FLICKER_RANGE)
			end
		end
	end
end

function Tapes.start()
	for _, instance in CollectionService:GetTagged(Config.Tags.tape) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.tape):Connect(track)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer then
			return
		end
		local scene = sceneOf(prompt)
		if scene == nil or Cutscene.playing or State.menuOpen then
			return
		end
		Cutscene.play(scene)
	end)

	RunService.Heartbeat:Connect(function()
		flicker(os.clock())
	end)
end

return Tapes
