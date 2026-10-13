--!strict
-- Modal screens: title, settings, the upgrade bench, notes, the level-clear and survey
-- report cards, the daily board and the emote wheel. One window is open at a time; while one
-- is open the scanner and movement inputs are released and the mouse is freed.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Audio = require(script.Parent.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Dots = require(script.Parent.Dots)
local Enemies = require(ReplicatedStorage.Shared.data.Enemies)
local Input = require(script.Parent.Input)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.pure.Progression)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)
local Upgrades = require(ReplicatedStorage.Shared.data.Upgrades)

type Window = { frame: Frame, first: GuiObject?, onClose: (() -> ())? }

local CARD_SECONDS = 8
local TITLE_LETTERS = "L  I  D  A  R"

local Menus = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local backdrop: TextButton
local windows: { [string]: Window } = {}
local current: string? = nil
local titleStatus: TextLabel
local titleButtons: Frame
local benchList: Frame
local benchBalance: TextLabel
local benchCosmetics: Frame
local noteTitle: TextLabel
local noteBody: TextLabel
local clearBody: TextLabel
local clearInvite: TextButton
local clearCard: Frame
local clearCardBody: TextLabel
local reportBody: TextLabel
local boardBody: TextLabel
local settingsRows: Frame
local guideBody: TextLabel
local startRequested = false
local noteQueue: { { title: string, body: string } } = {}

local function send(name: string, ...: any)
	(Net.get(name) :: RemoteEvent):FireServer(...)
end

function Menus.isOpen(name: string?): boolean
	if name == nil then
		return current ~= nil
	end
	return current == name
end

function Menus.close()
	local name = current
	if name == nil then
		return
	end
	local window = windows[name]
	window.frame.Visible = false
	current = nil
	backdrop.Visible = false
	State.menuOpen = false
	Ui.focus(nil)
	Input.menuChanged()
	if window.onClose then
		window.onClose()
	end
end

function Menus.open(name: string)
	if current ~= nil and current ~= name then
		Menus.close()
	end
	local window = windows[name]
	window.frame.Visible = true
	current = name
	backdrop.Visible = true
	backdrop.BackgroundTransparency = if name == "title" then 1 else 0.45
	State.menuOpen = true
	Input.menuChanged()
	if Input.device == "gamepad" then
		Ui.focus(window.first)
	end
end

local function window(name: string, width: number, height: number, paper: boolean?): Frame
	local frame = Ui.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Visible = false,
		ZIndex = 2,
		Parent = gui,
	}, { Ui.padding(20) })
	if paper then
		frame.BackgroundColor3 = Ui.colors.paper
		frame.BackgroundTransparency = 0
	end
	windows[name] = { frame = frame, first = nil, onClose = nil }
	return frame
end

local function heading(parent: Instance, text: string): TextLabel
	return Ui.label({
		Text = text,
		FontFace = Ui.fontBold,
		TextSize = Ui.text.large,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = parent,
	})
end

local function closeButton(parent: Frame, name: string, text: string): TextButton
	local button = Ui.button({
		Name = "Close",
		Text = text,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(150, 38),
		Parent = parent,
	}, Menus.close)
	windows[name].first = button
	return button
end

