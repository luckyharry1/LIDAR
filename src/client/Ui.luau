--!strict
-- One visual language for every screen: near-black panels, thin pale lines, monospace
-- capitals, and the same four accent colours the dots use. All interface code builds its
-- instances through here so sizes, fonts and safe-area handling stay consistent.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Ui = {}

Ui.colors = {
	ink = Color3.fromRGB(6, 8, 10),
	panel = Color3.fromRGB(14, 17, 22),
	line = Color3.fromRGB(226, 232, 245),
	dim = Color3.fromRGB(132, 142, 158),
	good = Color3.fromRGB(96, 240, 140),
	warn = Color3.fromRGB(255, 196, 96),
	bad = Color3.fromRGB(255, 84, 84),
	gold = Color3.fromRGB(255, 214, 110),
	paper = Color3.fromRGB(236, 229, 208),
	paperInk = Color3.fromRGB(44, 38, 30),
}

Ui.font = Font.fromEnum(Enum.Font.RobotoMono)
Ui.fontBold = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
Ui.fontSerif = Font.fromEnum(Enum.Font.Merriweather)

Ui.text = { small = 13, body = 16, large = 22, title = 34, hero = 84 }

-- Interfaces are laid out for this viewport and scaled to fit whatever the device has.
local DESIGN_WIDTH = 1180
local DESIGN_HEIGHT = 640
local MIN_SCALE = 0.55
local MAX_SCALE = 1.5

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local scales: { UIScale } = {}
local clickHandler: (() -> ())? = nil

local function currentScale(): number
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(DESIGN_WIDTH, DESIGN_HEIGHT)
	return math.clamp(math.min(size.X / DESIGN_WIDTH, size.Y / DESIGN_HEIGHT), MIN_SCALE, MAX_SCALE)
end

local function refreshScales()
	local scale = currentScale()
	for _, uiScale in scales do
		uiScale.Scale = scale
	end
end

-- Generic constructor: Ui.new("Frame", { Size = ... }, { child, child })
function Ui.new(className: string, properties: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	if properties then
		for key, value in properties do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if properties and properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

-- A ScreenGui that keeps clear of notches and the Roblox top bar, and scales with the viewport.
function Ui.screen(name: string, displayOrder: number): ScreenGui
	local gui = Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local uiScale = Ui.new("UIScale", { Scale = currentScale(), Parent = gui })
	table.insert(scales, uiScale)
	gui.Parent = playerGui
	return gui
end

-- A full-bleed ScreenGui for fades and backdrops: ignores insets and is never scaled.
function Ui.overlay(name: string, displayOrder: number): ScreenGui
	return Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		Parent = playerGui,
	})
end

function Ui.label(properties: { [string]: any }): TextLabel
	local label = Ui.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Ui.font,
		TextSize = Ui.text.body,
		TextColor3 = Ui.colors.line,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = "",
	})
	for key, value in properties do
		(label :: any)[key] = value
	end
	return label
end

function Ui.panel(properties: { [string]: any }, children: { Instance }?): Frame
	local frame = Ui.new("Frame", {
		BackgroundColor3 = Ui.colors.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Ui.new("UIStroke", { Color = Ui.colors.line, Transparency = 0.72, Thickness = 1 }),
	})
	for key, value in properties do
		(frame :: any)[key] = value
	end
	if children then
		for _, child in children do
			child.Parent = frame
		end
	end
	return frame
end

function Ui.padding(all: number): UIPadding
	return Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
	})
end

function Ui.list(direction: Enum.FillDirection, gap: number): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- A text button in the house style. `accent` tints the outline and text.
function Ui.button(
	properties: { [string]: any },
	onActivated: () -> (),
	accent: Color3?
): TextButton
	local color = accent or Ui.colors.line
	local stroke = Ui.new("UIStroke", {
		Color = color,
		Transparency = 0.45,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local button = Ui.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Ui.colors.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		FontFace = Ui.fontBold,
		TextSize = Ui.text.body,
		TextColor3 = color,
		Text = "",
		Selectable = true,
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0, 6) }),
		stroke,
	})
	for key, value in properties do
		(button :: any)[key] = value
	end
	local function highlight(on: boolean)
		button.BackgroundColor3 = if on then color else Ui.colors.panel
		button.TextColor3 = if on then Ui.colors.ink else color
		stroke.Transparency = if on then 0 else 0.45
	end
	button.MouseEnter:Connect(function()
		highlight(true)
	end)
	button.MouseLeave:Connect(function()
		highlight(false)
	end)
	button.SelectionGained:Connect(function()
		highlight(true)
	end)
	button.SelectionLost:Connect(function()
		highlight(false)
	end)
	button.Activated:Connect(function()
		if clickHandler then
			clickHandler()
		end
		highlight(false)
		onActivated()
	end)
	return button
end

-- Lets the audio controller hear every button press without Ui depending on it.
function Ui.onClick(handler: () -> ())
	clickHandler = handler
end

-- Moves gamepad focus to a control (no-op without a gamepad).
function Ui.focus(control: GuiObject?)
	GuiService.SelectedObject = control
end

function Ui.formatTime(seconds: number): string
	local whole = math.floor(seconds)
	return string.format("%d:%02d.%d", whole // 60, whole % 60, math.floor((seconds - whole) * 10))
end

local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
	end
	refreshScales()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

return Ui
