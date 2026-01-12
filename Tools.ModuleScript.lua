--!strict
-- ReplicatedStorage/Modules/RogueToolbar.lua

local RogueToolbar = {}
RogueToolbar.__index = RogueToolbar

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

export type DummyTool = { Id: string, Name: string, Key: string, Level: number, Icon: string?, Cooldown: number }
export type ToolDef = { Id: string, Name: string, Kind: "Powers" | "Items", IconText: string }

type SlotUI = {
	Tool: DummyTool,
	Wrap: Frame,
	Button: TextButton,
	Glow: Frame,
	SelectedStroke: UIStroke,
	CooldownFill: Frame,
	CooldownEnd: number,
	Selected: boolean,
	Index: number,
}

export type Theme = {
	AnchorY: number,
	GapPx: number,
	SlotScale: number,
	SlotMinPx: number,
	SlotMaxPx: number,
	ShadowTransparency: number,
	SlotTransparency: number,
	SlotRimStrokeT: number,
	SelectedStrokeT_On: number,
	SelectedStrokeT_Off: number,
	ColorSlotA: Color3,
	ColorSlotB: Color3,
	ColorRim: Color3,
	ColorAccentA: Color3,
	ColorAccentB: Color3,
	ColorText: Color3,
	ColorSubText: Color3,
	CooldownTransparency: number,
	HotbarInsidePad: number,
	MoveTween: number,
}

export type Options = {
	Theme: Theme?,
	MaxSlots: number?,
	DefaultNewSlotCooldown: number?,
	StartTab: ("Powers" | "Items")?,
	AnchorY: number?,
	InitialHotbarTools: { DummyTool }?,
	InitialToolboxDefs: { ToolDef }?,
}

local DEFAULT_THEME: Theme = {
	AnchorY = 0.92,
	GapPx = 10,
	SlotScale = 0.085,
	SlotMinPx = 54,
	SlotMaxPx = 92,
	ShadowTransparency = 0.70,
	SlotTransparency = 0.50,
	SlotRimStrokeT = 0.55,
	SelectedStrokeT_On = 0.18,
	SelectedStrokeT_Off = 1.0,
	ColorSlotA = Color3.fromRGB(14, 14, 17),
	ColorSlotB = Color3.fromRGB(28, 28, 34),
	ColorRim = Color3.fromRGB(90, 90, 105),
	ColorAccentA = Color3.fromRGB(175, 145, 100),
	ColorAccentB = Color3.fromRGB(120, 100, 70),
	ColorText = Color3.fromRGB(235, 235, 240),
	ColorSubText = Color3.fromRGB(175, 175, 190),
	CooldownTransparency = 0.55,
	HotbarInsidePad = 24,
	MoveTween = 0.10,
}

local DEFAULT_MAX_SLOTS = 9
local DEFAULT_NEW_SLOT_COOLDOWN = 6.0

local KEY_TO_DIGIT: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
}

local function mk(className: string, props: { [string]: any }?, parent: Instance?): Instance
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(parent: Instance, r: number): UICorner
	return mk("UICorner", { CornerRadius = UDim.new(0, r) }, parent) :: UICorner
end

local function stroke(parent: Instance, thickness: number, color: Color3, transparency: number, name: string?): UIStroke
	return mk("UIStroke", {
		Thickness = thickness,
		Color = color,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Name = name or "UIStroke",
	}, parent) :: UIStroke
end

local function gradient(parent: Instance, c0: Color3, c1: Color3, rot: number, t0: number?, t1: number?): UIGradient
	local g = mk("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c0),
			ColorSequenceKeypoint.new(1, c1),
		}),
		Rotation = rot,
	}, parent) :: UIGradient
	if t0 and t1 then
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, t0),
			NumberSequenceKeypoint.new(1, t1),
		})
	end
	return g
end

local function tween(obj: Instance, t: number, props: { [string]: any })
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function screenMinAxisPx(): number
	local cam = workspace.CurrentCamera
	if not cam then return 800 end
	local vp = cam.ViewportSize
	return math.min(vp.X, vp.Y)
end

local function getMousePos(): Vector2
	local p = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return Vector2.new(p.X - inset.X, p.Y - inset.Y)
end

local function rectContains(pos: Vector2, tl: Vector2?, br: Vector2?, pad: number?): boolean
	if not tl or not br then return false end
	local p = pad or 0
	return pos.X >= (tl.X - p) and pos.X <= (br.X + p) and pos.Y >= (tl.Y - p) and pos.Y <= (br.Y + p)
end

local function shortenName(name: string): string
	local upper = string.upper(name)
	local first = upper:match("^(%S+)")
	if first and #first >= 3 then return first end
	if #upper > 6 then return upper:sub(1, 6) end
	return upper
end

function RogueToolbar.MakeToolbar(playerGui: PlayerGui, opts: Options?): RogueToolbar
	local self = setmetatable({}, RogueToolbar)

	self.PlayerGui = playerGui
	self.Theme = (opts and opts.Theme) or DEFAULT_THEME
	self.MaxSlots = (opts and opts.MaxSlots) or DEFAULT_MAX_SLOTS
	self.DefaultNewSlotCooldown = (opts and opts.DefaultNewSlotCooldown) or DEFAULT_NEW_SLOT_COOLDOWN

	self.ToolboxOpen = false
	self.Dragging = false
	self.SlotPx = 0

	self.SlotsByKey = {} :: { [string]: SlotUI }
	self.AllSlots = {} :: { SlotUI }

	self.ToolboxDefs = (opts and opts.InitialToolboxDefs) or {}
	self.ToolboxAvailable = {} :: { [string]: boolean }
	self.ToolboxDefById = {} :: { [string]: ToolDef }

	self.DragTool = nil :: ToolDef?
	self.DragUserInputType = nil :: Enum.UserInputType?
	self.DragGhost = nil :: Frame?
	self.DragConn = nil :: RBXScriptConnection?
	self.DragSource = nil :: ("Toolbox" | "Hotbar")?
	self.DragSourceSlotIndex = nil :: number?

	self.DragHiddenToolId = nil :: string?
	self.DragHiddenPrevAvail = nil :: boolean?
	self.DragHiddenSlot = nil :: SlotUI?
	self.DragHiddenSlotPrevVisible = nil :: boolean?

	self.InsertPlaceholder = nil :: Frame?
	self.PreviewInsertIndex = nil :: number?
	self.LastPreviewKey = ""

	self.CurrentTab = (opts and opts.StartTab) or "Powers"
	self._conns = {} :: { RBXScriptConnection }

	self.Player = Players.LocalPlayer
	self.Backpack = self.Player:WaitForChild("Backpack") :: Backpack
	self.Character = self.Player.Character :: Model?
	self.ToolInstancesById = {} :: { [string]: Tool }
	self.ToolInstancesByName = {} :: { [string]: { Tool } }

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	self.DropRemote = remotes:WaitForChild("Drop") :: RemoteEvent

	self:_initCatalog()
	self:_buildGui()
	self:_setupToolLinking()

	for i, tool in ipairs((opts and opts.InitialHotbarTools) or {}) do
		table.insert(self.AllSlots, self:_createSlot(tool, i))
	end
	self:_reindexHotbarSlots()
	self:_layoutHotbarNormal(false)
	self:_clearSelection()
	self:SetToolboxOpen(false)

	table.insert(self._conns, RunService.RenderStepped:Connect(function()
		self:_tickCooldowns()
	end))

	local cam = workspace.CurrentCamera
	if cam then
		table.insert(self._conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_onResize()
		end))
	end

	table.insert(self._conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if not self.Dragging or not self.DragUserInputType then return end
		if input.UserInputType ~= self.DragUserInputType then return end
		self:_stopDrag(getMousePos())
	end))

	return self