-- Body text that scrolls when it outgrows its box, so long pages still fit a phone screen.
local function scrollBody(
	parent: Instance,
	position: UDim2,
	size: UDim2,
	properties: { [string]: any }
): TextLabel
	local scroller = Ui.new("ScrollingFrame", {
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = parent,
	})
	local label = Ui.label({
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	for key, value in properties do
		(label :: any)[key] = value
	end
	label.Parent = scroller
	return label
end

local function setBody(label: TextLabel, text: string)
	label.Text = text
	local scroller = label.Parent
	if scroller and scroller:IsA("ScrollingFrame") then
		scroller.CanvasPosition = Vector2.zero
	end
end

--------------------------------------------------------------------------------------------
-- Title

local function requestStart(mode: string)
	if startRequested or not State.profileLoaded then
		return
	end
	startRequested = true
	titleStatus.Text = "Stepping inside..."
	titleButtons.Visible = false
	send("Start", mode)
end

local function refreshTitle()
	if titleButtons == nil then
		return
	end
	for _, child in titleButtons:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	if not State.profileLoaded then
		titleStatus.Text = "Fetching your survey record..."
		return
	end
	local profile = State.profile
	local server = State.server
	local order = 0
	local first: GuiObject? = nil
	local function add(text: string, mode: string, accent: Color3?)
		order += 1
		local button = Ui.button({
			Text = text,
			Size = UDim2.fromOffset(320, 40),
			LayoutOrder = order,
			Parent = titleButtons,
		}, function()
			requestStart(mode)
		end, accent)
		first = first or button
	end
	if server.runActive then
		add("JOIN THE SURVEY", "continue", Ui.colors.good)
		titleStatus.Text = "A survey is under way on this server. You will join it."
	elseif not profile.tutorialDone then
		add("BEGIN", "new", Ui.colors.good)
		titleStatus.Text = "Everything is dark. You have a scanner."
	else
		if profile.checkpointTier > 1 then
			add("CONTINUE  /  TIER " .. profile.checkpointTier, "continue", Ui.colors.good)
			add("NEW SURVEY", "new")
		else
			add("BEGIN SURVEY", "new", Ui.colors.good)
		end
		add(
			if server.dailyDone then "DAILY SURVEY  /  RUN AGAIN" else "DAILY SURVEY",
			"daily",
			Ui.colors.gold
		)
		titleStatus.Text =
			`Visit {profile.streak.count}.  Best tier {profile.bestTier}.  {profile.static} Static.`
	end
	order += 1
	Ui.button({
		Text = "SETTINGS",
		Size = UDim2.fromOffset(320, 34),
		LayoutOrder = order,
		Parent = titleButtons,
	}, function()
		Menus.open("settings")
	end, Ui.colors.dim)
	windows.title.first = first
	if current == "title" and Input.device == "gamepad" then
		Ui.focus(first)
	end
end

local function buildTitle()
	local frame = window("title", 760, 380)
	frame.BackgroundTransparency = 1;
	(frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = false
	Ui.label({
		Text = TITLE_LETTERS,
		FontFace = Ui.fontBold,
		TextSize = Ui.text.hero,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 90),
		Parent = frame,
	})
	Ui.label({
		Text = "A SURVEY OF THE DARK",
		TextSize = Ui.text.body,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 90),
		Parent = frame,
	})
	titleButtons = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.fromOffset(320, 190),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 8) })
	titleStatus = Ui.label({
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = frame,
	})
end

--------------------------------------------------------------------------------------------
-- Settings

local function setting(key: string, value: any)
	(State.profile.settings :: { [string]: any })[key] = value
	send("SetSetting", key, value)
end

local function refreshSettings()
	for _, child in settingsRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local settings = State.profile.settings
	local order = 0
	local function row(label: string, value: string, onPress: () -> ())
		order += 1
		local frame = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = settingsRows,
		})
		Ui.label({ Text = label, Size = UDim2.new(0.55, 0, 1, 0), Parent = frame })
		Ui.button({
			Text = value,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.new(0.42, 0, 0, 34),
			Parent = frame,
		}, function()
			onPress()
			refreshSettings()
		end)
	end
	row(
		"DOT COLOURS",
		if settings.palette == "alt" then "WHITE / BLUE / ORANGE" else "WHITE / GREEN / RED",
		function()
			setting("palette", if settings.palette == "alt" then "default" else "alt")
			Menus.applyCosmetics()
		end
	)
	row("TEAMMATES' SCANS", if settings.sharedScans then "SHOWN" else "HIDDEN", function()
		setting("sharedScans", not settings.sharedScans)
	end)
	local modes = { auto = "hold", hold = "toggle", toggle = "auto" }
	row("SCAN BUTTON", string.upper(settings.scanMode), function()
		setting("scanMode", modes[settings.scanMode])
	end)
	row("VOLUME", math.floor(settings.volume * 100 + 0.5) .. "%", function()
		local nextVolume = settings.volume + 0.2
		setting("volume", if nextVolume > 1.01 then 0 else math.min(1, nextVolume))
	end)
	row("FREEZE DOTS (PHOTO)", if Dots.isFrozen() then "FROZEN" else "LIVE", function()
		Dots.setFrozen(not Dots.isFrozen())
	end)
