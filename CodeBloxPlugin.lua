--[[
    CodeBlox Plugin for Roblox Studio — OpenCode Monochrome Edition

    Premium monochromatic UI with dynamic theme sync, TweenService
    micro-interactions, live log feed, status board, and metadata overlay.

    Setup:
    1. Place this file in your Roblox Studio Plugins folder.
    2. Ensure the CodeBlox server is running (node server.js).
    3. Configure SERVER_URL and API_KEY below to match your .env.
]]

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
local SERVER_URL = "http://localhost:3000"
local API_KEY = "codeblox-default-key"
local POLL_INTERVAL = 0.5
local MAX_LOG_ENTRIES = 200

-- ---------------------------------------------------------------------------
-- Services
-- ---------------------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

-- ---------------------------------------------------------------------------
-- Plugin Guard
-- ---------------------------------------------------------------------------
local plugin = plugin or getfenv().plugin
if not plugin then
	warn("[CodeBlox] Must be run as a Roblox Studio plugin.")
	return
end

-- ---------------------------------------------------------------------------
-- Theme System
-- ---------------------------------------------------------------------------
local Themes = {
	black = {
		bg = Color3.fromRGB(10, 10, 10),
		surface = Color3.fromRGB(18, 18, 18),
		surfaceAlt = Color3.fromRGB(24, 24, 24),
		border = Color3.fromRGB(45, 45, 45),
		borderLight = Color3.fromRGB(60, 60, 60),
		text = Color3.fromRGB(235, 235, 235),
		textMid = Color3.fromRGB(160, 160, 160),
		textDim = Color3.fromRGB(100, 100, 100),
		accent = Color3.fromRGB(255, 255, 255),
		dot = Color3.fromRGB(220, 220, 220),
		logSystem = Color3.fromRGB(140, 140, 140),
		logSuccess = Color3.fromRGB(210, 210, 210),
		logError = Color3.fromRGB(170, 170, 170),
		btnFace = Color3.fromRGB(240, 240, 240),
		btnText = Color3.fromRGB(10, 10, 10),
		btnHover = Color3.fromRGB(200, 200, 200),
		btnPress = Color3.fromRGB(160, 160, 160),
	},
	white = {
		bg = Color3.fromRGB(248, 248, 248),
		surface = Color3.fromRGB(255, 255, 255),
		surfaceAlt = Color3.fromRGB(240, 240, 240),
		border = Color3.fromRGB(210, 210, 210),
		borderLight = Color3.fromRGB(225, 225, 225),
		text = Color3.fromRGB(15, 15, 15),
		textMid = Color3.fromRGB(80, 80, 80),
		textDim = Color3.fromRGB(140, 140, 140),
		accent = Color3.fromRGB(0, 0, 0),
		dot = Color3.fromRGB(50, 50, 50),
		logSystem = Color3.fromRGB(110, 110, 110),
		logSuccess = Color3.fromRGB(40, 40, 40),
		logError = Color3.fromRGB(90, 90, 90),
		btnFace = Color3.fromRGB(20, 20, 20),
		btnText = Color3.fromRGB(255, 255, 255),
		btnHover = Color3.fromRGB(50, 50, 50),
		btnPress = Color3.fromRGB(80, 80, 80),
	},
}

local currentTheme = "black"
local isConnected = false

-- ---------------------------------------------------------------------------
-- Tween Helpers
-- ---------------------------------------------------------------------------
local TWEEN_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function tweenColor(obj, prop, color)
	local tw = TweenService:Create(obj, TWEEN_FAST, { [prop] = color })
	tw:Play()
	return tw
end

local function tweenTrans(obj, prop, value)
	local tw = TweenService:Create(obj, TWEEN_FAST, { [prop] = value })
	tw:Play()
	return tw
end

-- ---------------------------------------------------------------------------
-- Widget Setup
-- ---------------------------------------------------------------------------
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	420, 520,
	360, 400
)

local widget = plugin:CreateDockWidgetPluginGui("CodeBloxWidget", widgetInfo)
widget.Title = "CodeBlox"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- ---------------------------------------------------------------------------
-- Root
-- ---------------------------------------------------------------------------
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(1, 0, 1, 0)
root.BorderSizePixel = 0
root.Parent = widget

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 52)
header.BorderSizePixel = 0
header.Parent = root

local headerStroke = Instance.new("UIStroke")
headerStroke.Thickness = 1
headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
headerStroke.Parent = header