end

function RogueToolbar:AddToolToToolbox(def: ToolDef, available: boolean?): ()
	self:_ensureToolboxDef(def.Id, def.Name, def.Kind)
	self.ToolboxAvailable[def.Id] = (available == nil) and true or available
	if self.ToolboxOpen then self:_rebuildToolbox() end
end

function RogueToolbar:AddToolToToolbar(toolId: string, toolName: string, insertIndex: number?): boolean
	self:_ensureToolboxDef(toolId, toolName, "Items")
	self.ToolboxAvailable[toolId] = false
	local ok = self:_insertSlotAndEquip(insertIndex or (#self.AllSlots + 1), toolName, toolId)
	if self.ToolboxOpen then self:_rebuildToolbox() end
	return ok
end

function RogueToolbar:SelectAndEquipById(toolId: string): boolean
	local slot = self:_findSlotByToolId(toolId)
	if not slot then return false end

	local tool = self:_findToolInstanceForSlot(slot)
	if not tool then return false end

	self:_clearSelection()
	local equipped = self:_equipTool(tool)
	self:_setSelected(slot, equipped)
	return equipped
end

function RogueToolbar:EnsureUnequippedById(toolId: string): boolean
	local tool = self:_findToolInstanceById(toolId)
	if not tool then return false end
	if self:_isEquipped(tool) then
		return self:_unequipTool(tool)
	end
	return true
end

function RogueToolbar:RemoveToolFromToolbar(index: number, returnToToolbox: boolean?): ()
	local slot = self.AllSlots[index]
	if not slot then return end
	if (returnToToolbox == nil) or returnToToolbox then
		self:_ensureToolboxDef(slot.Tool.Id, slot.Tool.Name, "Items")
		self.ToolboxAvailable[slot.Tool.Id] = true
	end
	self:_removeSlotAt(index)
	if self.ToolboxOpen then self:_rebuildToolbox() end
end

function RogueToolbar:SetToolboxOpen(on: boolean): ()
	self:_openToolbox(on)
end

function RogueToolbar:IsToolboxOpen(): boolean
	return self.ToolboxOpen
end

function RogueToolbar:HandleKeybind(input: InputObject, gameProcessed: boolean): ()
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard or input.UserInputState ~= Enum.UserInputState.Begin then
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		if self.Dragging then self:_cancelDrag() end
		self:_openToolbox(not self.ToolboxOpen)
		return
	end

	if self.ToolboxOpen or self.Dragging then return end
	local digit = KEY_TO_DIGIT[input.KeyCode]
	if not digit then return end
	local slot = self.SlotsByKey[digit]
	if slot then self:_pressSlot(slot) end
end

function RogueToolbar:Destroy(): ()
	if self.Dragging then self:_cancelDrag() end
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}
	if self.Gui and self.Gui.Parent then self.Gui:Destroy() end
end

function RogueToolbar:_initCatalog(): ()
	for _, def in ipairs(self.ToolboxDefs) do
		self.ToolboxDefById[def.Id] = def
		if self.ToolboxAvailable[def.Id] == nil then
			self.ToolboxAvailable[def.Id] = true
		end
	end
end

function RogueToolbar:_ensureToolboxDef(toolId: string, toolName: string, kind: ("Powers" | "Items")?): ()
	if self.ToolboxDefById[toolId] then return end
	local k: "Powers" | "Items" = kind or "Items"
	local def: ToolDef = { Id = toolId, Name = toolName, Kind = k, IconText = shortenName(toolName) }
	table.insert(self.ToolboxDefs, def)
	self.ToolboxDefById[toolId] = def
	if self.ToolboxAvailable[toolId] == nil then self.ToolboxAvailable[toolId] = true end
end

function RogueToolbar:_indexToolsIn(container: Instance): ()
	for _, inst in ipairs(container:GetChildren()) do
		if inst:IsA("Tool") then self:_indexTool(inst) end
	end
end

function RogueToolbar:_setupToolLinking(): ()
	self:_indexToolsIn(self.Backpack)
	if self.Player.Character then
		self.Character = self.Player.Character
		self:_indexToolsIn(self.Character)
	end

	table.insert(self._conns, self.Backpack.ChildAdded:Connect(function(inst: Instance)
		if inst:IsA("Tool") then self:_indexTool(inst) end
	end))

	table.insert(self._conns, self.Player.CharacterAdded:Connect(function(char: Model)
		self.Character = char
		self:_indexToolsIn(char)
		table.insert(self._conns, char.ChildAdded:Connect(function(inst: Instance)
			if inst:IsA("Tool") then self:_indexTool(inst) end
		end))
	end))
end

function RogueToolbar:_indexTool(tool: Tool): ()
	local function resolveToolId(): string
		local idAttr = tool:GetAttribute("ToolId")
		return (type(idAttr) == "string" and idAttr ~= "") and idAttr or tool.Name
	end

	local function addToNameIndex(name: string): ()
		local list = self.ToolInstancesByName[name]
		if not list then
			list = {}
			self.ToolInstancesByName[name] = list
		end
		if not table.find(list, tool) then
			table.insert(list, tool)
		end
	end

	local function removeFromNameIndex(name: string): ()
		local list = self.ToolInstancesByName[name]
		if not list then return end
		for i = #list, 1, -1 do
			if list[i] == tool then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			self.ToolInstancesByName[name] = nil
		end
	end

	local id = resolveToolId()
	self.ToolInstancesById[id] = tool
	addToNameIndex(tool.Name)

	table.insert(self._conns, tool.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil then
			if self.ToolInstancesById[id] == tool then self.ToolInstancesById[id] = nil end
			removeFromNameIndex(tool.Name)
		end
	end))

	table.insert(self._conns, tool:GetAttributeChangedSignal("ToolId"):Connect(function()
		local newId = resolveToolId()
		if newId == id then return end
		if self.ToolInstancesById[id] == tool then
			self.ToolInstancesById[id] = nil
		end
		self.ToolInstancesById[newId] = tool
		id = newId
	end))
