--!strict
-- Modal screens: title, settings, the upgrade bench, notes, the level-clear and survey
-- report cards, the daily board and the emote wheel. One window is open at a time; while one
-- is open the scanner and movement inputs are released and the mouse is freed.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Audio = require(script.Parent.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Dots = require(script.Parent.Dots)
local DotRules = require(ReplicatedStorage.Shared.pure.DotRules)
local Enemies = require(ReplicatedStorage.Shared.data.Enemies)
local Input = require(script.Parent.Input)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.pure.Progression)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)
local Upgrades = require(ReplicatedStorage.Shared.data.Upgrades)

type Window = { frame: Frame, first: GuiObject?, onClose: (() -> ())? }
type LobbyEntry = State.LobbyEntry

local CARD_SECONDS = 8
local DOT_QUALITY_NEXT = { auto = "low", low = "medium", medium = "high", high = "auto" }
local TITLE_LETTERS = "L  I  D  A  R"

local Menus = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local backdrop: TextButton
local windows: { [string]: Window } = {}
local current: string? = nil
local titleStatus: TextLabel
local titleButtons: Frame
local titleNotices: Frame
local noticeOrder = 0
local partyList: ScrollingFrame
local partyStatus: TextLabel
local partyReady: TextButton
local partyStart: TextButton
local refreshParty: () -> () -- defined with the Play Together screen below
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
local settingsRows: ScrollingFrame
local guideBody: TextLabel
local startRequested = false
local noteQueue: { { title: string, body: string } } = {}
local endingTitle: TextLabel
local endingBody: TextLabel
local pendingEnding: { title: string, body: string }? = nil

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

local STAGE_WORDS = {
	title = "ON THE TITLE",
	tutorial = "IN THE INTAKE",
	level = "IN THE DARK",
	downed = "IN THE DARK",
	lore = "IN A SAFE ROOM",
	passage = "ON THE STAIRS",
}
local NOTICE_SECONDS = 10
local NOTICE_LIMIT = 2

-- The mode the main button would start: carry on from the checkpoint, or a new survey.
local function defaultMode(): string
	return if State.profile.checkpointTier > 1 then "continue" else "new"
end

local function requestStart(mode: string, together: boolean?)
	if startRequested or not State.profileLoaded then
		return
	end
	startRequested = true
	titleStatus.Text = if together then "Taking everyone in..." else "Stepping inside..."
	titleButtons.Visible = false
	if current == "party" then
		Menus.open("title") -- shows the status line while the server builds the level
	end
	send(if together then "PartyStart" else "Start", mode)
end

