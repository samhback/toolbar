--!strict
-- StarterPlayerScripts/RogueToolbar.client.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

-- NOTE: your module is named "Tools" here (per your require). Keep as-is.
local RogueToolbar = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Tools"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Start EMPTY: no dummy hotbar tools and no dummy toolbox tools.
local toolbar = RogueToolbar.MakeToolbar(playerGui, {
	InitialHotbarTools = {},
	InitialToolboxDefs = {},
	StartTab = "Powers",
})

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	toolbar:HandleKeybind(input, gameProcessed)
end)

----------------------------------------------------------------
-- FIX:
-- If the player has two Tools with the same Name (or same ToolId attr),
-- the toolbar can end up toggling between them (can't truly unequip).
--
-- Solution: ensure EVERY physical Tool instance has a UNIQUE ToolId attribute.
-- - If ToolId is missing/blank, assign a GUID.
-- - If ToolId collides with a different Tool instance, rewrite to a unique variant.
-- This preserves the display name via ToolName, while giving the equip logic a stable unique key.
----------------------------------------------------------------

-- Tools may be parented to Character first (auto-equip), then Backpack later.
-- We listen to BOTH Character and Backpack and dedupe by Tool reference.
local processedTools: { [Tool]: boolean } = {}

-- Track which ToolId strings are currently claimed by which Tool instance.
local claimedToolIds: { [string]: Tool } = {}
local toolToClaimedId: { [Tool]: string } = {}

local function guidShort(): string
	-- GenerateGUID(false) => "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
	-- Keep it readable but collision-resistant enough for a session.
	local g = HttpService:GenerateGUID(false)
	return string.gsub(g, "%-", "")
end

local function ensureUniqueToolId(toolInst: Tool): string
	local currentAttr = toolInst:GetAttribute("ToolId")
	local baseId = (type(currentAttr) == "string" and currentAttr ~= "") and currentAttr or toolInst.Name

	-- If this tool already claimed an id, keep using it (stable)
	local existing = toolToClaimedId[toolInst]
	if existing ~= nil then
		return existing
	end

	-- If baseId is free, claim it.
	local owner = claimedToolIds[baseId]
	if owner == nil or owner == toolInst then
		claimedToolIds[baseId] = toolInst
		toolToClaimedId[toolInst] = baseId

		-- Write back so any equip logic relying on ToolId can find the exact instance.
		toolInst:SetAttribute("ToolId", baseId)
		return baseId
	end

	-- Collision: generate a unique variant and claim it.
	local uniqueId = baseId .. "_" .. guidShort()
	while claimedToolIds[uniqueId] ~= nil do
		uniqueId = baseId .. "_" .. guidShort()
	end

	claimedToolIds[uniqueId] = toolInst
	toolToClaimedId[toolInst] = uniqueId
	toolInst:SetAttribute("ToolId", uniqueId)

	return uniqueId
end

local function releaseToolId(toolInst: Tool)
	local id = toolToClaimedId[toolInst]
	if id ~= nil then
		if claimedToolIds[id] == toolInst then
			claimedToolIds[id] = nil
		end
		toolToClaimedId[toolInst] = nil
	end
end

local function registerPickupTool(toolInst: Tool)
	if processedTools[toolInst] then return end
	processedTools[toolInst] = true

	local toolId = ensureUniqueToolId(toolInst)

	local toolNameAttr = toolInst:GetAttribute("ToolName")
	local toolName = (type(toolNameAttr) == "string" and toolNameAttr ~= "") and toolNameAttr or toolInst.Name

	local kindAttr = toolInst:GetAttribute("Kind")
	local kind: "Powers" | "Items" = (kindAttr == "Powers") and "Powers" or "Items"

	local iconTextAttr = toolInst:GetAttribute("IconText")
	local iconText = (type(iconTextAttr) == "string") and iconTextAttr or ""

	-- Try hotbar first; if full, go to toolbox.
	local placedInHotbar = toolbar:AddToolToToolbar(toolId, toolName, nil)
	if placedInHotbar then
		toolbar:SelectAndEquipById(toolId)
	else
		toolbar:AddToolToToolbox({
			Id = toolId,
			Name = toolName,
			Kind = kind,
			IconText = iconText,
		}, true)
		toolbar:EnsureUnequippedById(toolId)
	end
end

local function watchContainer(container: Instance)
	for _, inst in ipairs(container:GetChildren()) do
		if inst:IsA("Tool") then
			registerPickupTool(inst)
		end
	end

	container.ChildAdded:Connect(function(inst: Instance)
		if inst:IsA("Tool") then
			registerPickupTool(inst)
		end
	end)

	-- Cleanup:
	-- - If the Tool is actually destroyed (Parent == nil), release its claimed id and processed flag.
	-- - If it simply moves between Backpack/Character, keep state.
	container.ChildRemoved:Connect(function(inst: Instance)
		if not inst:IsA("Tool") then return end
		local t = inst :: Tool
		if t.Parent == nil then
			processedTools[t] = nil
			releaseToolId(t)
		end
	end)
end

-- Always watch backpack
local backpack = player:WaitForChild("Backpack")
watchContainer(backpack)

-- Watch current character + future respawns
local function attachCharacter(char: Model)
	watchContainer(char)
end

if player.Character then
	attachCharacter(player.Character)
end

player.CharacterAdded:Connect(function(char)
	attachCharacter(char)
end)
