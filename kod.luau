-- Chat Commands Script (Autoexec + All Games Universal, No UI Panel) - Prefix: ";"
-- Commands: ;fly [speed] (;flay), ;unfly (;uf), ;flyspeed <num> (;fs), ;tp <player> (;to), ;cmds (;help), ;unload

if not game:IsLoaded() then
	pcall(function()
		game.Loaded:Wait()
	end)
end

local Players = game:GetService("Players")
while not Players.LocalPlayer do
	task.wait(0.1)
end

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local lp = Players.LocalPlayer

local env = (type(getgenv) == "function" and getgenv()) or _G
if type(env._ChatFlyCleanup) == "function" then
	pcall(env._ChatFlyCleanup)
end

local function getSafeGuiParent()
	if type(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and typeof(hui) == "Instance" then
			return hui
		end
	end
	local okCore = pcall(function()
		return CoreGui:GetChildren()
	end)
	if okCore then
		return CoreGui
	end
	return lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui", 10) or CoreGui
end

local guiParent = getSafeGuiParent()
for _, container in ipairs({ guiParent, CoreGui, lp:FindFirstChildOfClass("PlayerGui") }) do
	if typeof(container) == "Instance" then
		pcall(function()
			for _, child in ipairs(container:GetChildren()) do
				if child.Name == "ChatCmdAutocompleteGui" then
					pcall(function() child:Destroy() end)
				end
			end
		end)
	end
end

local PREFIX = ";"

local state = {
	running = true,
	flying = false,
	flySpeed = 60,
	esp = false,
	wse = false,
	fps = false,
}

local connections = {}
local createdCommands = {}
local bodyGyro = nil
local bodyVel = nil
local flyConn = nil
local lastCmdText = nil
local lastCmdTime = 0
local lastTpAt = 0
local lastSentViaTcs = {}

local function track(conn)
	table.insert(connections, conn)
	return conn
end

local function findSystemTextChannel()
	local fallback = nil
	for _, d in ipairs(TextChatService:GetDescendants()) do
		if d:IsA("TextChannel") and d.DisplaySystemMessage then
			if d.Name == "RBXSystem" then
				return d
			elseif d.Name == "RBXGeneral" then
				fallback = d
			elseif not fallback then
				fallback = d
			end
		end
	end
	return fallback
end

local function sendSystemChatText(clean)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local ch = findSystemTextChannel()
		if ch then
			return pcall(function()
				ch:DisplaySystemMessage("<font color='#55FF7F'>[Cmd]</font> " .. clean)
			end)
		end
		return false
	end
	return pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = "[Cmd] " .. clean,
			Color = Color3.fromRGB(85, 255, 127),
		})
	end)
end

local function notifyChat(msg)
	local clean = tostring(msg)
	print("[ChatCmd] " .. clean)
	return sendSystemChatText(clean)
end

local function getRig()
	local char = lp.Character
	if not char then return nil, nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("UpperTorso")
	if not hum or not root or hum.Health <= 0 then
		return nil, nil, nil
	end
	return char, hum, root
end

local function findCharacterHumanoid(char)
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") or char:FindFirstChildWhichIsA("Humanoid", true)
end

local function findNamedBasePart(char, names)
	if not char then return nil end
	for _, name in ipairs(names) do
		local direct = char:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then
			return direct
		end
	end
	local wanted = {}
	for _, name in ipairs(names) do
		wanted[name] = true
	end
	local found = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and wanted[d.Name] and not found[d.Name] then
			found[d.Name] = d
		end
	end
	for _, name in ipairs(names) do
		if found[name] then
			return found[name]
		end
	end
	return nil
end

local function findCharacterAnchor(char)
	if not char then return nil, nil end
	local part = findNamedBasePart(char, {
		"HumanoidRootPart",
		"UpperTorso",
		"Torso",
		"Collider",
		"HeadsetPart",
		"Head",
		"Base",
	})
	if not part then
		if char.PrimaryPart and char.PrimaryPart:IsA("BasePart") then
			part = char.PrimaryPart
		else
			part = char:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	if part and part:IsA("BasePart") then
		return part, part.CFrame
	end
	local okPivot, pivotCF = pcall(function()
		return char:GetPivot()
	end)
	if okPivot and typeof(pivotCF) == "CFrame" then
		return nil, pivotCF
	end
	return nil, nil
end

local function stopFly(silent)
	state.flying = false
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	if bodyGyro then
		pcall(function() bodyGyro:Destroy() end)
		bodyGyro = nil
	end
	if bodyVel then
		pcall(function() bodyVel:Destroy() end)
		bodyVel = nil
	end
	local char = lp.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if not silent then
		notifyChat("Fly: OFF")
	end
end

local function startFly(speedArg)
	if speedArg ~= nil then
		local n = tonumber(speedArg)
		if n and n > 0 then
			state.flySpeed = math.clamp(n, 1, 1000)
		end
	end

	local _, hum, root = getRig()
	if not hum or not root then
		notifyChat("Character topilmadi (tirik emas).")
		return
	end

	stopFly(true)
	state.flying = true

	for _, c in ipairs(root:GetChildren()) do
		if c.Name == "_ChatFlyGyro" or c.Name == "_ChatFlyVel" then
			pcall(function() c:Destroy() end)
		end
	end

	local bg = Instance.new("BodyGyro")
	bg.Name = "_ChatFlyGyro"
	bg.P = 9e4
	bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	bg.CFrame = root.CFrame
	bg.Parent = root
	bodyGyro = bg

	local bv = Instance.new("BodyVelocity")
	bv.Name = "_ChatFlyVel"
	bv.P = 9e4
	bv.Velocity = Vector3.zero
	bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bv.Parent = root
	bodyVel = bv

	hum.PlatformStand = true
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.PlatformStanding) end)

	flyConn = RunService.RenderStepped:Connect(function()
		if not state.running or not state.flying then
			return
		end
		local _, curHum, curRoot = getRig()
		if not curHum or not curRoot or not bodyGyro or not bodyVel or bodyGyro.Parent ~= curRoot then
			stopFly(true)
			return
		end

		curHum.PlatformStand = true
		local cam = Workspace.CurrentCamera
		local camCF = cam and cam.CFrame or curRoot.CFrame
		bodyGyro.CFrame = camCF

		if UserInputService:GetFocusedTextBox() ~= nil then
			bodyVel.Velocity = Vector3.zero
			return
		end

		local moveVec = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			moveVec += camCF.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			moveVec -= camCF.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			moveVec += camCF.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			moveVec -= camCF.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			moveVec += Vector3.yAxis
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			moveVec -= Vector3.yAxis
		end

		if moveVec.Magnitude < 0.01 and curHum.MoveDirection.Magnitude > 0.05 then
			moveVec = curHum.MoveDirection
		end

		if moveVec.Magnitude > 0.01 then
			bodyVel.Velocity = moveVec.Unit * state.flySpeed
		else
			bodyVel.Velocity = Vector3.zero
		end
	end)

	notifyChat("Fly: ON (Speed: " .. tostring(state.flySpeed) .. ") | W/A/S/D + Space + Ctrl/Q")
end