end

local function buildSettings()
	local frame = window("settings", 560, 380)
	heading(frame, "SETTINGS")
	settingsRows = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -100),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 6) })
	closeButton(frame, "settings", "DONE")
	windows.settings.onClose = function()
		-- Settings opened from the title returns to it rather than dropping into the dark.
		if State.server.stage == "title" then
			task.defer(Menus.open, "title")
		end
	end
end

--------------------------------------------------------------------------------------------
-- Bench: upgrades and cosmetics

-- Applies palette and equipped cosmetics to the dot renderer.
function Menus.applyCosmetics()
	local profile = State.profile
	local tint = Upgrades.cosmeticById[profile.cosmetics.dots]
	Dots.setPalette(profile.settings.palette, if tint then tint.color else nil)
end

local function refreshBench()
	if benchList == nil then
		return
	end
	local profile = State.profile
	benchBalance.Text = "STATIC " .. profile.static
	for _, list in { benchList, benchCosmetics } do
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end
	for order, def in Upgrades.list do
		local level = profile.upgrades[def.id] or 0
		local cost = Progression.cost(profile, def.id)
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 58),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = benchList,
		})
		Ui.label({
			Text = string.upper(def.name) .. "  [" .. string.rep("#", level) .. string.rep(
				"-",
				def.maxLevel - level
			) .. "]",
			FontFace = Ui.fontBold,
			TextSize = Ui.text.small,
			Size = UDim2.new(0.7, 0, 0, 18),
			Parent = row,
		})
		Ui.label({
			Text = def.description,
			TextSize = Ui.text.small,
			TextColor3 = Ui.colors.dim,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(0.7, 0, 0, 36),
			Parent = row,
		})
		if cost ~= nil then
			local affordable = profile.static >= cost
			Ui.button({
				Text = cost .. " STATIC",
				TextSize = Ui.text.small,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.new(0.27, 0, 0, 34),
				Parent = row,
			}, function()
				send("BuyUpgrade", def.id)
			end, if affordable then Ui.colors.gold else Ui.colors.dim)
		elseif def.toggle then
			local on = profile.toggles[def.id] == true
			Ui.button({
				Text = if on then "ON" else "OFF",
				TextSize = Ui.text.small,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.new(0.27, 0, 0, 34),
				Parent = row,
			}, function()
				send("ToggleUpgrade", def.id, not on)
			end, if on then Ui.colors.good else Ui.colors.dim)
		else
			Ui.label({
				Text = "COMPLETE",
				TextSize = Ui.text.small,
				TextColor3 = Ui.colors.good,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.new(0.27, 0, 0, 34),
				Parent = row,
			})
		end
	end
	local order = 0
	local function cosmeticRow(
		slot: string,
		id: string,
		name: string,
		cost: number,
		color: { number }?
	)
		order += 1
		local owned = id == "" or profile.cosmetics.owned[id] == true
		local equipped = (profile.cosmetics :: { [string]: any })[slot] == id
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = benchCosmetics,
		})
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = if color
				then Color3.fromRGB(color[1], color[2], color[3])
				else Ui.colors.line,
			BorderSizePixel = 0,
			Parent = row,
		}, { Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		Ui.label({
			Text = string.upper(name),
			TextSize = Ui.text.small,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(0.55, -22, 1, 0),
			Parent = row,
		})
		if equipped then
			Ui.label({
				Text = "IN USE",
				TextSize = Ui.text.small,
				TextColor3 = Ui.colors.good,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0.4, 0, 1, 0),
				Parent = row,
			})
		else
			Ui.button({
				Text = if owned then "USE" else cost .. " STATIC",
				TextSize = Ui.text.small,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.new(0.4, 0, 0, 28),
				Parent = row,
			}, function()
				send("EquipCosmetic", slot, id)
			end, if owned or profile.static >= cost then Ui.colors.gold else Ui.colors.dim)
		end
	end
	cosmeticRow("dots", "", "Standard phosphor", 0, nil)
	cosmeticRow("gun", "", "Standard housing", 0, { 60, 62, 68 })
	for _, def in Upgrades.cosmetics do
		cosmeticRow(def.slot, def.id, def.name, def.cost, def.color)
	end