-- Messages that arrive while the title is up (the visit streak, a saving problem) are shown
-- under the buttons instead of as toasts, which landed on top of the big title letters.
local function titleNotice(text: string, kind: string?)
	if titleNotices == nil then
		return
	end
	local labels = {}
	for _, child in titleNotices:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	if #labels >= NOTICE_LIMIT then
		labels[1]:Destroy()
	end
	noticeOrder += 1
	local label = Ui.label({
		Text = text,
		TextSize = Ui.text.small,
		TextColor3 = if kind == "warn"
			then Ui.colors.warn
			elseif kind == "good" then Ui.colors.good
			else Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = noticeOrder,
		Parent = titleNotices,
	})
	task.delay(NOTICE_SECONDS, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

local function othersHere(): number
	local count = 0
	for _, entry in State.server.lobby do
		if entry.userId ~= player.UserId then
			count += 1
		end
	end
	return count
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
	local function add(text: string, height: number, onPress: () -> (), accent: Color3?)
		order += 1
		local button = Ui.button({
			Text = text,
			Size = UDim2.fromOffset(320, height),
			LayoutOrder = order,
			Parent = titleButtons,
		}, onPress, accent)
		first = first or button
	end
	local function start(text: string, mode: string, accent: Color3?)
		add(text, if order == 0 then 40 else 36, function()
			requestStart(mode)
		end, accent)
	end
	local others = othersHere()
	local together = if others > 0 then `PLAY TOGETHER  /  {others} HERE` else "PLAY TOGETHER"
	local function party()
		add(together, 36, function()
			refreshParty()
			Menus.open("party")
		end)
	end
	if server.runActive then
		start("JOIN THE SURVEY", "continue", Ui.colors.good)
		party()
		titleStatus.Text = "A survey is under way on this server. You will join it."
	elseif not profile.tutorialDone then
		start("BEGIN", "new", Ui.colors.good)
		party()
		titleStatus.Text = "Everything is dark. You have a scanner."
	else
		if profile.checkpointTier > 1 then
			start("CONTINUE  /  TIER " .. profile.checkpointTier, "continue", Ui.colors.good)
			start("NEW SURVEY", "new")
		else
			start("BEGIN SURVEY", "new", Ui.colors.good)
		end
		party()
		start(
			if server.dailyDone then "DAILY SURVEY  /  RUN AGAIN" else "DAILY SURVEY",
			"daily",
			Ui.colors.gold
		)
		titleStatus.Text =
			`Visit {profile.streak.count}.  Best tier {profile.bestTier}.  {profile.static} Static.`
	end
	add("SETTINGS", 32, function()
		Menus.open("settings")
	end, Ui.colors.dim)
	windows.title.first = first
	if current == "title" and Input.device == "gamepad" then
		Ui.focus(first)
	end
end

-- Everything stacks in one column, so no line can land on another whatever the screen size.
local function buildTitle()
	local frame = window("title", 760, 380)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(760, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y;
	(frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = false
	local column = Ui.list(Enum.FillDirection.Vertical, 6)
	column.HorizontalAlignment = Enum.HorizontalAlignment.Center
	column.Parent = frame
	Ui.label({
		Text = TITLE_LETTERS,
		FontFace = Ui.fontBold,
		TextSize = Ui.text.hero,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 90),
		LayoutOrder = 1,
		Parent = frame,
	})
	Ui.label({
		Text = "THE UNDERSTORY",
		TextSize = Ui.text.body,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
		Parent = frame,
	})
	titleButtons = Ui.new("Frame", {
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 6) })
	titleStatus = Ui.label({
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = frame,
	})
	titleNotices = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 2) })(Net.get("Toast") :: RemoteEvent).OnClientEvent
		:Connect(function(text: string, kind: string?)
			if State.server.stage == "title" then
				titleNotice(text, kind)
			end
		end)
end

--------------------------------------------------------------------------------------------
-- Play Together: everyone on this server, a Roblox invite for friends, and a way to go in
-- as one crew. The server is the party: whoever is on it plays the same run.

local friendCache: { [number]: boolean } = {}
local friendAsked: { [number]: boolean } = {}

local function isFriend(userId: number): boolean
	if userId == player.UserId then
		return false
	end
	if not friendAsked[userId] then
		friendAsked[userId] = true
		task.spawn(function()
			local ok, result = pcall(function()
				return player:IsFriendsWith(userId)
			end)
			friendCache[userId] = ok and result == true
			if friendCache[userId] and current == "party" then
				refreshParty()
			end
		end)
	end
	return friendCache[userId] == true
end

local function myEntry(): LobbyEntry?
	for _, entry in State.server.lobby do
		if entry.userId == player.UserId then
			return entry
		end
	end
	return nil
end