-- Command Registry & Metadata for Chat ';' Autocomplete
local commandEntries = {
	{ name = "fly", hint = "[speed] Uchishni yoqish", takesArg = true },
	{ name = "unfly", hint = "Uchishni o'chirish", takesArg = false },
	{ name = "flyspeed", hint = "<son> Uchish tezligi", takesArg = true },
	{ name = "tp", hint = "<ism> O'yinchiga teleport", takesArg = true },
	{ name = "esp", hint = "Skelet + Jon + Ism ESP", takesArg = false },
	{ name = "wse", hint = "Teggan odamni uzoqqa uchirish", takesArg = false },
	{ name = "fps", hint = "FPS Boost (soya/effektlarni o'chirish)", takesArg = false },
	{ name = "cmds", hint = "Komandalar ro'yxati", takesArg = false },
	{ name = "unload", hint = "Skriptni o'chirish", takesArg = false },
}

-- =====================================================================
-- FPS Boost (;fps / ;unfps - reversible Lighting, Terrain & Particle optimizer)
-- =====================================================================
local Lighting = game:GetService("Lighting")
local fpsConn = nil
local fpsToken = 0
local fpsBackup = nil

local function isPartInsideCharacter(inst)
	local model = inst:FindFirstAncestorWhichIsA("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function applyFpsToInstance(inst, bk)
	if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
		or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
		if inst.Enabled then
			bk.enabled[inst] = true
			inst.Enabled = false
		end
	elseif inst:IsA("BasePart") then
		if inst.CastShadow then
			bk.shadows[inst] = true
			inst.CastShadow = false
		end
		if inst.Reflectance > 0 then
			bk.reflect[inst] = inst.Reflectance
			inst.Reflectance = 0
		end
		if inst.Material ~= Enum.Material.SmoothPlastic
			and inst.Material ~= Enum.Material.Neon
			and inst.Material ~= Enum.Material.ForceField
			and not isPartInsideCharacter(inst) then
			bk.materials[inst] = inst.Material
			inst.Material = Enum.Material.SmoothPlastic
		end
	end
end

local function stopFpsBoost(silent)
	state.fps = false
	fpsToken += 1
	if fpsConn then
		pcall(function() fpsConn:Disconnect() end)
		fpsConn = nil
	end
	local bk = fpsBackup
	fpsBackup = nil
	if bk then
		pcall(function() Lighting.GlobalShadows = bk.globalShadows end)
		if bk.technology ~= nil and type(sethiddenproperty) == "function" then
			pcall(sethiddenproperty, Lighting, "Technology", bk.technology)
		end
		if bk.qualityLevel ~= nil then
			pcall(function() settings().Rendering.QualityLevel = bk.qualityLevel end)
		end
		for obj, val in pairs(bk.postEffects) do
			if obj and obj.Parent then pcall(function() obj.Enabled = val end) end
		end
		for obj, val in pairs(bk.atmospheres) do
			if obj and obj.Parent then pcall(function() obj.Density = val end) end
		end
		for obj, val in pairs(bk.clouds) do
			if obj and obj.Parent then pcall(function() obj.Enabled = val end) end
		end
		if bk.terrain and bk.terrain.obj and bk.terrain.obj.Parent then
			local tr = bk.terrain.obj
			pcall(function()
				tr.WaterWaveSize = bk.terrain.waveSize
				tr.WaterWaveSpeed = bk.terrain.waveSpeed
				tr.WaterReflectance = bk.terrain.reflectance
				tr.WaterTransparency = bk.terrain.transparency
			end)
			if type(sethiddenproperty) == "function" then
				pcall(sethiddenproperty, tr, "Decoration", true)
			end
		end
		for obj, _ in pairs(bk.enabled) do
			if obj and obj.Parent then pcall(function() obj.Enabled = true end) end
		end
		for obj, _ in pairs(bk.shadows) do
			if obj and obj.Parent then pcall(function() obj.CastShadow = true end) end
		end
		for obj, val in pairs(bk.reflect) do
			if obj and obj.Parent then pcall(function() obj.Reflectance = val end) end
		end
		for obj, val in pairs(bk.materials) do
			if obj and obj.Parent then pcall(function() obj.Material = val end) end
		end
	end
	if not silent then
		notifyChat("FPS Boost: OFF (Asl grafika tiklandi)")
	end
end

local function startFpsBoost()
	if state.fps then return end
	state.fps = true
	fpsToken += 1
	local myToken = fpsToken

	local bk = {
		globalShadows = Lighting.GlobalShadows,
		technology = Lighting.Technology,
		qualityLevel = nil,
		postEffects = {},
		atmospheres = {},
		clouds = {},
		terrain = nil,
		enabled = {},
		shadows = {},
		reflect = {},
		materials = {},
	}
	fpsBackup = bk

	pcall(function()
		bk.qualityLevel = settings().Rendering.QualityLevel
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	if type(setfpscap) == "function" then
		pcall(setfpscap, 999)
	end

	pcall(function() Lighting.GlobalShadows = false end)
	if type(sethiddenproperty) == "function" then
		pcall(sethiddenproperty, Lighting, "Technology", Enum.Technology.Compatibility)
	end
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("PostEffect") then
			bk.postEffects[c] = c.Enabled
			pcall(function() c.Enabled = false end)
		elseif c:IsA("Atmosphere") then
			bk.atmospheres[c] = c.Density
			pcall(function() c.Density = 0 end)
		elseif c:IsA("Clouds") then
			bk.clouds[c] = c.Enabled
			pcall(function() c.Enabled = false end)
		end
	end

	local tr = Workspace:FindFirstChildOfClass("Terrain")
	if tr then
		bk.terrain = {
			obj = tr,
			waveSize = tr.WaterWaveSize,
			waveSpeed = tr.WaterWaveSpeed,
			reflectance = tr.WaterReflectance,
			transparency = tr.WaterTransparency,
		}
		pcall(function()
			tr.WaterWaveSize = 0
			tr.WaterWaveSpeed = 0
			tr.WaterReflectance = 0
			tr.WaterTransparency = 0
		end)
		if type(sethiddenproperty) == "function" then
			pcall(sethiddenproperty, tr, "Decoration", false)
		end
	end

	fpsConn = Workspace.DescendantAdded:Connect(function(inst)
		if not state.running or not state.fps or myToken ~= fpsToken then return end
		pcall(applyFpsToInstance, inst, bk)
	end)

	-- Chunked non-blocking scan so large maps never freeze during activation
	task.spawn(function()
		local all = Workspace:GetDescendants()
		for i = 1, #all do
			if not state.running or not state.fps or myToken ~= fpsToken then return end
			pcall(applyFpsToInstance, all[i], bk)
			if i % 400 == 0 then
				task.wait()
			end
		end
	end)

	notifyChat("FPS Boost: ON (Soya, effekt, zarracha va sifat optimallashtirildi)")
end

-- =====================================================================
-- Touch Fling / WSE (Launches touching players/bots away without self-fling)
-- =====================================================================
local wseConns = {}
local FLING_PARTS = { "HumanoidRootPart", "UpperTorso", "LowerTorso", "Head", "Torso", "CollisionPart" }

local function restoreFlyForces()
	if state.flying then
		if bodyVel and bodyVel.Parent then
			bodyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		end
		if bodyGyro and bodyGyro.Parent then
			bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
		end
	end
end

local function stopWse(silent)
	state.wse = false
	for _, c in ipairs(wseConns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(wseConns)
	restoreFlyForces()
	local char = lp.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
		if root and root:IsA("BasePart") then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end)
		end
		for _, name in ipairs({ "Torso", "UpperTorso", "LowerTorso", "Head" }) do
			local p = char:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				pcall(function() p.CanCollide = false end)
			end
		end
	end
	if not silent then
		notifyChat("WSE: OFF")
	end
end

local function startWse()
	if state.wse then return end
	stopWse(true)
	state.wse = true

	if lp.Character and lp.Character:GetAttribute("InSafezone") == true then
		pcall(function() lp.Character:SetAttribute("InSafezone", false) end)
	end

	local safeVel = Vector3.zero
	local movel = 0.1
	local inFlingPulse = false
	local savedCF = nil

	local function ensureCollisions(char)
		if not char then return end
		for _, name in ipairs(FLING_PARTS) do
			local p = char:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				p.CanCollide = true
				p.CanTouch = true
			end
		end
	end

	local function findNearbyTarget(myPos, range)
		local bestTarget, bestDist = nil, range or 7.5
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp and p.Character then
				local pHum = findCharacterHumanoid(p.Character)
				local pRoot = p.Character:FindFirstChild("HumanoidRootPart") 
					or p.Character:FindFirstChild("Torso") 
					or p.Character:FindFirstChild("UpperTorso")
				if pRoot and (not pHum or pHum.Health > 0) then
					local d = (pRoot.Position - myPos).Magnitude
					if d <= bestDist then
						bestDist = d
						bestTarget = pRoot
					end
				end
			end
		end
		if not bestTarget then
			for _, m in ipairs(Workspace:GetChildren()) do
				if m:IsA("Model") and m ~= lp.Character then
					local hum = m:FindFirstChildOfClass("Humanoid")
					local root = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
					if hum and root and hum.Health > 0 then
						local d = (root.Position - myPos).Magnitude
						if d <= bestDist then
							bestDist = d
							bestTarget = root
						end
					end
				end
			end
		end
		return bestTarget
	end

	table.insert(wseConns, RunService.Stepped:Connect(function()
		if not state.running or not state.wse then return end
		local myChar, _, root = getRig()
		if not myChar or not root then
			inFlingPulse = false
			savedCF = nil
			return
		end

		if myChar:GetAttribute("InSafezone") == true then
			pcall(function() myChar:SetAttribute("InSafezone", false) end)
		end

		ensureCollisions(myChar)

		local cur = root.AssemblyLinearVelocity
		if cur.Magnitude < 250 then
			safeVel = cur
		end

		local targetRoot = findNearbyTarget(root.Position, 7.5)
		if targetRoot then
			inFlingPulse = true
			savedCF = root.CFrame
			if state.flying and bodyGyro and bodyGyro.Parent then
				bodyGyro.MaxTorque = Vector3.zero
			end
			local diff = targetRoot.Position - root.Position
			local flat = Vector3.new(diff.X, 0, diff.Z)
			local flingDir = (flat.Magnitude > 0.1) and flat.Unit or root.CFrame.LookVector
			root.AssemblyAngularVelocity = Vector3.new(4000000, 4000000, 4000000)
			root.AssemblyLinearVelocity = Vector3.new(flingDir.X * 5000000, 80000, flingDir.Z * 5000000)
		else
			inFlingPulse = false
			root.AssemblyAngularVelocity = Vector3.zero
			root.AssemblyLinearVelocity = safeVel + Vector3.new(0, movel, 0)
			movel = -movel
		end
	end))

	table.insert(wseConns, RunService.Heartbeat:Connect(function(dt)
		if not state.running or not state.wse then return end
		local _, _, root = getRig()
		if not root then return end

		if inFlingPulse then
			inFlingPulse = false
			restoreFlyForces()
			root.AssemblyAngularVelocity = Vector3.zero
			root.AssemblyLinearVelocity = safeVel
			if savedCF then
				local dtClamped = math.min(dt or 0.016, 0.035)
				root.CFrame = savedCF + safeVel * dtClamped
			end
		end
	end))

	table.insert(wseConns, RunService.RenderStepped:Connect(function()
		if not state.running or not state.wse then return end
		local _, _, root = getRig()
		if root and not inFlingPulse then
			root.AssemblyLinearVelocity = safeVel
		end
	end))

	notifyChat("WSE: ON (Teggan odam/bot uzoqqa uchadi!)")
end

-- =====================================================================
-- Player ESP (Clean Translucent Skeleton + Health + Name, R15 + R6)
-- =====================================================================
local R15_BONES = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}

local espEntries = {}
local espConn = nil

local function newDrawingLine(thickness, color)
	local ln = Drawing.new("Line")
	ln.Thickness = thickness
	ln.Color = color
	ln.Transparency = 0.8
	ln.Visible = false
	return ln
end

local function newDrawingText(size, color, centered)
	local tx = Drawing.new("Text")
	tx.Size = size
	tx.Color = color
	tx.Center = centered
	tx.Outline = true
	pcall(function() tx.OutlineColor = Color3.fromRGB(0, 0, 0) end)
	tx.Transparency = 0.9
	tx.Visible = false
	return tx
end

local function createEspEntry()
	local lines = {}
	for i = 1, #R15_BONES do
		lines[i] = newDrawingLine(1.25, Color3.fromRGB(115, 240, 255))
	end
	local headCircle = nil
	local okC, cir = pcall(Drawing.new, "Circle")
	if okC and cir then
		cir.Thickness = 1.25
		cir.NumSides = 16
		cir.Filled = false
		cir.Color = Color3.fromRGB(115, 240, 255)
		cir.Transparency = 0.8
		cir.Visible = false
		headCircle = cir
	end
	return {
		lines = lines,
		headCircle = headCircle,
		nameText = newDrawingText(13, Color3.fromRGB(242, 246, 252), true),
		hpText = newDrawingText(12, Color3.fromRGB(95, 245, 135), false),
		hpBg = newDrawingLine(4, Color3.fromRGB(12, 14, 18)),
		hpFill = newDrawingLine(2, Color3.fromRGB(95, 245, 135)),
	}
end

local function hideEspEntry(entry)
	for _, ln in ipairs(entry.lines) do
		ln.Visible = false
	end
	if entry.headCircle then
		entry.headCircle.Visible = false
	end
	entry.nameText.Visible = false
	entry.hpText.Visible = false
	entry.hpBg.Visible = false
	entry.hpFill.Visible = false
end

local function destroyEspEntry(entry)
	if not entry then return end
	for _, ln in ipairs(entry.lines) do
		pcall(function() ln:Remove() end)
	end
	if entry.headCircle then
		pcall(function() entry.headCircle:Remove() end)
	end
	pcall(function() entry.nameText:Remove() end)
	pcall(function() entry.hpText:Remove() end)
	pcall(function() entry.hpBg:Remove() end)
	pcall(function() entry.hpFill:Remove() end)
end

local function stopEsp(silent)
	state.esp = false
	if espConn then
		espConn:Disconnect()
		espConn = nil
	end
	for p, entry in pairs(espEntries) do
		destroyEspEntry(entry)
		espEntries[p] = nil
	end
	if not silent then
		notifyChat("ESP: OFF")
	end
end

local function drawWorldSegment(cam, vw, vh, ln, worldA, worldB, color, thickness, alpha)
	local vA = cam:WorldToViewportPoint(worldA)
	local vB = cam:WorldToViewportPoint(worldB)
	if vA.Z > 0.2 and vB.Z > 0.2 then
		local inX = (vA.X >= -120 and vA.X <= vw + 120) or (vB.X >= -120 and vB.X <= vw + 120)
		local inY = (vA.Y >= -120 and vA.Y <= vh + 120) or (vB.Y >= -120 and vB.Y <= vh + 120)
		if inX and inY then
			ln.From = Vector2.new(vA.X, vA.Y)
			ln.To = Vector2.new(vB.X, vB.Y)
			ln.Color = color
			ln.Thickness = thickness
			ln.Transparency = alpha
			ln.Visible = true
			return
		end
	end
	ln.Visible = false
end

local function updateEspFrame()
	if not state.running or not state.esp then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end

	local camPos = cam.CFrame.Position
	local vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
	local seen = {}
	local activeTargets = {}

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp then
			seen[p] = true
			local entry = espEntries[p]
			local char = p.Character
			local hum = findCharacterHumanoid(char)
			local anchorPart = char and (findNamedBasePart(char, { "Head" }) or findCharacterAnchor(char))

			if not char or not hum or hum.Health <= 0 or not anchorPart or not anchorPart:IsA("BasePart") then
				if entry then
					hideEspEntry(entry)
				end
			else
				if not entry then
					local ok, created = pcall(createEspEntry)
					if ok and created then
						entry = created
						espEntries[p] = entry
					end
				end
				if entry then
					local dist = (camPos - anchorPart.Position).Magnitude
					table.insert(activeTargets, {
						player = p,
						entry = entry,
						char = char,
						hum = hum,
						anchor = anchorPart,
						dist = dist,
					})
				end
			end
		end
	end

	table.sort(activeTargets, function(a, b)
		return a.dist < b.dist
	end)

	local placedLabels = {}
	local boneColor = Color3.fromRGB(115, 240, 255)

	for _, item in ipairs(activeTargets) do
		local p = item.player
		local entry = item.entry
		local char = item.char
		local hum = item.hum
		local anchorPart = item.anchor
		local dist = item.dist

		-- Translucent fade with distance so close players are crisp & far crowds stay subtle
		local skelAlpha = math.clamp(0.82 - (dist / 500) * 0.44, 0.36, 0.82)
		local textAlpha = math.clamp(0.92 - (dist / 450) * 0.45, 0.42, 0.92)
		local skelThick = (dist < 85) and 1.35 or 1.05

		-- Head ring
		local headPart = findNamedBasePart(char, { "Head", "HeadsetPart", "Base" }) or anchorPart
		if entry.headCircle then
			if headPart and headPart:IsA("BasePart") then
				local hv = cam:WorldToViewportPoint(headPart.Position)
				if hv.Z > 0.2 and hv.X > -80 and hv.X < vw + 80 and hv.Y > -80 and hv.Y < vh + 80 then
					entry.headCircle.Position = Vector2.new(hv.X, hv.Y)
					entry.headCircle.Radius = math.clamp(170 / math.max(dist, 8), 2.5, 8.5)
					entry.headCircle.Thickness = skelThick
					entry.headCircle.Color = boneColor
					entry.headCircle.Transparency = skelAlpha
					entry.headCircle.Visible = true
				else
					entry.headCircle.Visible = false
				end
			else
				entry.headCircle.Visible = false
			end
		end

		-- Skeleton (R15 joint-parts or anatomical R6 CFrame joints or fallback)
		local usedLines = 0
		if char:FindFirstChild("UpperTorso") then
			for i = 1, #R15_BONES do
				usedLines = i
				local pair = R15_BONES[i]
				local pA = char:FindFirstChild(pair[1])
				local pB = char:FindFirstChild(pair[2])
				if pA and pB and pA:IsA("BasePart") and pB:IsA("BasePart") then
					drawWorldSegment(cam, vw, vh, entry.lines[i], pA.Position, pB.Position, boneColor, skelThick, skelAlpha)
				else
					entry.lines[i].Visible = false
				end
			end
		else
			local torso = char:FindFirstChild("Torso")
			local lArm = char:FindFirstChild("Left Arm")
			local rArm = char:FindFirstChild("Right Arm")
			local lLeg = char:FindFirstChild("Left Leg")
			local rLeg = char:FindFirstChild("Right Leg")
			if torso and torso:IsA("BasePart") then
				local tCF = torso.CFrame
				local neck = (tCF * CFrame.new(0, torso.Size.Y * 0.42, 0)).Position
				local pelvis = (tCF * CFrame.new(0, -torso.Size.Y * 0.45, 0)).Position
				if headPart and headPart:IsA("BasePart") then
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], headPart.Position, neck, boneColor, skelThick, skelAlpha)
				end
				usedLines += 1
				drawWorldSegment(cam, vw, vh, entry.lines[usedLines], neck, pelvis, boneColor, skelThick, skelAlpha)
				if lArm and lArm:IsA("BasePart") then
					local lSh = (tCF * CFrame.new(-torso.Size.X * 0.65, torso.Size.Y * 0.35, 0)).Position
					local lHand = (lArm.CFrame * CFrame.new(0, -lArm.Size.Y * 0.42, 0)).Position
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], neck, lSh, boneColor, skelThick, skelAlpha)
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], lSh, lHand, boneColor, skelThick, skelAlpha)
				end
				if rArm and rArm:IsA("BasePart") then
					local rSh = (tCF * CFrame.new(torso.Size.X * 0.65, torso.Size.Y * 0.35, 0)).Position
					local rHand = (rArm.CFrame * CFrame.new(0, -rArm.Size.Y * 0.42, 0)).Position
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], neck, rSh, boneColor, skelThick, skelAlpha)
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], rSh, rHand, boneColor, skelThick, skelAlpha)
				end
				if lLeg and lLeg:IsA("BasePart") then
					local lHip = (tCF * CFrame.new(-torso.Size.X * 0.25, -torso.Size.Y * 0.45, 0)).Position
					local lFoot = (lLeg.CFrame * CFrame.new(0, -lLeg.Size.Y * 0.45, 0)).Position
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], pelvis, lHip, boneColor, skelThick, skelAlpha)
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], lHip, lFoot, boneColor, skelThick, skelAlpha)
				end
				if rLeg and rLeg:IsA("BasePart") then
					local rHip = (tCF * CFrame.new(torso.Size.X * 0.25, -torso.Size.Y * 0.45, 0)).Position
					local rFoot = (rLeg.CFrame * CFrame.new(0, -rLeg.Size.Y * 0.45, 0)).Position
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], pelvis, rHip, boneColor, skelThick, skelAlpha)
					usedLines += 1
					drawWorldSegment(cam, vw, vh, entry.lines[usedLines], rHip, rFoot, boneColor, skelThick, skelAlpha)
				end
			else
				local root = char:FindFirstChild("HumanoidRootPart")
				if headPart and root and headPart:IsA("BasePart") and root:IsA("BasePart") then
					usedLines = 1
					drawWorldSegment(cam, vw, vh, entry.lines[1], headPart.Position, root.Position, boneColor, skelThick, skelAlpha)
				end
			end
		end
		for i = usedLines + 1, #entry.lines do
			entry.lines[i].Visible = false
		end

		-- Header: Name above, HP bar + HP number cleanly side-by-side below (zero overlap!)
		local yOffset = (anchorPart.Name == "Head") and (anchorPart.Size.Y * 0.5 + 0.55) or 2.8
		local vp, onScreen = cam:WorldToViewportPoint(anchorPart.Position + Vector3.new(0, yOffset, 0))
		if vp.Z > 0.2 and (onScreen or (vp.X > -80 and vp.X < vw + 80 and vp.Y > -40 and vp.Y < vh + 40)) then
			local barY = math.round(vp.Y - 7)
			local crowdOverlap = false
			for _, box in ipairs(placedLabels) do
				if math.abs(vp.X - box.x) < 92 and math.abs(barY - box.y) < 30 then
					crowdOverlap = true
					break
				end
			end

			local maxHp = math.max(1, hum.MaxHealth)
			local hp = math.clamp(hum.Health, 0, maxHp)
			local pct = hp / maxHp
			local hpColor = Color3.fromRGB(math.round(255 * (1 - pct)), math.round(255 * pct), 75)

			if crowdOverlap then
				-- Keep only a tiny uncluttered HP bar if a closer player's label occupies this spot
				entry.nameText.Visible = false
				entry.hpText.Visible = false
				local miniW = 24
				local mx1 = math.round(vp.X - miniW * 0.5)
				entry.hpBg.From = Vector2.new(mx1 - 1, barY)
				entry.hpBg.To = Vector2.new(mx1 + miniW + 1, barY)
				entry.hpBg.Transparency = skelAlpha * 0.85
				entry.hpBg.Visible = true

				entry.hpFill.Color = hpColor
				entry.hpFill.From = Vector2.new(mx1, barY)
				entry.hpFill.To = Vector2.new(mx1 + math.max(1, miniW * pct), barY)
				entry.hpFill.Transparency = skelAlpha
				entry.hpFill.Visible = (hp > 0)
			else
				table.insert(placedLabels, { x = vp.X, y = barY })

				local hpLabel = (math.round(maxHp) ~= 100)
					and string.format("%d/%d", math.round(hp), math.round(maxHp))
					or (tostring(math.round(hp)) .. " HP")

				local barW = math.clamp(math.round(44 - dist * 0.05), 28, 40)
				local groupW = barW + 6 + 34
				local barX1 = math.round(vp.X - groupW * 0.5)

				entry.nameText.Text = p.DisplayName
				entry.nameText.Position = Vector2.new(math.round(vp.X), barY - 26)
				entry.nameText.Transparency = textAlpha
				entry.nameText.Visible = true

				entry.hpBg.From = Vector2.new(barX1 - 1, barY)
				entry.hpBg.To = Vector2.new(barX1 + barW + 1, barY)
				entry.hpBg.Transparency = textAlpha * 0.82
				entry.hpBg.Visible = true

				entry.hpFill.Color = hpColor
				entry.hpFill.From = Vector2.new(barX1, barY)
				entry.hpFill.To = Vector2.new(barX1 + math.max(1, barW * pct), barY)
				entry.hpFill.Transparency = textAlpha
				entry.hpFill.Visible = (hp > 0)

				entry.hpText.Text = hpLabel
				entry.hpText.Color = hpColor
				entry.hpText.Position = Vector2.new(barX1 + barW + 6, barY - 7)
				entry.hpText.Transparency = textAlpha
				entry.hpText.Visible = true
			end
		else
			entry.nameText.Visible = false
			entry.hpText.Visible = false
			entry.hpBg.Visible = false
			entry.hpFill.Visible = false
		end
	end

	for p, entry in pairs(espEntries) do
		if not seen[p] then
			destroyEspEntry(entry)
			espEntries[p] = nil
		end
	end