end

local function refreshGuide()
	local lines = {}
	local kinds = {}
	for kind in Enemies do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	for _, kind in kinds do
		local def = Enemies[kind]
		if State.profile.met[kind] then
			table.insert(lines, string.upper(def.displayName) .. "\n" .. def.rule)
		else
			table.insert(lines, "UNKNOWN\nSomething you have not met yet.")
		end
	end
	setBody(guideBody, table.concat(lines, "\n\n"))
end

local function buildBench()
	local frame = window("bench", 800, 380)
	heading(frame, "WORKBENCH")
	benchBalance = Ui.label({
		FontFace = Ui.fontBold,
		TextColor3 = Ui.colors.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(240, 28),
		Parent = frame,
	})
	benchList = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(0.6, -10, 1, -100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 6) })
	Ui.label({
		Text = "FINISHES",
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		Position = UDim2.new(0.6, 10, 0, 44),
		Size = UDim2.new(0.4, -10, 0, 18),
		Parent = frame,
	})
	benchCosmetics = Ui.new("ScrollingFrame", {
		Position = UDim2.new(0.6, 10, 0, 66),
		Size = UDim2.new(0.4, -10, 1, -122),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 4) })
	Ui.button({
		Text = "SURVEY REPORT",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(190, 38),
		Parent = frame,
	}, function()
		Menus.showReport()
	end)
	Ui.button({
		Text = "FIELD GUIDE",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 200, 1, 0),
		Size = UDim2.fromOffset(160, 38),
		Parent = frame,
	}, function()
		refreshGuide()
		Menus.open("guide")
	end)
	local kitButton = Ui.button({
		Text = "SURVEYOR'S KIT",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 370, 1, 0),
		Size = UDim2.fromOffset(180, 38),
		Visible = false,
		Parent = frame,
	}, function()
		MarketplaceService:PromptGamePassPurchase(player, State.meta.kitPassId)
	end, Ui.colors.gold)
	State.onProfile(function()
		local meta = State.meta
		kitButton.Visible = meta.kitPassId ~= 0 and not meta.ownsKit and meta.canPromptPurchase
	end)
	closeButton(frame, "bench", "CLOSE")

	local guide = window("guide", 620, 380)
	heading(guide, "FIELD GUIDE")
	guideBody = scrollBody(guide, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -100), {
		TextSize = Ui.text.small,
	})
	closeButton(guide, "guide", "CLOSE")
end

--------------------------------------------------------------------------------------------
-- Notes, level clear, report, daily board

local function buildNote()
	local frame = window("note", 600, 380, true)
	noteTitle = Ui.label({
		FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
		TextSize = Ui.text.large,
		TextColor3 = Ui.colors.paperInk,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = frame,
	})
	noteBody = scrollBody(frame, UDim2.fromOffset(0, 46), UDim2.new(1, 0, 1, -104), {
		FontFace = Ui.fontSerif,
		TextSize = Ui.text.body,
		TextColor3 = Ui.colors.paperInk,
		LineHeight = 1.25,
	});
	(noteBody.Parent :: ScrollingFrame).ScrollBarImageColor3 = Ui.colors.paperInk
	closeButton(frame, "note", "PUT IT BACK")
	windows.note.onClose = function()
		-- If another page arrived while this one was open, show it next.
		local nextNote = table.remove(noteQueue, 1)
		if nextNote then
			task.defer(Menus.showNote, nextNote.title, nextNote.body)
		end
	end