refreshParty = function()
	if partyList == nil then
		return
	end
	for _, child in partyList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local lobby = State.server.lobby
	local ready, onTitle = 0, 0
	for index, entry in lobby do
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 30),
			BackgroundColor3 = Ui.colors.ink,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = partyList,
		}, { Ui.new("UICorner", { CornerRadius = UDim.new(0, 4) }), Ui.padding(6) })
		local tag = if entry.userId == player.UserId
			then "  (YOU)"
			elseif isFriend(entry.userId) then "  (FRIEND)"
			else ""
		Ui.label({
			Text = entry.name .. tag,
			TextSize = Ui.text.small,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(0.62, 0, 1, 0),
			Parent = row,
		})
		local word = if entry.ready then "READY" else STAGE_WORDS[entry.stage] or ""
		Ui.label({
			Text = word,
			FontFace = Ui.fontBold,
			TextSize = Ui.text.small,
			TextColor3 = if entry.ready
				then Ui.colors.good
				elseif entry.stage == "title" then Ui.colors.dim
				else Ui.colors.line,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.38, 0, 1, 0),
			Parent = row,
		})
		if entry.stage == "title" then
			onTitle += 1
			if entry.ready then
				ready += 1
			end
		end
	end

	local server = State.server
	local me = myEntry()
	local meReady = me ~= nil and me.ready
	local others = othersHere()
	partyReady.Visible = not server.runActive
	partyReady.Text = if meReady then "NOT READY" else "I'M READY"
	partyStart.Text = if server.runActive then "JOIN THEM" else "GO IN"
	if server.runActive then
		partyStatus.Text = "A survey is under way here. Join and you drop in beside them."
	elseif others == 0 then
		partyStatus.Text =
			"Nobody else is here yet. Invite friends: they join this server and play the same run."
	else
		partyStatus.Text =
			`{ready} of {onTitle} on the title are ready. GO IN takes everyone who is ready.`
	end
end

local function buildParty()
	local frame = window("party", 560, 380)
	heading(frame, "PLAY TOGETHER")
	partyStatus = Ui.label({
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = frame,
	})
	partyList = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 1, -122),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 4) })
	local row = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Horizontal, 8) })
	local function button(
		text: string,
		order: number,
		onPress: () -> (),
		accent: Color3?
	): TextButton
		return Ui.button({
			Text = text,
			TextSize = 14,
			Size = UDim2.new(0.25, -6, 1, 0),
			LayoutOrder = order,
			Parent = row,
		}, onPress, accent)
	end
	button("INVITE FRIENDS", 1, function()
		Menus.invite()
	end, Ui.colors.good)
	partyReady = button("I'M READY", 2, function()
		local me = myEntry()
		send("PartyReady", not (me ~= nil and me.ready))
	end)
	partyStart = button("GO IN", 3, function()
		if State.server.runActive then
			requestStart("continue")
		else
			requestStart(defaultMode(), true)
		end
	end, Ui.colors.good)
	button("BACK", 4, Menus.close, Ui.colors.dim)
	windows.party.first = partyStart
	windows.party.onClose = function()
		if State.server.stage == "title" and not startRequested then
			task.defer(Menus.open, "title")
		end
	end
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
			Size = UDim2.new(1, -8, 0, 36),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = settingsRows,
		})
		Ui.label({ Text = label, Size = UDim2.new(0.55, 0, 1, 0), Parent = frame })
		Ui.button({
			Text = value,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.new(0.42, 0, 0, 30),
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
	local quality = settings.dotQuality
	row(
		"DOT DETAIL",
		if quality == "auto"
			then "AUTO (" .. string.upper(Menus.dotQuality()) .. ")"
			else string.upper(quality),
		function()
			setting("dotQuality", DOT_QUALITY_NEXT[settings.dotQuality] or "auto")
			Menus.applyCosmetics()
		end
	)
	row("FRIENDS", "INVITE", function()
		Menus.invite()
	end)
	row("FREEZE DOTS (PHOTO)", if Dots.isFrozen() then "FROZEN" else "LIVE", function()
		Dots.setFrozen(not Dots.isFrozen())
	end)
end

local function buildSettings()
	local frame = window("settings", 560, 380)
	heading(frame, "SETTINGS")
	settingsRows = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, { Ui.list(Enum.FillDirection.Vertical, 4) })
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

-- The dot detail actually in use: "auto" picks by device (phones hold fewer dots).
function Menus.dotQuality(): string
	local quality = State.profile.settings.dotQuality
	if quality ~= "auto" then
		return quality
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "low"
		else "medium"
end

-- Applies the palette, equipped cosmetics and the dot budget (detail setting plus the
-- Phosphor upgrade) to the dot renderer.
function Menus.applyCosmetics()
	local profile = State.profile
	local tint = Upgrades.cosmeticById[profile.cosmetics.dots]
	Dots.setPalette(profile.settings.palette, if tint then tint.color else nil)
	Dots.setBudget(DotRules.budget(Menus.dotQuality(), State.effects.phosphorLevel))
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
			-- The manual's page for it (with the crew's margin note), then the plain rule.
			local entity = Lore.entities[kind]
			local page = if entity then entity.page else string.upper(def.displayName)
			table.insert(lines, page .. "\n" .. def.rule)
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
		-- If another page arrived while this one was open, show it next; then Ines, if she
		-- is waiting; then, after the ladder, the title.
		local nextNote = table.remove(noteQueue, 1)
		if nextNote then
			task.defer(Menus.showNote, nextNote.title, nextNote.body)
		elseif pendingEnding ~= nil then
			local ending = pendingEnding
			pendingEnding = nil
			task.defer(Menus.showEnding, ending.title, ending.body)
		elseif State.server.stage == "title" then
			task.defer(Menus.open, "title")
		end
	end