end

local function startEsp()
	if typeof(Drawing) ~= "table" and typeof(Drawing) ~= "userdata" then
		notifyChat("Xatolik: Bu executorda Drawing API mavjud emas.")
		return
	end
	if state.esp then return end
	state.esp = true
	if not espConn then
		espConn = RunService.RenderStepped:Connect(updateEspFrame)
	end
	notifyChat("ESP: ON (Skelet + Jon + Ism)")
end

local function findTargetPlayer(rawQuery)
	if type(rawQuery) ~= "string" then return nil end
	local clean = rawQuery:gsub("[{}@\"']", ""):match("^%s*(.-)%s*$")
	if not clean or clean == "" then return nil end
	local q = string.lower(clean)

	local prefixHit, subHit = nil, nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp then
			local n = string.lower(p.Name)
			local d = string.lower(p.DisplayName)
			if n == q or d == q then
				return p
			end
			if not prefixHit and (n:sub(1, #q) == q or d:sub(1, #q) == q) then
				prefixHit = p
			end
			if not subHit and (n:find(q, 1, true) or d:find(q, 1, true)) then
				subHit = p
			end
		end
	end
	return prefixHit or subHit
end

local commands = {}
local acGui = nil

local function unload()
	if not state.running then return end
	state.running = false
	stopFly(true)
	stopEsp(true)
	stopWse(true)
	stopFpsBoost(true)
	for _, conn in ipairs(connections) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(connections)
	for _, cmdObj in ipairs(createdCommands) do
		pcall(function() cmdObj:Destroy() end)
	end
	table.clear(createdCommands)
	if acGui then
		pcall(function() acGui:Destroy() end)
		acGui = nil
	end
	notifyChat("Chat commands unloaded.")
end

commands.fly = function(args)
	if state.flying and not args[1] then
		stopFly(false)
	else
		startFly(args[1])
	end
end
commands.f = commands.fly
commands.flay = commands.fly

commands.unfly = function()
	stopFly(false)
end
commands.uf = commands.unfly
commands.nofly = commands.unfly
commands.unflay = commands.unfly

commands.flyspeed = function(args)
	local n = tonumber(args[1])
	if not n or n <= 0 then
		notifyChat("Ishlatish: ;flyspeed <son> (hozir: " .. tostring(state.flySpeed) .. ")")
		return
	end
	state.flySpeed = math.clamp(n, 1, 1000)
	notifyChat("FlySpeed: " .. tostring(state.flySpeed))
end
commands.fs = commands.flyspeed
commands.speedfly = commands.flyspeed
commands.flayspeed = commands.flyspeed

commands.tp = function(args)
	local query = table.concat(args, " ")
	if query:match("^%s*$") then
		notifyChat("Ishlatish: ;tp <oyinchi ismi>")
		return
	end
	local target = findTargetPlayer(query)
	if not target then
		notifyChat("O'yinchi topilmadi: " .. query)
		return
	end
	local tChar = target.Character
	local tPart, targetCF = findCharacterAnchor(tChar)
	if not targetCF then
		notifyChat(target.Name .. " hozir maydonda emas (character yo'q).")
		return
	end
	local myChar, myHum, myRoot = getRig()
	if not myChar or not myHum or not myRoot then
		notifyChat("Character topilmadi (tirik emas).")
		return
	end
	if myChar:GetAttribute("Grabbed") then
		pcall(function()
			local com = game:GetService("ReplicatedStorage"):FindFirstChild("COM")
			local pinch = com and com:FindFirstChild("Pinch")
			local letMeGo = pinch and pinch:FindFirstChild("LetMeGo")
			if letMeGo then letMeGo:FireServer() end
		end)
		for _, d in ipairs(myChar:GetDescendants()) do
			if d.Name == "PinchWeld" then
				pcall(function() d:Destroy() end)
			end
		end
	end
	if myChar:GetAttribute("InSafezone") ~= nil then
		pcall(function() myChar:SetAttribute("InSafezone", false) end)
	end
	if myHum.Sit then
		myHum.Sit = false
		task.wait(0.05)
		myChar, myHum, myRoot = getRig()
		if not myChar or not myHum or not myRoot then return end
	end
	local offsetZ = tPart and math.clamp(tPart.Size.Z * 0.5 + 3, 3, 10) or 4
	local destCF = CFrame.new(targetCF.Position + Vector3.new(0, 2, offsetZ))
	if Workspace.StreamingEnabled and (destCF.Position - myRoot.Position).Magnitude > 150 then
		pcall(function()
			lp:RequestStreamAroundAsync(destCF.Position, 0.2)
		end)
	end
	lastTpAt = os.clock()
	myRoot.AssemblyLinearVelocity = Vector3.zero
	myRoot.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		myChar:PivotTo(destCF)
	end)
	myRoot.CFrame = destCF
	for _ = 1, 2 do
		RunService.Heartbeat:Wait()
		if not state.running or not myChar.Parent or not myRoot.Parent then break end
		lastTpAt = os.clock()
		myRoot.AssemblyLinearVelocity = Vector3.zero
		myRoot.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			myChar:PivotTo(destCF)
		end)
		myRoot.CFrame = destCF
	end
	notifyChat("TP -> " .. target.DisplayName .. " (@" .. target.Name .. ")")