end

function Menus.showNote(title: string, body: string)
	if current == "note" then
		table.insert(noteQueue, { title = title, body = body })
		return
	end
	noteTitle.Text = title
	setBody(noteBody, body)
	Menus.open("note")
end

local function summaryText(summary: any): string
	local reward = summary.reward
	local lines = {
		`TIME            {Ui.formatTime(summary.seconds)}`,
		`BASE            {reward.base}`,
	}
	if reward.cells > 0 then
		table.insert(lines, `BATTERY CELLS   {reward.cells}`)
	end
	if reward.rescues > 0 then
		table.insert(lines, `SURVEYORS       {reward.rescues}`)
	end
	if reward.plate > 0 then
		table.insert(lines, `SURVEY PLATE    {reward.plate}`)
	end
	table.insert(
		lines,
		if reward.clean > 0
			then `NEVER CAUGHT    {reward.clean}`
			else `CAUGHT          {summary.catches}x`
	)
	if summary.total > reward.total then
		table.insert(lines, `DAILY BONUS     {summary.total - reward.total}`)
	end
	table.insert(lines, `STATIC          +{summary.total}`)
	return table.concat(lines, "\n")
end

local function buildClear()
	-- Modal version, used once to offer the friend invite.
	local frame = window("clear", 520, 380)
	heading(frame, "LEVEL CLEARED")
	clearBody = scrollBody(frame, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -150), {
		TextSize = Ui.text.body,
	})
	Ui.label({
		Text = "The dark is easier with someone else's dots in it.",
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -50),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = frame,
	})
	clearInvite = Ui.button({
		Text = "INVITE A FRIEND",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(220, 38),
		Parent = frame,
	}, function()
		Menus.invite()
	end, Ui.colors.good)
	closeButton(frame, "clear", "CONTINUE")
	windows.clear.first = clearInvite

	-- Non-modal card for every other clear: informative, never in the way.
	clearCard = Ui.panel({
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.fromOffset(300, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	}, { Ui.padding(12) })
	clearCardBody = Ui.label({
		TextSize = Ui.text.small,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = clearCard,
	})
end

function Menus.invite()
	task.spawn(function()
		local ok, canInvite = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and canInvite then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end
	end)
end

local function onLevelCleared(summary: any)
	Audio.levelCleared()
	local header = if summary.mode == "daily"
		then "DAILY SURVEY CLEARED"
		else `TIER {summary.tier} CLEARED  /  {string.upper(summary.name)}`
	local text = summaryText(summary)
	if summary.invite then
		setBody(clearBody, header .. "\n\n" .. text)
		Menus.open("clear")
		task.delay(CARD_SECONDS * 2, function()
			if current == "clear" then
				Menus.close()
			end
		end)
	else
		clearCardBody.Text = header .. "\n\n" .. text
		clearCard.Visible = true
		task.delay(CARD_SECONDS, function()
			clearCard.Visible = false
		end)
	end
end

local function buildReport()
	local frame = window("report", 520, 380)
	heading(frame, "SURVEY REPORT")
	reportBody = scrollBody(frame, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -100), {
		TextSize = Ui.text.body,
	})
	Ui.button({
		Text = "INVITE A FRIEND",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(220, 38),
		Parent = frame,
	}, function()
		Menus.invite()
	end, Ui.colors.good)
	closeButton(frame, "report", "CLOSE")
end