local headerPad = Instance.new("UIPadding")
headerPad.PaddingLeft = UDim.new(0, 16)
headerPad.PaddingRight = UDim.new(0, 16)
headerPad.Parent = header

local headerLayout = Instance.new("UIListLayout")
headerLayout.FillDirection = Enum.FillDirection.Horizontal
headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
headerLayout.Padding = UDim.new(0, 10)
headerLayout.Parent = header

-- Logo
local logoFrame = Instance.new("Frame")
logoFrame.Name = "Logo"
logoFrame.Size = UDim2.new(0, 32, 0, 32)
logoFrame.BorderSizePixel = 0
logoFrame.LayoutOrder = 1
logoFrame.Parent = header

local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(0, 6)
logoCorner.Parent = logoFrame

local logoStroke = Instance.new("UIStroke")
logoStroke.Thickness = 1
logoStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
logoStroke.Parent = logoFrame

local logoLabel = Instance.new("TextLabel")
logoLabel.Name = "Icon"
logoLabel.Size = UDim2.new(1, 0, 1, 0)
logoLabel.BackgroundTransparency = 1
logoLabel.Font = Enum.Font.RobotoMono
logoLabel.TextSize = 14
logoLabel.Text = ">_"
logoLabel.Parent = logoFrame

-- Title group
local titleGroup = Instance.new("Frame")
titleGroup.Name = "TitleGroup"
titleGroup.Size = UDim2.new(0, 0, 1, 0)
titleGroup.AutomaticSize = Enum.AutomaticSize.X
titleGroup.BackgroundTransparency = 1
titleGroup.LayoutOrder = 2
titleGroup.Parent = header

local titleText = Instance.new("TextLabel")
titleText.Name = "Title"
titleText.Size = UDim2.new(1, 0, 0, 20)
titleText.Position = UDim2.new(0, 0, 0, 4)
titleText.BackgroundTransparency = 1
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 16
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Text = "CodeBlox"
titleText.Parent = titleGroup

local subtitleText = Instance.new("TextLabel")
subtitleText.Name = "Subtitle"
subtitleText.Size = UDim2.new(1, 0, 0, 14)
subtitleText.Position = UDim2.new(0, 0, 0, 24)
subtitleText.BackgroundTransparency = 1
subtitleText.Font = Enum.Font.RobotoMono
subtitleText.TextSize = 10
subtitleText.TextXAlignment = Enum.TextXAlignment.Left
subtitleText.Text = "Roblox Studio Bridge"
subtitleText.Parent = titleGroup

-- Spacer
local spacer = Instance.new("Frame")
spacer.Name = "Spacer"
spacer.Size = UDim2.new(1, 0, 0, 0)
spacer.BackgroundTransparency = 1
spacer.LayoutOrder = 3
spacer.Parent = header

-- Status pill
local statusGroup = Instance.new("Frame")
statusGroup.Name = "StatusGroup"
statusGroup.Size = UDim2.new(0, 0, 0, 28)
statusGroup.AutomaticSize = Enum.AutomaticSize.X
statusGroup.BorderSizePixel = 0
statusGroup.LayoutOrder = 4
statusGroup.Parent = header

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 14)
statusCorner.Parent = statusGroup

local statusStroke = Instance.new("UIStroke")
statusStroke.Thickness = 1
statusStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
statusStroke.Parent = statusGroup

local statusPad = Instance.new("UIPadding")
statusPad.PaddingLeft = UDim.new(0, 10)
statusPad.PaddingRight = UDim.new(0, 12)
statusPad.Parent = statusGroup

local statusDot = Instance.new("Frame")
statusDot.Name = "Dot"
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(0, 0, 0.5, -4)
statusDot.BorderSizePixel = 0
statusDot.Parent = statusGroup

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = statusDot

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Label"
statusLabel.Size = UDim2.new(0, 0, 1, 0)
statusLabel.Position = UDim2.new(0, 16, 0, 0)
statusLabel.AutomaticSize = Enum.AutomaticSize.X
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.RobotoMono
statusLabel.TextSize = 11
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "IDLE"
statusLabel.Parent = statusGroup

-- Header divider
local dividerTop = Instance.new("Frame")
dividerTop.Name = "DividerTop"
dividerTop.Size = UDim2.new(1, 0, 0, 1)
dividerTop.Position = UDim2.new(0, 0, 0, 52)
dividerTop.BorderSizePixel = 0
dividerTop.Parent = root