end
commands.to = commands.tp
commands.goto = commands.tp

commands.esp = function(args)
	local sub = args[1] and string.lower(args[1])
	if sub == "on" or sub == "yoq" then
		if not state.esp then
			startEsp()
		else
			notifyChat("ESP allaqachon yoqilgan.")
		end
	elseif sub == "off" or sub == "och" then
		stopEsp(false)
	elseif state.esp then
		stopEsp(false)
	else
		startEsp()
	end
end
commands.unesp = function()
	stopEsp(false)
end

commands.wse = function(args)
	local sub = args[1] and string.lower(args[1])
	if sub == "on" or sub == "yoq" then
		if not state.wse then
			startWse()
		else
			notifyChat("WSE allaqachon yoqilgan.")
		end
	elseif sub == "off" or sub == "och" then
		stopWse(false)
	elseif state.wse then
		stopWse(false)
	else
		startWse()
	end
end
commands.unwse = function()
	stopWse(false)
end

commands.fps = function(args)
	local sub = args[1] and string.lower(args[1])
	if sub == "on" or sub == "yoq" then
		if not state.fps then
			startFpsBoost()
		else
			notifyChat("FPS Boost allaqachon yoqilgan.")
		end
	elseif sub == "off" or sub == "och" then
		stopFpsBoost(false)
	elseif state.fps then
		stopFpsBoost(false)
	else
		startFpsBoost()
	end