end

function RogueToolbar:_findToolByNameWithoutId(name: string): Tool?
	local list = self.ToolInstancesByName[name]
	if not list then return nil end
	for i = #list, 1, -1 do
		local tool = list[i]
		if tool and self:_isInInventory(tool) then
			local tid = tool:GetAttribute("ToolId")
			if type(tid) ~= "string" or tid == "" then
				return tool
			end
		end
	end
	return nil
end

function RogueToolbar:_getHumanoid(): Humanoid?
	local char = self.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

function RogueToolbar:_isEquipped(tool: Tool): boolean
	return (self.Character ~= nil and tool.Parent == self.Character)
end

function RogueToolbar:_isInInventory(tool: Tool): boolean
	return tool.Parent == self.Backpack or tool.Parent == self.Character
end

function RogueToolbar:_findToolInstanceById(toolId: string): Tool?
	local t = self.ToolInstancesById[toolId]
	if t and self:_isInInventory(t) then return t end

	local char = self.Character
	if char then
		for _, inst in ipairs(char:GetChildren()) do
			if inst:IsA("Tool") then
				local tid = inst:GetAttribute("ToolId")
				if type(tid) == "string" and tid ~= "" then
					if tid == toolId then
						self:_indexTool(inst)
						return inst
					end
				elseif inst.Name == toolId then
					self:_indexTool(inst)
					return inst
				end
			end
		end
	end

	for _, inst in ipairs(self.Backpack:GetChildren()) do
		if inst:IsA("Tool") then
			local tid = inst:GetAttribute("ToolId")
			if type(tid) == "string" and tid ~= "" then
				if tid == toolId then
					self:_indexTool(inst)
					return inst
				end
			elseif inst.Name == toolId then
				self:_indexTool(inst)
				return inst
			end
		end
	end

	t = self:_findToolByNameWithoutId(toolId)
	if t then return t end

	return nil
end

function RogueToolbar:_findToolInstanceByDef(def: ToolDef): Tool?
	local t = self.ToolInstancesById[def.Id]
	if t and self:_isInInventory(t) then return t end

	local char = self.Character
	if char then
		for _, inst in ipairs(char:GetChildren()) do
			if inst:IsA("Tool") then
				local tid = inst:GetAttribute("ToolId")
				if type(tid) == "string" and tid ~= "" then
					if tid == def.Id then
						self:_indexTool(inst)
						return inst
					end
				elseif inst.Name == def.Name then
					self:_indexTool(inst)
					return inst
				end
			end
		end
	end

	for _, inst in ipairs(self.Backpack:GetChildren()) do
		if inst:IsA("Tool") then
			local tid = inst:GetAttribute("ToolId")
			if type(tid) == "string" and tid ~= "" then
				if tid == def.Id then
					self:_indexTool(inst)
					return inst
				end
			elseif inst.Name == def.Name then
				self:_indexTool(inst)
				return inst
			end
		end
	end

	t = self:_findToolByNameWithoutId(def.Name)
	if t then return t end

	return nil
end

function RogueToolbar:_findToolInstanceForSlot(slot: SlotUI): Tool?
	local t = self.ToolInstancesById[slot.Tool.Id]
	if t and self:_isInInventory(t) then return t end

	local char = self.Character
	if char then
		for _, inst in ipairs(char:GetChildren()) do
			if inst:IsA("Tool") then
				local tid = inst:GetAttribute("ToolId")
				if type(tid) == "string" and tid ~= "" then
					if tid == slot.Tool.Id then
						self:_indexTool(inst)
						return inst
					end
				elseif inst.Name == slot.Tool.Name then
					self:_indexTool(inst)
					return inst
				end
			end
		end
	end

	for _, inst in ipairs(self.Backpack:GetChildren()) do
		if inst:IsA("Tool") then
			local tid = inst:GetAttribute("ToolId")
			if type(tid) == "string" and tid ~= "" then
				if tid == slot.Tool.Id then
					self:_indexTool(inst)
					return inst
				end
			elseif inst.Name == slot.Tool.Name then
				self:_indexTool(inst)
				return inst
			end
		end
	end

	t = self:_findToolByNameWithoutId(slot.Tool.Name)
	if t then return t end

	return nil
end

function RogueToolbar:_equipTool(tool: Tool): boolean
	local hum = self:_getHumanoid()
	if not hum then return false end
	if tool.Parent ~= self.Backpack and tool.Parent ~= self.Character then tool.Parent = self.Backpack end
	pcall(function() hum:EquipTool(tool) end)
	return self:_isEquipped(tool)
end

function RogueToolbar:_unequipTool(tool: Tool): boolean
	if tool.Parent == self.Character then tool.Parent = self.Backpack end
	return tool.Parent == self.Backpack
end

function RogueToolbar:_getSlotKind(slot: SlotUI): "Powers" | "Items"
	local def = self.ToolboxDefById[slot.Tool.Id]
	return def and def.Kind or "Items"
end

function RogueToolbar:_toggleItemEquip(slot: SlotUI): ()
	local tool = self:_findToolInstanceForSlot(slot)
	if not tool then return end

	if self:_isEquipped(tool) then
		if not self:_unequipTool(tool) then return end
	else
		if not self:_equipTool(tool) then return end
	end

	local nowEquipped = self:_isEquipped(tool)
	for _, s in ipairs(self.AllSlots) do
		if s ~= slot and s.Selected then self:_setSelected(s, false) end
	end
	self:_setSelected(slot, nowEquipped)
end

function RogueToolbar:_unequipSlotIfEquipped(slot: SlotUI): ()
	local tool = self:_findToolInstanceForSlot(slot)
	if tool and self:_isEquipped(tool) then self:_unequipTool(tool) end
end

function RogueToolbar:_computeSlotPx(): number
	return math.clamp(math.floor(screenMinAxisPx() * self.Theme.SlotScale), self.Theme.SlotMinPx, self.Theme.SlotMaxPx)
end