-- ---------------------------------------------------------------------------
-- Status Board
-- ---------------------------------------------------------------------------
local statusBoard = Instance.new("Frame")
statusBoard.Name = "StatusBoard"
statusBoard.Size = UDim2.new(1, 0, 0, 44)
statusBoard.Position = UDim2.new(0, 0, 0, 53)
statusBoard.BorderSizePixel = 0
statusBoard.Parent = root

local sbPad = Instance.new("UIPadding")
sbPad.PaddingLeft = UDim.new(0, 16)
sbPad.PaddingRight = UDim.new(0, 16)
sbPad.PaddingTop = UDim.new(0, 8)
sbPad.PaddingBottom = UDim.new(0, 8)
sbPad.Parent = statusBoard

local sbLayout = Instance.new("UIListLayout")
sbLayout.FillDirection = Enum.FillDirection.Horizontal
sbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sbLayout.Padding = UDim.new(0, 12)
sbLayout.Parent = statusBoard

local statBlocks = {}

local function createStatBlock(name, labelText, order)
	local block = Instance.new("Frame")
	block.Name = name
	block.Size = UDim2.new(0, 0, 1, 0)
	block.AutomaticSize = Enum.AutomaticSize.X
	block.BorderSizePixel = 0
	block.LayoutOrder = order
	block.Parent = statusBoard

	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = block

	local bs = Instance.new("UIStroke")
	bs.Thickness = 1
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Parent = block

	local bp = Instance.new("UIPadding")
	bp.PaddingLeft = UDim.new(0, 10)
	bp.PaddingRight = UDim.new(0, 10)
	bp.Parent = block

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Size = UDim2.new(1, 0, 0, 10)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.RobotoMono
	lbl.TextSize = 8
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = labelText
	lbl.Parent = block

	local val = Instance.new("TextLabel")
	val.Name = "Value"
	val.Size = UDim2.new(1, 0, 0, 14)
	val.Position = UDim2.new(0, 0, 0, 12)
	val.BackgroundTransparency = 1
	val.Font = Enum.Font.GothamBold
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Left
	val.Text = "---"
	val.Parent = block

	statBlocks[name] = block
	return block
end

createStatBlock("Provider", "PROVIDER", 1)
createStatBlock("Model", "MODEL", 2)
createStatBlock("Queue", "QUEUE", 3)

-- Mid divider
local dividerMid = Instance.new("Frame")
dividerMid.Name = "DividerMid"
dividerMid.Size = UDim2.new(1, 0, 0, 1)
dividerMid.Position = UDim2.new(0, 0, 0, 97)
dividerMid.BorderSizePixel = 0
dividerMid.Parent = root

-- ---------------------------------------------------------------------------
-- Action Button
-- ---------------------------------------------------------------------------
local actionBtn = Instance.new("TextButton")
actionBtn.Name = "ActionButton"
actionBtn.Size = UDim2.new(1, -32, 0, 36)
actionBtn.Position = UDim2.new(0, 16, 0, 106)
actionBtn.BorderSizePixel = 0
actionBtn.Font = Enum.Font.GothamBold
actionBtn.TextSize = 13
actionBtn.Text = "CONNECT"
actionBtn.AutoButtonColor = false
actionBtn.Parent = root

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = actionBtn

local btnStroke = Instance.new("UIStroke")
btnStroke.Thickness = 1
btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
btnStroke.Parent = actionBtn

-- Button divider
local dividerBtn = Instance.new("Frame")
dividerBtn.Name = "DividerBtn"
dividerBtn.Size = UDim2.new(1, 0, 0, 1)
dividerBtn.Position = UDim2.new(0, 0, 0, 152)
dividerBtn.BorderSizePixel = 0
dividerBtn.Parent = root

-- ---------------------------------------------------------------------------
-- Log Section Header
-- ---------------------------------------------------------------------------
local logHeader = Instance.new("Frame")
logHeader.Name = "LogHeader"
logHeader.Size = UDim2.new(1, 0, 0, 28)
logHeader.Position = UDim2.new(0, 0, 0, 153)
logHeader.BorderSizePixel = 0
logHeader.Parent = root

local logHeaderPad = Instance.new("UIPadding")
logHeaderPad.PaddingLeft = UDim.new(0, 16)
logHeaderPad.PaddingRight = UDim.new(0, 16)
logHeaderPad.Parent = logHeader