end
commands.fpsboost = commands.fps
commands.unfps = function()
	stopFpsBoost(false)
end

commands.cmds = function()
	notifyChat("Komandalar: ;fly [speed] | ;unfly | ;flyspeed <son> (;fs) | ;tp <ism> | ;esp | ;wse | ;fps | ;cmds | ;unload")
end
commands.help = commands.cmds

commands.unload = unload
commands.unscript = unload

local function handleChatMessage(rawText, fromTcs)
	if not state.running or type(rawText) ~= "string" then return end
	local trimmed = rawText:match("^%s*(.-)%s*$")
	if not trimmed then return end
	trimmed = trimmed:gsub("^/e%s+", "")
	if trimmed:sub(1, #PREFIX) ~= PREFIX then
		return
	end

	local now = os.clock()
	if fromTcs then
		lastSentViaTcs[trimmed] = now
	end
	if trimmed == lastCmdText and (now - lastCmdTime) < 0.25 then
		return
	end
	lastCmdText = trimmed
	lastCmdTime = now

	local body = trimmed:sub(#PREFIX + 1)
	local parts = {}
	for word in body:gmatch("%S+") do
		table.insert(parts, word)
	end
	if #parts == 0 then return end

	local cmdName = string.lower(table.remove(parts, 1))
	local fn = commands[cmdName]
	if fn then
		task.spawn(fn, parts)
	else
		notifyChat("Noma'lum komanda: ;" .. cmdName .. " (;cmds yozing)")
	end
end

-- =====================================================================
-- Chat ';' Autocomplete Popup (appears ONLY above chat bar when typing ';')
-- =====================================================================
acGui = Instance.new("ScreenGui")
acGui.Name = "ChatCmdAutocompleteGui"
acGui.ResetOnSpawn = false
acGui.DisplayOrder = 100
acGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okParent = pcall(function()
	acGui.Parent = guiParent
end)
if not okParent then
	local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui", 10)
	if pg then
		pcall(function() acGui.Parent = pg end)
	end
end

local acFrame = Instance.new("Frame")
acFrame.Name = "AutocompleteList"
acFrame.Visible = false
acFrame.BackgroundColor3 = Color3.fromRGB(28, 30, 34)
acFrame.BackgroundTransparency = 0.06
acFrame.BorderSizePixel = 0
acFrame.Size = UDim2.fromOffset(398, 0)
acFrame.ClipsDescendants = true
acFrame.Parent = acGui

local acCorner = Instance.new("UICorner")
acCorner.CornerRadius = UDim.new(0, 8)
acCorner.Parent = acFrame

local acStroke = Instance.new("UIStroke")
acStroke.Color = Color3.fromRGB(68, 72, 79)
acStroke.Thickness = 1
acStroke.Parent = acFrame

local acLayout = Instance.new("UIListLayout")
acLayout.SortOrder = Enum.SortOrder.LayoutOrder
acLayout.Padding = UDim.new(0, 0)
acLayout.Parent = acFrame

local ROW_HEIGHT = 32
local selectedIdx = 1
local currentMatches = {}
local currentChatBar = nil
local currentTextBox = nil
local lastTextBoxCheck = 0
local hoverOrClicking = false

local MAX_AC_ROWS = 9
local rowSlots = {}
for idx = 1, MAX_AC_ROWS do
	local rowBtn = Instance.new("TextButton")
	rowBtn.Name = "RowSlot_" .. tostring(idx)
	rowBtn.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	rowBtn.BackgroundColor3 = Color3.fromRGB(28, 30, 34)
	rowBtn.BackgroundTransparency = 0.06
	rowBtn.BorderSizePixel = 0
	rowBtn.AutoButtonColor = false
	rowBtn.Text = ""
	rowBtn.Visible = false
	rowBtn.LayoutOrder = idx
	rowBtn.Parent = acFrame

	local cmdLbl = Instance.new("TextLabel")
	cmdLbl.Name = "CmdText"
	cmdLbl.BackgroundTransparency = 1
	cmdLbl.Position = UDim2.fromOffset(14, 0)
	cmdLbl.Size = UDim2.new(0.60, -14, 1, 0)
	cmdLbl.Font = Enum.Font.GothamMedium
	cmdLbl.TextSize = 15
	cmdLbl.TextColor3 = Color3.fromRGB(245, 246, 250)
	cmdLbl.TextXAlignment = Enum.TextXAlignment.Left
	cmdLbl.TextTruncate = Enum.TextTruncate.AtEnd
	cmdLbl.Text = ""
	cmdLbl.Parent = rowBtn

	local hintLbl = Instance.new("TextLabel")
	hintLbl.Name = "HintText"
	hintLbl.BackgroundTransparency = 1
	hintLbl.Position = UDim2.new(0.60, 0, 0, 0)
	hintLbl.Size = UDim2.new(0.40, -12, 1, 0)
	hintLbl.Font = Enum.Font.Gotham
	hintLbl.TextSize = 13
	hintLbl.TextColor3 = Color3.fromRGB(162, 168, 178)
	hintLbl.TextXAlignment = Enum.TextXAlignment.Right
	hintLbl.TextTruncate = Enum.TextTruncate.AtEnd
	hintLbl.Text = ""
	hintLbl.Parent = rowBtn

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Position = UDim2.new(0, 0, 1, -1)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = Color3.fromRGB(52, 55, 62)
	divider.BackgroundTransparency = 0.3
	divider.BorderSizePixel = 0
	divider.Parent = rowBtn

	rowSlots[idx] = { btn = rowBtn, cmdLbl = cmdLbl, hintLbl = hintLbl, divider = divider }
end

local pendingClickItem = nil
for idx = 1, MAX_AC_ROWS do
	local slot = rowSlots[idx]
	track(slot.btn.MouseEnter:Connect(function()
		hoverOrClicking = true
		if idx <= #currentMatches then
			selectedIdx = idx
		end
	end))
	track(slot.btn.MouseLeave:Connect(function()
		hoverOrClicking = false
	end))
	track(slot.btn.MouseButton1Down:Connect(function()
		pendingClickItem = currentMatches[idx]
	end))
	track(slot.btn.Activated:Connect(function()
		pendingClickItem = currentMatches[idx]
	end))
end

local function applyAutocomplete(tb, item, fromClick)
	if not tb or not item then return end
	local fill = item.fillText or (PREFIX .. item.name .. (item.takesArg and " " or ""))
	if fromClick and item.executeOnClick then
		tb.Text = ""
		acFrame.Visible = false
		table.clear(currentMatches)
		pcall(function() tb:ReleaseFocus(false) end)
		handleChatMessage(fill, true)
		return
	end
	tb.Text = fill
	tb.CursorPosition = #fill + 1
	pcall(function() tb:CaptureFocus() end)
end

local function resolveChatInputRefs()
	local ec = CoreGui:FindFirstChild("ExperienceChat")
	if ec then
		local app = ec:FindFirstChild("appLayout")
		local ir = app and app:FindFirstChild("chatInputRow")
		local fa = ir and ir:FindFirstChild("fillArea")
		local cb = fa and fa:FindFirstChild("chatInputBar")
		local anchor = (cb and cb.AbsoluteSize.X > 100 and cb)
			or (ir and ir.AbsoluteSize.X > 100 and ir)
			or cb
		local tb = cb and cb:FindFirstChild("TextBox", true)
		if tb and tb:IsA("TextBox") then
			return ec, anchor, tb
		end
	end

	local pg = lp:FindFirstChildOfClass("PlayerGui")
	local legacyChat = pg and pg:FindFirstChild("Chat")
	if legacyChat and legacyChat:IsA("ScreenGui") then
		local tb = legacyChat:FindFirstChild("ChatBar", true)
		if not (tb and tb:IsA("TextBox")) then
			local parentFrame = legacyChat:FindFirstChild("ChatBarParentFrame", true)
			tb = parentFrame and parentFrame:FindFirstChildWhichIsA("TextBox", true)
		end
		if tb and tb:IsA("TextBox") then
			local anchor = tb:FindFirstAncestor("ChatBarParentFrame")
				or tb:FindFirstAncestor("BoxFrame")
				or tb
			return legacyChat, anchor, tb
		end
	end

	return nil, nil, nil
end

local lastActiveChatTb = nil
local lastSemiText = ""
local boundTextBoxes = {}
local boundSendButtons = {}

local function bindChatSubmissionHooks(tb, chatGui)
	if tb and not boundTextBoxes[tb] then
		boundTextBoxes[tb] = true
		track(tb.FocusLost:Connect(function(enterPressed)
			if not state.running or not enterPressed then
				if not enterPressed then
					lastSemiText = ""
				end
				return
			end
			local raw = (tb.Text ~= "" and tb.Text) or lastSemiText
			lastSemiText = ""
			if type(raw) == "string" then
				local stripped = raw:gsub("^%s+", ""):gsub("^/e%s+", "")
				if stripped:sub(1, #PREFIX) == PREFIX then
					handleChatMessage(raw, true)
				end
			end
		end))
	end
	if chatGui then
		local sendBtn = chatGui:FindFirstChild("SendButton", true)
		if sendBtn and sendBtn:IsA("GuiButton") and not boundSendButtons[sendBtn] then
			boundSendButtons[sendBtn] = true
			track(sendBtn.Activated:Connect(function()
				if not state.running then return end
				local curTb = currentTextBox or lastActiveChatTb
				local raw = (curTb and curTb.Text ~= "" and curTb.Text) or lastSemiText
				lastSemiText = ""
				if type(raw) == "string" then
					local stripped = raw:gsub("^%s+", ""):gsub("^/e%s+", "")
					if stripped:sub(1, #PREFIX) == PREFIX then
						handleChatMessage(raw, true)
					end
				end
			end))
		end
	end
end

track(UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if not state.running or not acFrame.Visible or #currentMatches == 0 then
		return
	end
	if input.KeyCode == Enum.KeyCode.Down then
		selectedIdx = (selectedIdx % #currentMatches) + 1
	elseif input.KeyCode == Enum.KeyCode.Up then
		selectedIdx = ((selectedIdx - 2) % #currentMatches) + 1
	elseif input.KeyCode == Enum.KeyCode.Tab then
		local chosen = currentMatches[selectedIdx] or currentMatches[1]
		local targetTb = currentTextBox or UserInputService:GetFocusedTextBox() or lastActiveChatTb
		if chosen and targetTb then
			applyAutocomplete(targetTb, chosen, false)
		end
	end
end))

local lastFocusGraceUntil = 0
track(RunService.RenderStepped:Connect(function()
	if not state.running then return end

	if pendingClickItem then
		local targetTb = currentTextBox or UserInputService:GetFocusedTextBox() or lastActiveChatTb
		if targetTb then
			local chosen = pendingClickItem
			pendingClickItem = nil
			applyAutocomplete(targetTb, chosen, true)
			lastFocusGraceUntil = os.clock() + 0.2
		end
	end

	local now = os.clock()
	if not currentTextBox or not currentTextBox.Parent or (now - lastTextBoxCheck) > 0.5 then
		lastTextBoxCheck = now
		local chatGui, cb, tb = resolveChatInputRefs()
		if chatGui and acGui.IgnoreGuiInset ~= chatGui.IgnoreGuiInset then
			acGui.IgnoreGuiInset = chatGui.IgnoreGuiInset
		end
		currentChatBar = cb
		currentTextBox = tb
		if tb then
			bindChatSubmissionHooks(tb, chatGui)
		end
	end

	-- Fallback: also detect any focused TextBox (works in custom chat games too)
	local focusedTb = UserInputService:GetFocusedTextBox()
	local tb = currentTextBox or focusedTb
	if not tb or not tb.Parent then
		acFrame.Visible = false
		return
	end
	if focusedTb and focusedTb == tb and not currentTextBox then
		local customGui = tb:FindFirstAncestorWhichIsA("ScreenGui")
		if customGui and acGui.IgnoreGuiInset ~= customGui.IgnoreGuiInset then
			acGui.IgnoreGuiInset = customGui.IgnoreGuiInset
		end
		bindChatSubmissionHooks(tb, customGui)
	end

	local focused = tb:IsFocused()
	if focused then
		lastFocusGraceUntil = now + 0.14
	end
	local keepOpen = focused or hoverOrClicking or (now <= lastFocusGraceUntil)

	local txt = tb.Text or ""
	local stripped = txt:gsub("^%s+", ""):gsub("^/e%s+", "")
	local isSemi = stripped:sub(1, #PREFIX) == PREFIX
	if isSemi and tb:IsA("TextBox") then
		lastActiveChatTb = tb
		lastSemiText = txt
	elseif txt == "" and not focused and not hoverOrClicking then
		-- Keep lastSemiText briefly only for FocusLost(enterPressed=true); FocusLost clears it right after
	end

	if not keepOpen or not isSemi then
		acFrame.Visible = false
		table.clear(currentMatches)
		return
	end

	local body = stripped:sub(#PREFIX + 1)
	local firstWord, tpQuery = body:match("^(%a+)%s+(.*)$")
	local exactLower = string.lower(body)
	local firstLower = firstWord and string.lower(firstWord) or ""
	local isTpExact = (exactLower == "tp" or exactLower == "to" or exactLower == "goto")
	local isTpWithArg = (firstLower == "tp" or firstLower == "to" or firstLower == "goto")
	local matches = {}

	if isTpExact or isTpWithArg then
		local cmdUsed = isTpWithArg and firstLower or exactLower
		local cleanQ = isTpWithArg and string.lower((tpQuery or ""):gsub("[{}@\"']", "")) or ""
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp then
				local nLower = string.lower(p.Name)
				local dLower = string.lower(p.DisplayName)
				if cleanQ == "" or nLower:find(cleanQ, 1, true) or dLower:find(cleanQ, 1, true) then
					table.insert(matches, {
						display = PREFIX .. cmdUsed .. " " .. p.Name,
						hint = (p.DisplayName ~= p.Name) and p.DisplayName or "Teleport",
						fillText = PREFIX .. cmdUsed .. " " .. p.Name,
						executeOnClick = true,
					})
					if #matches >= MAX_AC_ROWS then break end
				end
			end
		end
	elseif not body:find("%s") then
		local qLower = string.lower(body)
		for _, entry in ipairs(commandEntries) do
			local matchesAlias = (entry.name == "fly" and qLower:sub(1, 3) == "fla")
				or (entry.name == "unfly" and qLower:sub(1, 5) == "unfla")
			if qLower == "" or entry.name:sub(1, #qLower) == qLower or matchesAlias then
				table.insert(matches, {
					display = PREFIX .. entry.name,
					hint = entry.hint,
					fillText = PREFIX .. entry.name .. (entry.takesArg and " " or ""),
					executeOnClick = (not entry.takesArg or entry.name == "fly"),
				})
				if #matches >= MAX_AC_ROWS then break end
			end
		end
	end

	if #matches == 0 then
		acFrame.Visible = false
		table.clear(currentMatches)
		return
	end

	currentMatches = matches
	if selectedIdx > #matches then selectedIdx = 1 end
	if selectedIdx < 1 then selectedIdx = 1 end

	for idx = 1, MAX_AC_ROWS do
		local slot = rowSlots[idx]
		local item = matches[idx]
		if item then
			slot.btn.Visible = true
			slot.cmdLbl.Text = item.display
			slot.hintLbl.Text = item.hint
			local isSel = (idx == selectedIdx)
			slot.btn.BackgroundColor3 = isSel and Color3.fromRGB(64, 67, 74) or Color3.fromRGB(28, 30, 34)
			slot.divider.Visible = (idx < #matches)
		else
			slot.btn.Visible = false
		end
	end

	local totalH = #matches * ROW_HEIGHT
	local anchorObj = (currentChatBar and currentChatBar.AbsoluteSize.X > 100) and currentChatBar or tb
	local wPx = math.clamp(math.round(anchorObj.AbsoluteSize.X * 0.9), 390, 480)
	local offsetX = (anchorObj.Name == "chatInputRow") and 48 or 0
	local xPx = math.max(4, math.round(anchorObj.AbsolutePosition.X - acGui.AbsolutePosition.X + offsetX))
	local aboveY = math.round(anchorObj.AbsolutePosition.Y - acGui.AbsolutePosition.Y - totalH - 6)
	local yPx = (aboveY >= 4) and aboveY or math.round(anchorObj.AbsolutePosition.Y - acGui.AbsolutePosition.Y + anchorObj.AbsoluteSize.Y + 6)

	acFrame.Size = UDim2.fromOffset(wPx, totalH)
	acFrame.Position = UDim2.fromOffset(xPx, yPx)
	acFrame.Visible = true
end))

-- 1. Register TextChatCommand objects (modern TextChatService games)
local function registerTextChatCommands()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then return end
	for name, _ in pairs(commands) do
		local ok, cmdObj = pcall(function()
			local cmd = Instance.new("TextChatCommand")
			cmd.Name = "_ChatFlyCmd_" .. name
			cmd.PrimaryAlias = PREFIX .. name
			cmd.Enabled = true
			cmd.Parent = TextChatService
			return cmd
		end)
		if ok and cmdObj then
			table.insert(createdCommands, cmdObj)
			track(cmdObj.Triggered:Connect(function(_, unfilteredText)
				handleChatMessage(unfilteredText, true)
			end))
		end
	end
end
registerTextChatCommands()

-- 2. TextChatService.SendingMessage listener (captures commands with args cleanly before send)
local okSending, sendingSig = pcall(function()
	return TextChatService.SendingMessage
end)
if okSending and typeof(sendingSig) == "RBXScriptSignal" then
	track(sendingSig:Connect(function(textChatMsg)
		if textChatMsg and type(textChatMsg.Text) == "string" then
			handleChatMessage(textChatMsg.Text, true)
		end
	end))
end

-- 3. Universal Legacy Chat & Custom Chat fallback (skips TextChatService echo double-fires)
track(lp.Chatted:Connect(function(msg)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		return
	end
	if type(msg) == "string" then
		local stripped = (msg:match("^%s*(.-)%s*$") or ""):gsub("^/e%s+", "")
		local sentAt = lastSentViaTcs[stripped]
		if sentAt and (os.clock() - sentAt) < 3.0 then
			return
		end
	end
	handleChatMessage(msg, false)
end))

track(lp.CharacterRemoving:Connect(function()
	stopFly(true)
end))

track(Players.PlayerRemoving:Connect(function(p)
	local entry = espEntries[p]
	if entry then
		destroyEspEntry(entry)
		espEntries[p] = nil
	end
end))

track(lp.Idled:Connect(function()
	if not state.running then return end
	pcall(function()
		local vu = game:GetService("VirtualUser")
		vu:CaptureController()
		vu:ClickButton2(Vector2.zero)
	end)
end))

env._ChatFlyCleanup = unload
env._ChatFlyHandle = handleChatMessage
env._ChatFlyState = state
env._ChatFlyAcFrame = acFrame
env._ChatFlyEsp = espEntries
env._ChatFlyClickRow = function(idx)
	pendingClickItem = currentMatches[idx or 1]
end

local welcomeMsg = "Yuklandi! Chatda ; yozing - ro'yxat chiqadi (;fly, ;unfly, ;flyspeed, ;tp, ;esp, ;wse, ;fps, ;cmds)."
if not notifyChat(welcomeMsg) then
	task.spawn(function()
		for _ = 1, 24 do
			task.wait(0.25)
			if not state.running then return end
			if sendSystemChatText(welcomeMsg) then
				break
			end
		end
	end)
end