function RogueToolbar:_buildGui(): ()
	self.SlotPx = self:_computeSlotPx()

	local gui = mk("ScreenGui", {
		Name = "RogueToolbarGui",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, self.PlayerGui) :: ScreenGui
	self.Gui = gui

	local row = mk("Frame", {
		Name = "SlotsRow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, self.Theme.AnchorY),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		BackgroundColor3 = self.Theme.ColorAccentA,
		ZIndex = 2,
	}, gui) :: Frame
	self.Row = row
	corner(row, 18)
	self.RowHighlightStroke = stroke(row, 2, self.Theme.ColorAccentA, 1.0, "RowHighlightStroke")

	local toolboxLayer = mk("Frame", {
		Name = "ToolboxLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 200,
	}, gui) :: Frame
	self.ToolboxLayer = toolboxLayer

	local panel = mk("Frame", {
		Name = "ToolboxPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.06, 0.5),
		Size = UDim2.fromScale(0.30, 0.62),
		BackgroundColor3 = Color3.fromRGB(14, 14, 17),
		BackgroundTransparency = 0.18,
		ZIndex = 210,
	}, toolboxLayer) :: Frame
	self.ToolboxPanel = panel
	corner(panel, 14)
	stroke(panel, 2, Color3.fromRGB(90, 90, 105), 0.55)
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, panel)

	local toolboxDropHighlight = mk("Frame", {
		Name = "ToolboxDropHighlight",
		BackgroundColor3 = self.Theme.ColorAccentA,
		BackgroundTransparency = 0.90,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 260,
		Visible = false,
	}, panel) :: Frame
	self.ToolboxDropHighlight = toolboxDropHighlight
	corner(toolboxDropHighlight, 14)
	stroke(toolboxDropHighlight, 2, self.Theme.ColorAccentA, 0.20)

	mk("TextLabel", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Text = "TOOLBOX",
		Font = Enum.Font.GothamSemibold,
		TextSize = 16,
		TextColor3 = self.Theme.ColorText,
		TextTransparency = 0.10,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 211,
	}, panel)

	local tabsRow = mk("Frame", {
		Name = "TabsRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 0, 28),
		ZIndex = 211,
	}, panel) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, tabsRow)

	local function makeTab(text: string): TextButton
		local b = mk("TextButton", {
			Name = "Tab_" .. text,
			AutoButtonColor = false,
			Size = UDim2.new(0, 120, 0, 30),
			BackgroundColor3 = Color3.fromRGB(20, 20, 26),
			BackgroundTransparency = 0.25,
			Text = text,
			Font = Enum.Font.GothamSemibold,
			TextSize = 13,
			TextColor3 = self.Theme.ColorText,
			TextTransparency = 0.15,
			ZIndex = 212,
		}, tabsRow) :: TextButton
		corner(b, 10)
		stroke(b, 1, Color3.fromRGB(90, 90, 105), 0.65)
		return b
	end

	self.TabPowers = makeTab("Powers")
	self.TabItems = makeTab("Items")

	local content = mk("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 70),
		Size = UDim2.new(1, 0, 1, -70),
		ZIndex = 211,
	}, panel) :: Frame

	local listFrame = mk("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 1, -58),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		ScrollBarImageTransparency = 0.35,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 212,
	}, content) :: ScrollingFrame
	self.ListFrame = listFrame

	local grid = mk("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellPadding = UDim2.fromOffset(10, 10),
	}, listFrame) :: UIGridLayout
	self.ToolboxGrid = grid

	table.insert(self._conns, grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		listFrame.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 12)
	end))

	local dropZone = mk("Frame", {
		Name = "DropZone",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = Color3.fromRGB(22, 22, 28),
		BackgroundTransparency = 0.22,
		ZIndex = 215,
	}, content) :: Frame
	self.DropZone = dropZone
	corner(dropZone, 12)
	stroke(dropZone, 1, Color3.fromRGB(90, 90, 105), 0.60, "DropZoneStroke")

	local dzGlow = mk("Frame", {
		Name = "Glow",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self.Theme.ColorAccentA,
		BackgroundTransparency = 1,
		ZIndex = 216,
		Visible = true,
	}, dropZone) :: Frame
	self.DropZoneGlow = dzGlow
	corner(dzGlow, 12)
	gradient(dzGlow, self.Theme.ColorAccentA, self.Theme.ColorAccentB, 90, 0.90, 1.0)

	mk("TextLabel", {
		Name = "DropLabel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 1, -10),
		Text = "DROP TOOL HERE",
		Font = Enum.Font.GothamSemibold,
		TextSize = 13,
		TextColor3 = self.Theme.ColorText,
		TextTransparency = 0.12,
		ZIndex = 217,
	}, dropZone)

	self.DropZoneHighlightStroke = stroke(dropZone, 2, self.Theme.ColorAccentA, 1.0, "DropZoneHighlightStroke")

	self.TabPowers.Activated:Connect(function()
		self:_setTabActive("Powers")
		self:_rebuildToolbox()
	end)
	self.TabItems.Activated:Connect(function()
		self:_setTabActive("Items")
		self:_rebuildToolbox()
	end)

	self:_setTabActive(self.CurrentTab)
end

function RogueToolbar:_setRowHighlight(on: boolean): ()
	tween(self.Row, 0.08, { BackgroundTransparency = on and 0.93 or 1 })
	tween(self.RowHighlightStroke, 0.08, { Transparency = on and 0.25 or 1.0 })
end

function RogueToolbar:_getRowBounds(): (Vector2?, Vector2?)
	local p, s = self.Row.AbsolutePosition, self.Row.AbsoluteSize
	if s.X <= 0 or s.Y <= 0 then return nil, nil end
	return Vector2.new(p.X, p.Y), Vector2.new(p.X + s.X, p.Y + s.Y)
end

function RogueToolbar:_getToolboxBounds(): (Vector2?, Vector2?)
	if not self.ToolboxOpen then return nil, nil end
	local p, s = self.ToolboxPanel.AbsolutePosition, self.ToolboxPanel.AbsoluteSize
	if s.X <= 0 or s.Y <= 0 then return nil, nil end
	return Vector2.new(p.X, p.Y), Vector2.new(p.X + s.X, p.Y + s.Y)
end

function RogueToolbar:_getDropZoneBounds(): (Vector2?, Vector2?)
	if not self.ToolboxOpen then return nil, nil end
	local dz = self.DropZone
	if not dz then return nil, nil end
	local p, s = dz.AbsolutePosition, dz.AbsoluteSize
	if s.X <= 0 or s.Y <= 0 then return nil, nil end
	return Vector2.new(p.X, p.Y), Vector2.new(p.X + s.X, p.Y + s.Y)
end

function RogueToolbar:_setToolboxHoverHighlight(on: boolean): ()
	self.ToolboxDropHighlight.Visible = self.ToolboxOpen and on
end

function RogueToolbar:_setDropZoneHighlight(on: boolean): ()
	if not self.DropZoneHighlightStroke then return end
	tween(self.DropZone, 0.08, { BackgroundTransparency = on and 0.10 or 0.22 })
	tween(self.DropZoneHighlightStroke, 0.08, { Transparency = on and 0.25 or 1.0 })
	tween(self.DropZoneGlow, 0.08, { BackgroundTransparency = on and 0.86 or 1.0 })
end