local logTitle = Instance.new("TextLabel")
logTitle.Name = "Title"
logTitle.Size = UDim2.new(0.5, 0, 1, 0)
logTitle.BackgroundTransparency = 1
logTitle.Font = Enum.Font.RobotoMono
logTitle.TextSize = 10
logTitle.TextXAlignment = Enum.TextXAlignment.Left
logTitle.Text = "LIVE LOG"
logTitle.Parent = logHeader

local logCount = Instance.new("TextLabel")
logCount.Name = "Count"
logCount.Size = UDim2.new(0.5, -16, 1, 0)
logCount.BackgroundTransparency = 1
logCount.Font = Enum.Font.RobotoMono
logCount.TextSize = 10
logCount.TextXAlignment = Enum.TextXAlignment.Right
logCount.Text = "0 entries"
logCount.Parent = logHeader

-- ---------------------------------------------------------------------------
-- Log Scrolling Container
-- ---------------------------------------------------------------------------
local logScroll = Instance.new("ScrollingFrame")
logScroll.Name = "LogScroll"
logScroll.Size = UDim2.new(1, 0, 1, -181)
logScroll.Position = UDim2.new(0, 0, 0, 181)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 4
logScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logScroll.Parent = root

local logPad = Instance.new("UIPadding")
logPad.PaddingLeft = UDim.new(0, 16)
logPad.PaddingRight = UDim.new(0, 16)
logPad.PaddingTop = UDim.new(0, 4)
logPad.PaddingBottom = UDim.new(0, 8)
logPad.Parent = logScroll

local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 3)
logLayout.Parent = logScroll

-- ---------------------------------------------------------------------------
-- Metadata Overlay
-- ---------------------------------------------------------------------------
local metaOverlay = Instance.new("TextLabel")
metaOverlay.Name = "MetaOverlay"
metaOverlay.Size = UDim2.new(1, -32, 0, 14)
metaOverlay.Position = UDim2.new(0, 16, 1, -20)
metaOverlay.BackgroundTransparency = 1
metaOverlay.Font = Enum.Font.RobotoMono
metaOverlay.TextSize = 9
metaOverlay.TextXAlignment = Enum.TextXAlignment.Right
metaOverlay.TextTransparency = 0.6
metaOverlay.Text = "provider: --- | model: ---"
metaOverlay.Parent = root

-- ---------------------------------------------------------------------------
-- Log Entry System
-- ---------------------------------------------------------------------------
local logEntries = {}
local entryOrder = 0

local function addLog(text, entryType)
	entryOrder += 1

	local entry = Instance.new("TextLabel")
	entry.Name = "Log_" .. entryOrder
	entry.Size = UDim2.new(1, 0, 0, 0)
	entry.AutomaticSize = Enum.AutomaticSize.Y
	entry.BackgroundTransparency = 1
	entry.Font = Enum.Font.RobotoMono
	entry.TextSize = 11
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.TextYAlignment = Enum.TextYAlignment.Top
	entry.TextWrapped = true
	entry.Text = text
	entry.LayoutOrder = entryOrder
	entry.TextTransparency = 1
	entry.Parent = logScroll

	local theme = Themes[currentTheme]
	if entryType == "error" then
		entry.TextColor3 = theme.logError
	elseif entryType == "success" then
		entry.TextColor3 = theme.logSuccess
	else
		entry.TextColor3 = theme.logSystem
	end

	tweenTrans(entry, "TextTransparency", 0)
	table.insert(logEntries, entry)

	while #logEntries > MAX_LOG_ENTRIES do
		logEntries[1]:Destroy()
		table.remove(logEntries, 1)
	end

	logCount.Text = #logEntries .. " entries"
	return entry
end