-- The post-run card: what this session added up to. A natural place to stop.
function Menus.showReport()
	local session = State.server.session
	local profile = State.profile
	local pages = 0
	for _ in profile.lore do
		pages += 1
	end
	setBody(
		reportBody,
		table.concat({
			"THIS SESSION",
			`LEVELS CLEARED  {session.levels}`,
			`DISTANCE        {session.distance} studs`,
			`LORE PAGES      {session.lore}`,
			`TIMES CAUGHT    {session.catches}`,
			`STATIC EARNED   {session.static}`,
			"",
			"ALL TIME",
			`BEST TIER       {profile.bestTier}`,
			`LORE PAGES      {pages}`,
			`SURVEYORS FOUND {profile.stats.rescues}`,
			"",
			"Your place is saved in this room.",
		}, "\n")
	)
	Menus.open("report")
end

local function buildBoard()
	local frame = window("board", 520, 380)
	heading(frame, "DAILY SURVEY")
	boardBody = scrollBody(frame, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -100), {
		TextSize = Ui.text.body,
	})
	closeButton(frame, "board", "CLOSE")
end

local function onDailyBoard(board: any)
	local lines = {
		`YOUR TIME   {Ui.formatTime(board.yourMs / 1000)}`,
		`YOUR BEST   {Ui.formatTime(board.bestMs / 1000)}`,
		"",
	}
	for rank, row in board.rows do
		local marker = if row.you then ">" else " "
		table.insert(
			lines,
			string.format(
				"%s %2d  %-20s %s",
				marker,
				rank,
				string.sub(row.name, 1, 20),
				Ui.formatTime(row.ms / 1000)
			)
		)
	end
	if #board.rows == 0 then
		table.insert(lines, "No times posted yet today.")
	end
	setBody(boardBody, table.concat(lines, "\n"))
	Menus.open("board")
end

--------------------------------------------------------------------------------------------
-- Emote wheel

local function buildEmotes()
	local frame = window("emotes", 320, 300)
	heading(frame, "SAY")
	local list = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 6) })
	for index, word in Config.Coop.emotes do
		local button = Ui.button({
			Text = string.upper(word),
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = index,
			Parent = list,
		}, function()
			send("Emote", index)
			Menus.close()
		end)
		if index == 1 then
			windows.emotes.first = button
		end
	end
end

--------------------------------------------------------------------------------------------

function Menus.start()
	gui = Ui.screen("Menus", 20)
	-- A Modal button frees the mouse while a window is open in first person.
	backdrop = Ui.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(4, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Modal = true,
		Visible = false,
		Parent = gui,
	})
	buildTitle()
	buildSettings()
	buildBench()
	buildNote()
	buildClear()
	buildReport()
	buildBoard()
	buildEmotes()

	State.onProfile(function()
		Menus.applyCosmetics()
		refreshTitle()
		refreshBench()
		refreshSettings()
	end)
	State.onState(function(server, previous)
		if server.stage ~= "title" and previous.stage == "title" then
			startRequested = false
			if current == "title" or current == "settings" then
				Menus.close()
			end
		elseif server.stage == "title" then
			refreshTitle()
		end
		if
			server.stage ~= "lore"
			and (current == "bench" or current == "guide" or current == "report")
		then
			Menus.close()
		end
	end)
	Input.onAction("emote", function()
		if State.server.partySize > 1 and State.server.stage ~= "title" then
			Menus.open("emotes")
		end
	end);
	(Net.get("OpenBench") :: RemoteEvent).OnClientEvent:Connect(function()
		refreshBench()
		Menus.open("bench")
	end);
	(Net.get("OpenNote") :: RemoteEvent).OnClientEvent:Connect(Menus.showNote);
	(Net.get("Ending") :: RemoteEvent).OnClientEvent:Connect(Menus.showNote);
	(Net.get("LevelCleared") :: RemoteEvent).OnClientEvent:Connect(onLevelCleared);
	(Net.get("DailyBoard") :: RemoteEvent).OnClientEvent:Connect(onDailyBoard)

	refreshSettings()
	refreshTitle()
	Menus.open("title")
end

return Menus