function RogueToolbar:_setTabActive(kind: "Powers" | "Items"): ()
	self.CurrentTab = kind
	local function style(btn: TextButton, on: boolean)
		btn.BackgroundTransparency = on and 0.05 or 0.25
		local st = btn:FindFirstChildOfClass("UIStroke")
		if st then (st :: UIStroke).Transparency = on and 0.35 or 0.65 end
	end
	style(self.TabPowers, kind == "Powers")
	style(self.TabItems, kind == "Items")
end

function RogueToolbar:_rebuildKeyMap(): ()
	table.clear(self.SlotsByKey)
	for _, slot in ipairs(self.AllSlots) do
		self.SlotsByKey[slot.Tool.Key] = slot
	end
end

function RogueToolbar:_setSlotKeyLabel(slot: SlotUI, key: string): ()
	slot.Tool.Key = key
	local keyLbl = slot.Button:FindFirstChild("Key")
	if keyLbl and keyLbl:IsA("TextLabel") then keyLbl.Text = key end
end

function RogueToolbar:_reindexHotbarSlots(): ()
	for i, slot in ipairs(self.AllSlots) do
		slot.Index = i
		slot.Button:SetAttribute("SlotIndex", i)
		self:_setSlotKeyLabel(slot, tostring(i))
		slot.Wrap.Name = ("SlotWrap_%d"):format(i)
	end
	self:_rebuildKeyMap()
end

function RogueToolbar:_getNextFreeDigitKey(): string?
	for i = 1, 9 do
		local k = tostring(i)
		if not self.SlotsByKey[k] then return k end
	end
	return nil
end

function RogueToolbar:_ensureRowSize(visualCount: number): ()
	local count = math.max(visualCount, 1)
	local w = count * self.SlotPx + math.max(count - 1, 0) * self.Theme.GapPx
	self.Row.Size = UDim2.fromOffset(w, self.SlotPx)
end

function RogueToolbar:_setWrapPos(wrap: Frame, x: number, animate: boolean): ()
	local p = UDim2.fromOffset(math.floor(x), 0)
	if animate then tween(wrap, self.Theme.MoveTween, { Position = p }) else wrap.Position = p end
end

function RogueToolbar:_layoutHotbarVisual(wraps: { Frame }, placeholder: Frame?, phIndex: number?, animate: boolean): ()
	local addPh = (placeholder ~= nil and phIndex ~= nil)
	self:_ensureRowSize(#wraps + (addPh and 1 or 0))

	local x = 0
	local function bump() x += self.SlotPx + self.Theme.GapPx end

	for i = 1, #wraps + 1 do
		if addPh and phIndex == i then
			(placeholder :: Frame).Size = UDim2.fromOffset(self.SlotPx, self.SlotPx)
			self:_setWrapPos((placeholder :: Frame), x, animate)
			bump()
		end
		local w = wraps[i]
		if w then
			self:_setWrapPos(w, x, animate)
			bump()
		end
	end
end

function RogueToolbar:_layoutHotbarNormal(animate: boolean): ()
	local wraps: { Frame } = {}
	for _, s in ipairs(self.AllSlots) do wraps[#wraps + 1] = s.Wrap end
	self:_layoutHotbarVisual(wraps, nil, nil, animate)
end

function RogueToolbar:_setSelected(slot: SlotUI, on: boolean): ()
	slot.Selected = on
	tween(slot.Glow, 0.12, { BackgroundTransparency = on and 0.82 or 1 })
	tween(slot.SelectedStroke, 0.12, { Transparency = on and self.Theme.SelectedStrokeT_On or self.Theme.SelectedStrokeT_Off })
end

function RogueToolbar:_clearSelection(): ()
	for _, s in ipairs(self.AllSlots) do
		if s.Selected then self:_setSelected(s, false) end
	end
end

function RogueToolbar:_findSlotByToolId(toolId: string): SlotUI?
	for _, s in ipairs(self.AllSlots) do
		if s.Tool.Id == toolId then return s end
	end
	return nil
end

function RogueToolbar:_startCooldown(slot: SlotUI, cd: number): ()
	if cd <= 0 then return end
	slot.CooldownEnd = time() + cd
	slot.CooldownFill.Visible = true
end

function RogueToolbar:_isOnCooldown(slot: SlotUI): boolean
	return slot.CooldownEnd > 0 and time() < slot.CooldownEnd
end

function RogueToolbar:_pressSlot(slot: SlotUI): ()
	if self.Dragging or self.ToolboxOpen then return end

	if self:_getSlotKind(slot) == "Items" then
		self:_toggleItemEquip(slot)
		return
	end

	if self:_isOnCooldown(slot) then return end
	for _, s in ipairs(self.AllSlots) do
		if s ~= slot then self:_setSelected(s, false) end
	end
	self:_setSelected(slot, true)
	self:_startCooldown(slot, slot.Tool.Cooldown)
end

function RogueToolbar:_applyEquippedVisual(slot: SlotUI, name: string, toolId: string): ()
	local rune = slot.Button:FindFirstChild("Rune")
	if rune and rune:IsA("TextLabel") then (rune :: TextLabel).Text = shortenName(name) end
	slot.Button:SetAttribute("ToolId", toolId)
	slot.Button:SetAttribute("ToolName", name)
end

function RogueToolbar:_createSlot(tool: DummyTool, index: number): SlotUI
	local wrap = mk("Frame", {
		Name = ("SlotWrap_%d"):format(index),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(self.SlotPx, self.SlotPx),
		ZIndex = 5,
	}, self.Row) :: Frame

	local shadow = mk("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(1.08, 1.18),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = self.Theme.ShadowTransparency,
		ZIndex = 1,
	}, wrap) :: Frame
	corner(shadow, 14)
	gradient(shadow, Color3.new(0, 0, 0), Color3.new(0, 0, 0), 90, 0.25, 0.90)

	local btn = mk("TextButton", {
		Name = "SlotButton",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self.Theme.ColorSlotA,
		BackgroundTransparency = self.Theme.SlotTransparency,
		ZIndex = 10,
	}, wrap) :: TextButton
	corner(btn, 12)
	gradient(btn, self.Theme.ColorSlotB, self.Theme.ColorSlotA, 90)
	stroke(btn, 1, self.Theme.ColorRim, self.Theme.SlotRimStrokeT, "RimStroke")
	local selectedStroke = stroke(btn, 2, self.Theme.ColorAccentA, self.Theme.SelectedStrokeT_Off, "SelectedStroke")

	local glow = mk("Frame", {
		Name = "Glow",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self.Theme.ColorAccentB,
		BackgroundTransparency = 1,
		ZIndex = 11,
	}, btn) :: Frame
	corner(glow, 12)
	gradient(glow, self.Theme.ColorAccentA, self.Theme.ColorAccentB, 90, 0.92, 1.0)

	mk("TextLabel", {
		Name = "Key",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.10, 0.08),
		Size = UDim2.fromScale(0.30, 0.22),
		Text = tool.Key,
		TextColor3 = self.Theme.ColorText,
		TextTransparency = 0.15,
		Font = Enum.Font.GothamSemibold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 20,
	}, btn)

	mk("TextLabel", {
		Name = "Level",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.94, 0.08),
		Size = UDim2.fromScale(0.55, 0.22),
		Text = "Lv." .. tostring(tool.Level),
		TextColor3 = self.Theme.ColorSubText,
		TextTransparency = 0.35,
		Font = Enum.Font.GothamSemibold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 20,
	}, btn)

	mk("TextLabel", {
		Name = "Rune",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.88, 0.70),
		Text = shortenName(tool.Name),
		TextColor3 = self.Theme.ColorText,
		TextTransparency = 0.18,
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 15,
	}, btn)

	local cdMask = mk("Frame", {
		Name = "CooldownMask",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	}, btn) :: Frame
	corner(cdMask, 12)

	local cdFill = mk("Frame", {
		Name = "CooldownFill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = self.Theme.CooldownTransparency,
		ZIndex = 30,
		Visible = false,
	}, cdMask) :: Frame
	gradient(cdFill, Color3.new(1, 1, 1), Color3.fromRGB(220, 220, 220), 90, 0.15, 0.35)

	btn:SetAttribute("SlotIndex", index)

	local slot: SlotUI = {
		Tool = tool,
		Wrap = wrap,
		Button = btn,
		Glow = glow,
		SelectedStroke = selectedStroke,
		CooldownFill = cdFill,
		CooldownEnd = 0,
		Selected = false,
		Index = index,
	}

	btn.Activated:Connect(function() self:_pressSlot(slot) end)
	btn.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_startDragFromHotbar(slot, input)
		end
	end)

	return slot