-- ---------------------------------------------------------------------------
-- Theme Application
-- ---------------------------------------------------------------------------
local function applyTheme(themeName)
	local theme = Themes[themeName]
	if not theme then return end
	currentTheme = themeName

	-- Root and structural
	tweenColor(root, "BackgroundColor3", theme.bg)
	tweenColor(header, "BackgroundColor3", theme.surface)
	tweenColor(headerStroke, "Color", theme.borderLight)
	tweenColor(dividerTop, "BackgroundColor3", theme.border)
	tweenColor(dividerMid, "BackgroundColor3", theme.border)
	tweenColor(dividerBtn, "BackgroundColor3", theme.border)

	-- Header elements
	tweenColor(titleText, "TextColor3", theme.accent)
	tweenColor(subtitleText, "TextColor3", theme.textDim)
	tweenColor(logoFrame, "BackgroundColor3", theme.surfaceAlt)
	tweenColor(logoLabel, "TextColor3", theme.accent)
	tweenColor(logoStroke, "Color", theme.border)

	-- Status pill
	tweenColor(statusDot, "BackgroundColor3", theme.dot)
	tweenColor(statusStroke, "Color", theme.border)
	if isConnected then
		tweenColor(statusLabel, "TextColor3", theme.text)
		tweenColor(statusGroup, "BackgroundColor3", theme.surfaceAlt)
	else
		tweenColor(statusLabel, "TextColor3", theme.textDim)
		tweenColor(statusGroup, "BackgroundColor3", theme.surface)
	end

	-- Status board
	tweenColor(statusBoard, "BackgroundColor3", theme.bg)
	tweenColor(logHeader, "BackgroundColor3", theme.bg)
	for _, block in pairs(statBlocks) do
		tweenColor(block, "BackgroundColor3", theme.surfaceAlt)
		local s = block:FindFirstChildOfClass("UIStroke")
		if s then tweenColor(s, "Color", theme.border) end
		local l = block:FindFirstChild("Label")
		if l then tweenColor(l, "TextColor3", theme.textDim) end
		local v = block:FindFirstChild("Value")
		if v then tweenColor(v, "TextColor3", theme.text) end
	end

	-- Button
	if isConnected then
		tweenColor(actionBtn, "BackgroundColor3", theme.surfaceAlt)
		tweenColor(actionBtn, "TextColor3", theme.text)
		tweenColor(btnStroke, "Color", theme.border)
	else
		tweenColor(actionBtn, "BackgroundColor3", theme.btnFace)
		tweenColor(actionBtn, "TextColor3", theme.btnText)
		tweenColor(btnStroke, "Color", theme.btnFace)
	end

	-- Log header
	tweenColor(logTitle, "TextColor3", theme.textMid)
	tweenColor(logCount, "TextColor3", theme.textDim)
	tweenColor(metaOverlay, "TextColor3", theme.textDim)
	tweenColor(logScroll, "ScrollBarImageColor3", theme.border)

	-- Dim old log entries
	for _, entry in ipairs(logEntries) do
		if entry.Parent then
			tweenColor(entry, "TextColor3", theme.textDim)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Button Interactions
-- ---------------------------------------------------------------------------
local btnHovered = false
local btnPressed = false

actionBtn.MouseEnter:Connect(function()
	btnHovered = true
	if not btnPressed then
		local theme = Themes[currentTheme]
		if isConnected then
			tweenColor(actionBtn, "BackgroundColor3", theme.surface)
		else
			tweenColor(actionBtn, "BackgroundColor3", theme.btnHover)
		end
	end
end)

actionBtn.MouseLeave:Connect(function()
	btnHovered = false
	btnPressed = false
	local theme = Themes[currentTheme]
	if isConnected then
		tweenColor(actionBtn, "BackgroundColor3", theme.surfaceAlt)
	else
		tweenColor(actionBtn, "BackgroundColor3", theme.btnFace)
	end
end)

actionBtn.MouseButton1Down:Connect(function()
	btnPressed = true
	local theme = Themes[currentTheme]
	tweenColor(actionBtn, "BackgroundColor3", theme.btnPress)
end)

actionBtn.MouseButton1Up:Connect(function()
	btnPressed = false
	if btnHovered then
		local theme = Themes[currentTheme]
		if isConnected then
			tweenColor(actionBtn, "BackgroundColor3", theme.surface)
		else
			tweenColor(actionBtn, "BackgroundColor3", theme.btnHover)
		end
	end
end)

actionBtn.Activated:Connect(function()
	if isConnected then
		isConnected = false
		statusLabel.Text = "IDLE"
		actionBtn.Text = "CONNECT"
		addLog("[SYSTEM] Disconnected by user", "system")
		applyTheme(currentTheme)
	else
		isConnected = true
		statusLabel.Text = "ACTIVE"
		actionBtn.Text = "DISCONNECT"
		addLog("[SYSTEM] Connection initiated", "system")
		applyTheme(currentTheme)
	end
end)