end

--------------------------------------------------------------------------------------------
-- The finale: Ines speaks, then the choice. There is no close button: it is answered once.

local function choose(choice: string)
	send("Choose", choice)
	Menus.close()
	local card = Lore.ending.cards[choice]
	if card then
		task.defer(Menus.showNote, card.title, card.body)
	end
end

local function buildEnding()
	local frame = window("ending", 600, 380)
	endingTitle = heading(frame, "")
	endingBody = scrollBody(frame, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -100), {
		TextSize = Ui.text.body,
		LineHeight = 1.15,
	})
	local up = Ui.button({
		Text = Lore.ending.choices.up,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -6, 0, 38),
		Parent = frame,
	}, function()
		choose("up")
	end, Ui.colors.line)
	Ui.button({
		Text = Lore.ending.choices.stay,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -6, 0, 38),
		Parent = frame,
	}, function()
		choose("stay")
	end, Ui.colors.gold)
	windows.ending.first = up
end

-- Ines's last words and the choice. Waits for the page the player is reading to be put back.
function Menus.showEnding(title: string, body: string)
	if current == "note" then
		pendingEnding = { title = title, body = body }
		return
	end
	endingTitle.Text = string.upper(title)
	setBody(endingBody, body)
	Menus.open("ending")
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
		table.insert(lines, `MANUAL PAGE     {reward.plate}`)
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
	buildParty()
	buildBench()
	buildNote()
	buildClear()
	buildReport()
	buildBoard()
	buildEmotes()
	buildEnding()

	State.onProfile(function()
		Menus.applyCosmetics()
		refreshTitle()
		refreshBench()
		refreshSettings()
	end)
	State.onState(function(server, previous)
		if server.stage ~= "title" and previous.stage == "title" then
			startRequested = false
			if current == "title" or current == "settings" or current == "party" then
				Menus.close()
			end
		elseif server.stage == "title" then
			if current == "party" then
				refreshParty()
			end
			if previous.stage ~= "title" then
				-- Back from the dark (the ladder): the title comes back, ready to start again.
				startRequested = false
				titleButtons.Visible = true
				if current == nil then
					Menus.open("title")
				end
			end
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
	(Net.get("Ending") :: RemoteEvent).OnClientEvent:Connect(Menus.showEnding);
	(Net.get("LevelCleared") :: RemoteEvent).OnClientEvent:Connect(onLevelCleared);
	(Net.get("DailyBoard") :: RemoteEvent).OnClientEvent:Connect(onDailyBoard)

	refreshSettings()
	refreshTitle()
	Menus.open("title")
end

return Menus