end

function RogueToolbar:_equipInSlot(index: number, name: string, toolId: string): (string?, string?)
	local slot = self.AllSlots[index]
	if not slot then return nil, nil end
	local oldId, oldName = slot.Tool.Id, slot.Tool.Name
	slot.Tool.Id, slot.Tool.Name = toolId, name
	self:_applyEquippedVisual(slot, name, toolId)
	return oldId, oldName
end

function RogueToolbar:_insertSlotAndEquip(insertIndex: number, name: string, toolId: string): boolean
	if #self.AllSlots >= self.MaxSlots then return false end
	insertIndex = math.clamp(insertIndex, 1, #self.AllSlots + 1)

	local newKey = self:_getNextFreeDigitKey()
	if not newKey then return false end

	local newTool: DummyTool = {
		Id = toolId,
		Name = name,
		Key = newKey,
		Level = 1,
		Icon = nil,
		Cooldown = self.DefaultNewSlotCooldown,
	}
	local slot = self:_createSlot(newTool, insertIndex)
	table.insert(self.AllSlots, insertIndex, slot)
	self:_reindexHotbarSlots()
	self:_applyEquippedVisual(slot, name, toolId)
	self:_layoutHotbarNormal(false)
	return true
end

function RogueToolbar:_moveSlotTo(srcIndex: number, destIndex: number): ()
	if srcIndex == destIndex then return end
	if srcIndex < 1 or srcIndex > #self.AllSlots then return end
	destIndex = math.clamp(destIndex, 1, #self.AllSlots)

	local slot = table.remove(self.AllSlots, srcIndex)
	if not slot then return end
	table.insert(self.AllSlots, destIndex, slot)
	self:_reindexHotbarSlots()
	self:_layoutHotbarNormal(false)
end

function RogueToolbar:_removeSlotAt(index: number): ()
	local slot = self.AllSlots[index]
	if not slot then return end
	local wasSelected = slot.Selected

	slot.Wrap:Destroy()
	table.remove(self.AllSlots, index)
	self:_reindexHotbarSlots()
	self:_layoutHotbarNormal(false)

	if wasSelected then self:_clearSelection() end
end

function RogueToolbar:_rebuildToolbox(): ()
	local fallback = Vector2.new(72, 72)
	local sizePx = (#self.AllSlots > 0) and self.AllSlots[1].Button.AbsoluteSize or fallback
	self.ToolboxGrid.CellSize = UDim2.fromOffset(sizePx.X, sizePx.Y)

	for _, c in ipairs(self.ListFrame:GetChildren()) do
		if c:IsA("GuiObject") and c ~= self.ToolboxGrid then c:Destroy() end
	end

	local n = 0
	for _, def in ipairs(self.ToolboxDefs) do
		if def.Kind ~= self.CurrentTab then continue end
		if self.ToolboxAvailable[def.Id] ~= true then continue end
		n += 1

		local tile = mk("TextButton", {
			Name = "ToolTile_" .. def.Id,
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(22, 22, 28),
			BackgroundTransparency = 0.18,
			Text = "",
			ZIndex = 213,
		}, self.ListFrame) :: TextButton
		corner(tile, 12)
		stroke(tile, 1, Color3.fromRGB(90, 90, 105), 0.60)

		mk("TextLabel", {
			Name = "Index",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 10, 0, 8),
			Size = UDim2.new(0, 40, 0, 20),
			Text = tostring(n),
			Font = Enum.Font.GothamSemibold,
			TextSize = 14,
			TextColor3 = self.Theme.ColorText,
			TextTransparency = 0.15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 214,
		}, tile)

		mk("TextLabel", {
			Name = "Rune",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromScale(0.92, 0.78),
			Text = shortenName(def.Name),
			TextColor3 = self.Theme.ColorText,
			TextTransparency = 0.18,
			Font = Enum.Font.GothamBlack,
			TextSize = 18,
			TextScaled = true,
			TextWrapped = true,
			ZIndex = 214,
		}, tile)

		tile.InputBegan:Connect(function(inp: InputObject)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				self:_startDragFromToolbox(def, inp)
			end
		end)
	end
end

function RogueToolbar:_makeDragGhost(title: string, subtitle: string): Frame
	local ghost = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(25, 25, 32),
		BackgroundTransparency = 0.10,
		Size = UDim2.fromOffset(240, 82),
		ZIndex = 1000,
	}, self.Gui) :: Frame
	corner(ghost, 12)
	stroke(ghost, 2, self.Theme.ColorAccentA, 0.35)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 10),
		Size = UDim2.new(1, -24, 0, 22),
		Text = title,
		Font = Enum.Font.GothamSemibold,
		TextSize = 14,
		TextColor3 = self.Theme.ColorText,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 1001,
	}, ghost)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 38),
		Size = UDim2.new(1, -24, 0, 20),
		Text = subtitle,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = self.Theme.ColorSubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.20,
		ZIndex = 1001,
	}, ghost)

	return ghost
end