-- ---------------------------------------------------------------------------
-- Metadata Update
-- ---------------------------------------------------------------------------
local function updateMeta(provider, model)
	local p = provider or "---"
	local m = model or "---"
	metaOverlay.Text = "provider: " .. p .. " | model: " .. m

	local pb = statBlocks.Provider
	if pb then
		local pv = pb:FindFirstChild("Value")
		if pv then pv.Text = string.upper(p) end
	end

	local mb = statBlocks.Model
	if mb then
		local mv = mb:FindFirstChild("Value")
		if mv then mv.Text = string.upper(m) end
	end
end

local function updateQueue(count)
	local qb = statBlocks.Queue
	if qb then
		local qv = qb:FindFirstChild("Value")
		if qv then qv.Text = tostring(count) end
	end
end

-- ---------------------------------------------------------------------------
-- Plugin Toggle Button
-- ---------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("CodeBlox")
local toggleBtn = toolbar:CreateButton(
	"CodeBlox",
	"Toggle the CodeBlox panel",
	"rbxassetid://0"
)

toggleBtn.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

-- ---------------------------------------------------------------------------
-- HTTP Helpers
-- ---------------------------------------------------------------------------
local function apiGet(endpoint)
	local ok, resp = pcall(function()
		return HttpService:RequestAsync({
			Url = SERVER_URL .. endpoint,
			Method = "GET",
			Headers = {
				["X-API-Key"] = API_KEY,
				["Content-Type"] = "application/json",
			},
		})
	end)
	if ok and resp.Success then
		local dOk, decoded = pcall(HttpService.JSONDecode, HttpService, resp.Body)
		if dOk then return decoded end
	end
	return nil
end

local function apiPost(endpoint, data)
	local ok, resp = pcall(function()
		return HttpService:RequestAsync({
			Url = SERVER_URL .. endpoint,
			Method = "POST",
			Headers = {
				["X-API-Key"] = API_KEY,
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(data),
		})
	end)
	if ok and resp.Success then
		local dOk, decoded = pcall(HttpService.JSONDecode, HttpService, resp.Body)
		if dOk then return decoded end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Script Execution Engine
-- ---------------------------------------------------------------------------
local function executeScript(code, actionId)
	local preview = string.sub(code, 1, 60)
	if #code > 60 then preview = preview .. "..." end
	addLog("[EXEC] " .. preview, "system")

	local success, result = pcall(function()
		local fn, loadErr = loadstring(code)
		if not fn then
			error("Syntax error: " .. tostring(loadErr))
		end
		return fn()
	end)

	local outputText = ""
	local errorText = ""

	if success then
		outputText = result ~= nil and tostring(result) or "OK"
		addLog("[DONE] " .. outputText, "success")
	else
		errorText = tostring(result)
		addLog("[FAIL] " .. errorText, "error")
	end

	apiPost("/api/response", {
		actionId = actionId,
		success = success,
		output = outputText,
		error = errorText,
	})
end

-- ---------------------------------------------------------------------------
-- Status Sync
-- ---------------------------------------------------------------------------
local function syncStatus()
	local status = apiGet("/api/status")
	if not status then
		if isConnected then
			isConnected = false
			statusLabel.Text = "OFFLINE"
			actionBtn.Text = "CONNECT"
			addLog("[ERROR] Lost connection to server", "error")
			applyTheme(currentTheme)
		end
		return false
	end

	isConnected = true
	statusLabel.Text = "ACTIVE"
	actionBtn.Text = "DISCONNECT"

	if status.theme and Themes[status.theme] and status.theme ~= currentTheme then
		applyTheme(status.theme)
	end

	updateMeta(status.activeProvider, status.activeModel)
	updateQueue(status.queueLength or 0)
	return true
end

-- ---------------------------------------------------------------------------
-- Main Polling Loop
-- ---------------------------------------------------------------------------
local running = true

local function pollLoop()
	addLog("[INIT] CodeBlox plugin loaded", "system")
	addLog("[INIT] Polling " .. SERVER_URL, "system")
	applyTheme(currentTheme)

	while running do
		local connected = syncStatus()

		if connected then
			local data = apiGet("/api/actions")
			if data then
				if data.theme and Themes[data.theme] and data.theme ~= currentTheme then
					applyTheme(data.theme)
				end
				if data.actions then
					for _, action in ipairs(data.actions) do
						if action.code and action.id then
							executeScript(action.code, action.id)
						end
					end
				end
			end
		end

		task.wait(POLL_INTERVAL)
	end
end

task.spawn(pollLoop)

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------
plugin.Unloading:Connect(function()
	running = false
	widget.Enabled = false
end)