function RogueToolbar:_ensurePlaceholder(): ()
	if self.InsertPlaceholder and self.InsertPlaceholder.Parent then return end
	local ph = mk("Frame", {
		Name = "InsertPlaceholder",
		BackgroundColor3 = self.Theme.ColorAccentA,
		BackgroundTransparency = 0.93,
		Size = UDim2.fromOffset(self.SlotPx, self.SlotPx),
		ZIndex = 6,
	}, self.Row) :: Frame
	corner(ph, 12)
	stroke(ph, 2, self.Theme.ColorAccentA, 0.35)
	self.InsertPlaceholder = ph
end

function RogueToolbar:_visualOrderWraps(excludingIndex: number?): { Frame }
	local wraps: { Frame } = {}
	for i, s in ipairs(self.AllSlots) do
		if not (excludingIndex and i == excludingIndex) then wraps[#wraps + 1] = s.Wrap end
	end
	return wraps
end

function RogueToolbar:_getInsertIndexByMouseX(x: number, excludingIndex: number?): number
	local wraps = self:_visualOrderWraps(excludingIndex)
	if #wraps == 0 then return 1 end
	for i, w in ipairs(wraps) do
		local p, s = w.AbsolutePosition, w.AbsoluteSize
		if x < (p.X + s.X * 0.5) then return i end
	end
	return #wraps + 1
end

function RogueToolbar:_clearPreview(): ()
	if self.InsertPlaceholder then
		self.InsertPlaceholder:Destroy()
		self.InsertPlaceholder = nil
	end
	self.PreviewInsertIndex = nil
	self.LastPreviewKey = ""
	self:_layoutHotbarNormal(true)
end

function RogueToolbar:_findSlotAt(pos: Vector2): SlotUI?
	for _, slot in ipairs(self.AllSlots) do
		if slot.Wrap.Visible then
			local p, s = slot.Wrap.AbsolutePosition, slot.Wrap.AbsoluteSize
			if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then
				return slot
			end
		end
	end
	return nil
end

function RogueToolbar:_previewLayout(mp: Vector2, insideHotbar: boolean, hoveredSlot: SlotUI?): ()
	if not insideHotbar or hoveredSlot ~= nil then
		self:_clearPreview()
		return
	end
	if self.DragSource == "Toolbox" and #self.AllSlots >= self.MaxSlots then
		self:_clearPreview()
		return
	end

	local excluding = (self.DragSource == "Hotbar") and self.DragSourceSlotIndex or nil
	local idx = self:_getInsertIndexByMouseX(mp.X, excluding)
	self.PreviewInsertIndex = idx

	self:_ensurePlaceholder()
	local wraps = self:_visualOrderWraps(excluding)
	local key = ("%s|%d|%d"):format(self.DragSource or "?", idx, #wraps)
	if key == self.LastPreviewKey then return end
	self.LastPreviewKey = key
	self:_layoutHotbarVisual(wraps, self.InsertPlaceholder, idx, true)
end

function RogueToolbar:_updateDragHover(mp: Vector2): ()
	if not self.ToolboxOpen then
		self:_cancelDrag()
		return
	end
	if not self.DragGhost then return end

	self.DragGhost.Position = UDim2.fromOffset(math.floor(mp.X + 12), math.floor(mp.Y + 12))

	local rowTL, rowBR = self:_getRowBounds()
	local insideHotbar = rectContains(mp, rowTL, rowBR, self.Theme.HotbarInsidePad)
	local hoveredSlot = insideHotbar and self:_findSlotAt(mp) or nil

	local dzTL, dzBR = self:_getDropZoneBounds()
	local insideDropZone = rectContains(mp, dzTL, dzBR, 0)

	if self.DragSource == "Toolbox" then
		self:_setRowHighlight(insideHotbar)
		self:_setToolboxHoverHighlight(false)
		self:_setDropZoneHighlight(insideDropZone)
	else
		self:_setRowHighlight(false)
		local tbTL, tbBR = self:_getToolboxBounds()
		self:_setToolboxHoverHighlight(rectContains(mp, tbTL, tbBR, 0))
		self:_setDropZoneHighlight(insideDropZone)
	end

	self:_previewLayout(mp, insideHotbar, hoveredSlot)
end

function RogueToolbar:_endDragCleanup(): ()
	self.Dragging = false
	self.DragTool = nil
	self.DragUserInputType = nil
	self.DragSource = nil
	self.DragSourceSlotIndex = nil
	self.DragHiddenToolId = nil
	self.DragHiddenPrevAvail = nil
	self.DragHiddenSlot = nil
	self.DragHiddenSlotPrevVisible = nil

	if self.DragConn then self.DragConn:Disconnect(); self.DragConn = nil end
	if self.DragGhost then self.DragGhost:Destroy(); self.DragGhost = nil end

	self:_setToolboxHoverHighlight(false)
	self:_setRowHighlight(false)
	self:_setDropZoneHighlight(false)
	self:_clearPreview()
end

function RogueToolbar:_cancelDrag(): ()
	if not self.Dragging then return end

	if self.DragSource == "Toolbox" and self.DragHiddenToolId then
		self.ToolboxAvailable[self.DragHiddenToolId] = (self.DragHiddenPrevAvail == nil) and true or self.DragHiddenPrevAvail
	end

	if self.DragSource == "Hotbar" and self.DragHiddenSlot and self.DragHiddenSlot.Wrap and self.DragHiddenSlot.Wrap.Parent then
		self.DragHiddenSlot.Wrap.Visible = (self.DragHiddenSlotPrevVisible == nil) and true or self.DragHiddenSlotPrevVisible
	end

	if self.ToolboxOpen then self:_rebuildToolbox() end
	self:_endDragCleanup()
end

function RogueToolbar:_stopDrag(dropPos: Vector2): ()
	if not self.ToolboxOpen then
		self:_cancelDrag()
		return
	end

	local hoveredSlot = self:_findSlotAt(dropPos)
	local rowTL, rowBR = self:_getRowBounds()
	local insideHotbar = rectContains(dropPos, rowTL, rowBR, self.Theme.HotbarInsidePad)
	local tbTL, tbBR = self:_getToolboxBounds()
	local insideToolbox = rectContains(dropPos, tbTL, tbBR, 0)

	local dzTL, dzBR = self:_getDropZoneBounds()
	local insideDropZone = rectContains(dropPos, dzTL, dzBR, 0)

	local removedSourceSlot = false
	local dragTool = self.DragTool

	if dragTool then
		if self.DragSource == "Toolbox" then
			local placed = false
			local returnedToolId: string? = nil
			local returnedToolName: string? = nil

			if insideDropZone then
				local toolInst = self:_findToolInstanceByDef(dragTool)
				if toolInst then
					pcall(function()
						(self.DropRemote :: RemoteEvent):FireServer(toolInst)
					end)
					placed = true
					self.ToolboxAvailable[dragTool.Id] = false
				end
			elseif hoveredSlot then
				local oldId, oldName = self:_equipInSlot(hoveredSlot.Index, dragTool.Name, dragTool.Id)
				placed = true
				if oldId then returnedToolId, returnedToolName = oldId, (oldName or oldId) end
			elseif insideHotbar and #self.AllSlots < self.MaxSlots then
				local idx = self.PreviewInsertIndex or self:_getInsertIndexByMouseX(dropPos.X, nil)
				placed = self:_insertSlotAndEquip(idx, dragTool.Name, dragTool.Id)
			end

			if not placed and self.DragHiddenToolId then
				self.ToolboxAvailable[self.DragHiddenToolId] = (self.DragHiddenPrevAvail == nil) and true or self.DragHiddenPrevAvail
			end
			if placed and not insideDropZone then
				self.ToolboxAvailable[dragTool.Id] = false
			end

			if returnedToolId and returnedToolName then
				self:_ensureToolboxDef(returnedToolId, returnedToolName, "Items")
				self.ToolboxAvailable[returnedToolId] = true
			end
		else
			local srcIndex = self.DragSourceSlotIndex
			if srcIndex and self.AllSlots[srcIndex] then
				if insideDropZone then
					local srcSlot = self.AllSlots[srcIndex]
					local toolInst = self:_findToolInstanceForSlot(srcSlot)
					if toolInst then
						self:_unequipSlotIfEquipped(srcSlot)
						pcall(function()
							(self.DropRemote :: RemoteEvent):FireServer(toolInst)
						end)
						self:_removeSlotAt(srcIndex)
						removedSourceSlot = true
					end
				elseif hoveredSlot and hoveredSlot.Index ~= srcIndex then
					local srcSlot = self.AllSlots[srcIndex]
					local srcId, srcName = srcSlot.Tool.Id, srcSlot.Tool.Name
					local dstId, dstName = hoveredSlot.Tool.Id, hoveredSlot.Tool.Name
					self:_equipInSlot(srcIndex, dstName, dstId)
					self:_equipInSlot(hoveredSlot.Index, srcName, srcId)
				elseif insideHotbar then
					local idx = self.PreviewInsertIndex or self:_getInsertIndexByMouseX(dropPos.X, srcIndex)
					local dest = idx
					if dest > srcIndex then dest -= 1 end
					self:_moveSlotTo(srcIndex, math.clamp(dest, 1, #self.AllSlots))
				elseif insideToolbox then
					local srcSlot = self.AllSlots[srcIndex]
					self:_unequipSlotIfEquipped(srcSlot)
					self:_ensureToolboxDef(srcSlot.Tool.Id, srcSlot.Tool.Name, "Items")
					self.ToolboxAvailable[srcSlot.Tool.Id] = true
					self:_removeSlotAt(srcIndex)
					removedSourceSlot = true
				end
			end
		end
	end

	if not removedSourceSlot then
		if self.DragSource == "Hotbar" and self.DragHiddenSlot and self.DragHiddenSlot.Wrap and self.DragHiddenSlot.Wrap.Parent then
			self.DragHiddenSlot.Wrap.Visible = (self.DragHiddenSlotPrevVisible == nil) and true or self.DragHiddenSlotPrevVisible
		end
	end

	if self.ToolboxOpen then self:_rebuildToolbox() end
	self:_layoutHotbarNormal(true)
	self:_endDragCleanup()
end

function RogueToolbar:_startDragFromToolbox(def: ToolDef, input: InputObject): ()
	if not self.ToolboxOpen or self.Dragging then return end

	self.Dragging = true
	self.DragSource = "Toolbox"
	self.DragSourceSlotIndex = nil
	self.DragTool = def
	self.DragUserInputType = input.UserInputType

	self.DragHiddenToolId = def.Id
	self.DragHiddenPrevAvail = self.ToolboxAvailable[def.Id]
	self.ToolboxAvailable[def.Id] = false
	self:_rebuildToolbox()

	self.DragGhost = self:_makeDragGhost(def.Name, "Drop on slot to replace • Drop between to insert • Drop zone to drop item")
	self.DragConn = RunService.RenderStepped:Connect(function()
		if self.Dragging then self:_updateDragHover(getMousePos()) end
	end)
end

function RogueToolbar:_startDragFromHotbar(slot: SlotUI, input: InputObject): ()
	if not self.ToolboxOpen or self.Dragging then return end

	local toolId, toolName = slot.Tool.Id, slot.Tool.Name
	local def = self.ToolboxDefById[toolId]
	if not def then
		self:_ensureToolboxDef(toolId, toolName, "Items")
		def = self.ToolboxDefById[toolId]
	end
	if not def then return end

	self.Dragging = true
	self.DragSource = "Hotbar"
	self.DragSourceSlotIndex = slot.Index
	self.DragTool = def
	self.DragUserInputType = input.UserInputType

	self.DragHiddenSlot = slot
	self.DragHiddenSlotPrevVisible = slot.Wrap.Visible
	slot.Wrap.Visible = false

	self.DragGhost = self:_makeDragGhost(toolName, "Drop on slot to swap • Drop between to reorder • Drop on toolbox to return • Drop zone to drop item")
	self.DragConn = RunService.RenderStepped:Connect(function()
		if self.Dragging then self:_updateDragHover(getMousePos()) end
	end)
end

function RogueToolbar:_openToolbox(on: boolean): ()
	if not on and self.Dragging then self:_cancelDrag() end
	self.ToolboxOpen = on
	self.ToolboxLayer.Visible = on
	self:_setToolboxHoverHighlight(false)
	self:_setRowHighlight(false)
	self:_setDropZoneHighlight(false)
	self:_clearPreview()
	if on then
		self:_setTabActive(self.CurrentTab)
		self:_rebuildToolbox()
	end
end

function RogueToolbar:_tickCooldowns(): ()
	local now = time()
	for _, slot in ipairs(self.AllSlots) do
		local endT = slot.CooldownEnd
		if endT <= 0 then continue end

		local remaining = endT - now
		if remaining <= 0 then
			slot.CooldownEnd = 0
			slot.CooldownFill.Visible = false
			slot.CooldownFill.Size = UDim2.fromScale(1, 0)
		else
			local alpha = math.clamp(remaining / slot.Tool.Cooldown, 0, 1)
			slot.CooldownFill.Visible = true
			slot.CooldownFill.Size = UDim2.fromScale(1, alpha)
		end
	end
end

function RogueToolbar:_onResize(): ()
	self.SlotPx = self:_computeSlotPx()
	for _, s in ipairs(self.AllSlots) do
		s.Wrap.Size = UDim2.fromOffset(self.SlotPx, self.SlotPx)
	end
	self:_layoutHotbarNormal(false)
	if self.ToolboxOpen then self:_rebuildToolbox() end
	if self.Row.BackgroundTransparency < 1 then self:_setRowHighlight(true) end
end

return RogueToolbar
