--============================================
-- RetrBloxSource v1.1.0
--============================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
Player.CameraMode = Enum.CameraMode.LockFirstPerson

--==================================================
-- Player State
--==================================================

local Character = nil
local Humanoid = nil
local HRP = nil
local MoveBV = nil

local CharacterConnections = {}
local CurrentPose = "Stand"
local TargetCameraOffset = Vector3.new(0, 0, 0)
local CurrentMaxSpeedStuds = 0

-- 1 = autohop
-- 2 = wheel hop
-- 3 = no autohop
local JumpMode = 1
local JumpBuffer = 0
local JumpPressWindow = 0
local ScrollDebounce = false
local SpaceHeld = false

local TimeAccumulator = 0
local IsGroundedGlobal = false
local JumpLockFrames = 0
local GroundFrames = 0
local LastGrounded = false

local CameraImpactRoll = 0
local CameraImpactRollVelocity = 0
local LastAppliedCameraRoll = 0
local PeakFallVelocity = 0
local LandingCooldown = 0
local AirTime = 0

local InternalVelocity = Vector3.new(0, 0, 0)

--==================================================
-- Input and Camera Settings
--==================================================

UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
UIS.MouseIconEnabled = false

--==================================================
-- Utility Functions
--==================================================

local function Clamp(value, minValue, maxValue)
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

local function SafeUnit(v)
	local m = v.Magnitude
	if m > 0.000001 then return v / m end
	return Vector3.new(0, 0, 0)
end

local function FlatVector(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function GetCameraLookRight(cam)
	if not cam then
		return Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
	end
	local camCF = cam.CoordinateFrame
	local look = camCF:vectorToWorldSpace(Vector3.new(0, 0, -1))
	local right = camCF:vectorToWorldSpace(Vector3.new(1, 0, 0))
	return look, right
end

local function GetAllChildrenRecursive(object, list)
	list = list or {}
	local children = object:GetChildren()
	for i = 1, #children do
		local child = children[i]
		list[#list + 1] = child
		GetAllChildrenRecursive(child, list)
	end
	return list
end

--========================================
-- Converters
--========================================

local INCHES_PER_UNIT = 0.75
local STUDS_PER_INCH = 1 / 11.0236

local function ToStuds(units)
	return units * INCHES_PER_UNIT * STUDS_PER_INCH
end

local function ToUnits(studs)
	return studs / (INCHES_PER_UNIT * STUDS_PER_INCH)
end

--==================================================
-- Configuration
--==================================================

local sv = {
	gravity = 800,
	maxspeed = 250,
	airwishspeed = 50,
	airspeedcap = 50,
	accelerate = 10,
	airaccelerate = 25,
	friction = 4,
	surfacefriction = 1,
	stopspeed = 100,
	jumpvelocity = 268,
	maxvelocity = 3200,
	aircontrol = false,
	aircontrolfactor = 0.25,
}

local cl = {
	keycrouch = Enum.KeyCode.C,
	keyprone = Enum.KeyCode.V,
	standspeedscale = 1,
	crouchspeedscale = 0.33,
	pronespeedscale = 0.15,
	poselerpspeed = 15,
	scrolljumpbuffertime = 0.07,
	scrolldebouncetime = 0.05,
	stand = Vector3.new(0, 0, 0),
	crouch = Vector3.new(0, -1.5, 0),
	prone = Vector3.new(0, -3, 0),
	tickrate = 66.6666667,
}

local physics = {
	maxstepheight = 0.45,
	groundcheckdistance = 0.8,
	groundnormalmin = 0.7,
	groundsnapminnormaly = 0.7,
	footrayside = 0.85,
	groundsnapepsilon = 0.06,
	frictiondelayframes = 1,
	hullhalfwidth = 0.75,
}

local viewPunch = {
	enabled = true,
	threshold = 12,
	mindelta = 1.5,
	strength = 0.06,
	spring = 85,
	damping = 14,
	maxroll = 0.18,
	maxvelocity = 5,
}

local MaterialFriction = {
	[Enum.Material.Ice] = 0.2,
	[Enum.Material.Glacier] = 0.25,
	[Enum.Material.Mud] = 1.5,
	[Enum.Material.Concrete] = 1,
	[Enum.Material.Grass] = 0.9,
	[Enum.Material.Sand] = 1.15,
	[Enum.Material.Wood] = 0.95
}

local SourceGravityStuds = ToStuds(sv.gravity)
local JumpVelocityStuds = ToStuds(sv.jumpvelocity)
local MaxVelocityStuds = ToStuds(sv.maxvelocity)
local MaxWalkSpeedStuds = ToStuds(sv.maxspeed)
local AirWishSpeedStuds = ToStuds(sv.airwishspeed)
local AirSpeedCapStuds = ToStuds(sv.airspeedcap)
local StopSpeedStuds = ToStuds(sv.stopspeed)

Workspace.Gravity = SourceGravityStuds

local function IsWalkableNormal(normal)
	return normal and normal.Y >= physics.groundnormalmin
end

local function IsSnapSurface(normal)
	return normal and normal.Y >= physics.groundsnapminnormaly
end

local function TriggerLandingImpact(fallVelocityStuds, impactNormal, fallbackVelocity)
	if not viewPunch.enabled then return end
	if LandingCooldown > 0 then return end

	local impact = fallVelocityStuds - viewPunch.threshold
	if impact < viewPunch.mindelta then return end

	local kick = math.min(impact * viewPunch.strength, viewPunch.maxvelocity)

	local side = 1
	if Camera then
		local camRight = Camera.CFrame:vectorToWorldSpace(Vector3.new(1, 0, 0))
		local lateral = nil

		if impactNormal then
			lateral = Vector3.new(impactNormal.X, 0, impactNormal.Z)
		end

		if lateral and lateral.Magnitude > 0.001 then
			side = (camRight:Dot(lateral) >= 0) and -1 or 1
		elseif fallbackVelocity and fallbackVelocity.Magnitude > 0.001 then
			local flatVel = FlatVector(fallbackVelocity)
			side = (camRight:Dot(flatVel) >= 0) and -1 or 1
		elseif HRP then
			local flatVel = FlatVector(HRP.Velocity)
			if flatVel.Magnitude > 0.001 then
				side = (camRight:Dot(flatVel) >= 0) and -1 or 1
			end
		end
	end

	CameraImpactRollVelocity = CameraImpactRollVelocity + (kick * side)
	LandingCooldown = 0.12
end

local function UpdateCameraImpact(dt)
	if not viewPunch.enabled then return end

	local accel = (-CameraImpactRoll * viewPunch.spring) - (CameraImpactRollVelocity * viewPunch.damping)
	CameraImpactRollVelocity = CameraImpactRollVelocity + (accel * dt)

	CameraImpactRollVelocity = Clamp(CameraImpactRollVelocity, -viewPunch.maxvelocity, viewPunch.maxvelocity)
	CameraImpactRoll = CameraImpactRoll + (CameraImpactRollVelocity * dt)
	CameraImpactRoll = Clamp(CameraImpactRoll, -viewPunch.maxroll, viewPunch.maxroll)
end

--==================================================
-- Character Connections
--==================================================

local function DisconnectConnections()
	for i = 1, #CharacterConnections do
		if CharacterConnections[i] then
			pcall(function()
				CharacterConnections[i]:Disconnect()
			end)
		end
	end
	CharacterConnections = {}
end

local function BindConnection(conn)
	CharacterConnections[#CharacterConnections + 1] = conn
	return conn
end

--==================================================
-- Movement Logic
--==================================================

local StopEpsilon = 0.001
local OverBounce = 1.001

local function ClipVelocity(velocity, normal, overbounce)
	overbounce = overbounce or OverBounce

	local backoff = velocity:Dot(normal)
	if backoff < 0 then
		backoff = backoff * overbounce
	else
		backoff = backoff / overbounce
	end

	local out = velocity - (normal * backoff)

	if math.abs(out.X) < StopEpsilon then out = Vector3.new(0, out.Y, out.Z) end
	if math.abs(out.Y) < StopEpsilon then out = Vector3.new(out.X, 0, out.Z) end
	if math.abs(out.Z) < StopEpsilon then out = Vector3.new(out.X, out.Y, 0) end

	return out
end

local function ClampMomentum(v)
	if v.Magnitude > MaxVelocityStuds then
		return v.Unit * MaxVelocityStuds
	end
	return v
end

local function BuildIgnoreList()
	local list = {}
	if Character then list[#list + 1] = Character end
	return list
end

local function GetMoveAxes()
	local x, z = 0, 0
	if UIS:IsKeyDown(Enum.KeyCode.W) then z = z + 1 end
	if UIS:IsKeyDown(Enum.KeyCode.S) then z = z - 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) then x = x + 1 end
	if UIS:IsKeyDown(Enum.KeyCode.A) then x = x - 1 end
	return x, z
end

local function GetWishDirAndSpeed(cam, moveX, moveZ, maxSpeed)
	if not cam then
		return Vector3.new(0, 0, 0), 0
	end

	local look, right = GetCameraLookRight(cam)

	look = SafeUnit(FlatVector(look))
	right = SafeUnit(FlatVector(right))

	local wishVel = look * moveZ + right * moveX

	local wishDir = SafeUnit(wishVel)
	local wishSpeed = wishVel.Magnitude * maxSpeed

	if wishSpeed > MaxWalkSpeedStuds then
		wishSpeed = MaxWalkSpeedStuds
	end

	return wishDir, wishSpeed
end

local function ApplyFriction(vel, dt, friction, stopSpeed, surfaceFriction)
	local speed = vel.Magnitude
	if speed < 0.1 then return Vector3.new(0, 0, 0) end
	local control = math.max(speed, stopSpeed)
	local drop = control * friction * surfaceFriction * dt
	local newSpeed = math.max(speed - drop, 0)
	return vel * (newSpeed / speed)
end

local function Accelerate(vel, wishDir, wishSpeed, accel, dt, surfaceFriction)
	local currentSpeed = vel:Dot(wishDir)
	local addSpeed = wishSpeed - currentSpeed
	if addSpeed <= 0 then return vel end
	local accelSpeed = math.min(accel * dt * wishSpeed * surfaceFriction, addSpeed)
	return vel + (wishDir * accelSpeed)
end

local function AirAccelerate(vel, wishDir, wishSpeed, accel, dt)
	local targetSpeed = math.min(wishSpeed, AirSpeedCapStuds)

	local currentSpeed = vel:Dot(wishDir)
	local addSpeed = targetSpeed - currentSpeed

	if addSpeed <= 0 then
		return vel
	end

	local accelSpeed = accel * wishSpeed * dt * sv.surfacefriction

	if accelSpeed > addSpeed then
		accelSpeed = addSpeed
	end

	return vel + wishDir * accelSpeed
end

local function AirControl(vel, wishDir, wishSpeed, dt)
	if not sv.aircontrol then return vel end

	local zSpeed = vel.Y

	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local flatWish = Vector3.new(wishDir.X, 0, wishDir.Z)

	local speed = flatVel.Magnitude

	if speed < 0.001 or flatWish.Magnitude < 0.001 then
		return vel
	end

	flatVel = flatVel.Unit
	flatWish = flatWish.Unit

	local dot = flatVel:Dot(flatWish)

	if dot <= 0 then
		return vel
	end

	local k = 32 * sv.aircontrolfactor * dot * dot * dt

	local newVel = flatVel + (flatWish * k)
	newVel = SafeUnit(newVel) * speed

	return Vector3.new(newVel.X, zSpeed, newVel.Z)
end

local function RaycastIgnoreList(origin, direction, ignoreList)
	local currentIgnore = { unpack(ignoreList) }
	while true do
		local hitPart, hitPos, hitNormal = Workspace:FindPartOnRayWithIgnoreList(
			Ray.new(origin, direction), currentIgnore, false, false
		)
		if not hitPart then
			return nil
		end
		if hitPart.CanCollide then
			return hitPart, hitPos, hitNormal
		end
		table.insert(currentIgnore, hitPart)
	end
end

--==================================================
-- Collision and Hull Tracing
--==================================================

local function TraceHull(startPos, endPos, halfWidth, halfHeight, ignoreList)
	local dir = endPos - startPos
	local dist = dir.Magnitude
	if dist < 0.0001 then
		return { Fraction = 1, EndPos = startPos }
	end

	local uDir = dir.Unit
	local steps = math.ceil(dist / 0.15)

	for i = 1, steps do
		local testDist = math.min(i * (dist / steps), dist)
		local testPos = startPos + uDir * testDist

		local offsets = {
			Vector3.new(halfWidth, 0, halfWidth), Vector3.new(-halfWidth, 0, halfWidth),
			Vector3.new(halfWidth, 0, -halfWidth), Vector3.new(-halfWidth, 0, -halfWidth),
			Vector3.new(halfWidth, halfHeight, halfWidth), Vector3.new(-halfWidth, halfHeight, halfWidth),
			Vector3.new(halfWidth, halfHeight, -halfWidth), Vector3.new(-halfWidth, halfHeight, -halfWidth)
		}

		if dir.Y < -0.0001 then
			offsets[#offsets + 1] = Vector3.new(halfWidth, -halfHeight, halfWidth)
			offsets[#offsets + 1] = Vector3.new(-halfWidth, -halfHeight, halfWidth)
			offsets[#offsets + 1] = Vector3.new(halfWidth, -halfHeight, -halfWidth)
			offsets[#offsets + 1] = Vector3.new(-halfWidth, -halfHeight, -halfWidth)
		end

		for o = 1, #offsets do
			local hitPart, hitPos, hitNormal = RaycastIgnoreList(testPos, offsets[o], ignoreList)
			if hitPart then
				local collisionFraction = math.max((testDist / dist) - 0.02, 0)
				return {
					Fraction = collisionFraction,
					EndPos = startPos + uDir * (dist * collisionFraction),
					PlaneNormal = hitNormal
				}
			end
		end
	end

	return { Fraction = 1, EndPos = endPos }
end

local function TryPlayerMove(startPos, velocity, dt, halfWidth, halfHeight, ignoreList)
	local timeLeft = dt
	local currentPos = startPos
	local currentVel = velocity
	local numBounces = 4

	for bounce = 1, numBounces do
		if timeLeft <= 0 or currentVel.Magnitude < 0.001 then
			break
		end

		local distance = currentVel.Magnitude * timeLeft
		local steps = math.ceil(distance / 1)

		if steps < 1 then
			steps = 1
		end

		local stepDt = timeLeft / steps

		for i = 1, steps do
			local endPos = currentPos + currentVel * stepDt
			local trace = TraceHull(currentPos, endPos, halfWidth, halfHeight, ignoreList)

			currentPos = trace.EndPos

			if trace.Fraction < 1 and trace.PlaneNormal then
				currentPos = currentPos + trace.PlaneNormal * 0.01
				currentVel = ClipVelocity(currentVel, trace.PlaneNormal, OverBounce)
			end
		end

		timeLeft = 0
	end

	return currentPos, currentVel
end

local function TryStepMove(startPos, velocity, dt, halfWidth, halfHeight, ignoreList)
	local noStepPos, noStepVel = TryPlayerMove(startPos, velocity, dt, halfWidth, halfHeight, ignoreList)

	local stepUpPos = startPos + Vector3.new(0, physics.maxstepheight, 0)
	local stepUpTrace = TraceHull(startPos, stepUpPos, halfWidth, halfHeight, ignoreList)
	if stepUpTrace.Fraction < 1 then
		return noStepPos, noStepVel
	end

	local steppedStart = stepUpTrace.EndPos
	local stepMovePos, stepMoveVel = TryPlayerMove(steppedStart, velocity, dt, halfWidth, halfHeight, ignoreList)

	local stepDownPos = stepMovePos - Vector3.new(0, physics.maxstepheight + physics.groundsnapepsilon, 0)
	local stepDownTrace = TraceHull(stepMovePos, stepDownPos, halfWidth, halfHeight, ignoreList)

	local steppedEnd = stepMovePos
	if stepDownTrace.Fraction < 1 and stepDownTrace.PlaneNormal and IsWalkableNormal(stepDownTrace.PlaneNormal) then
		steppedEnd = stepDownTrace.EndPos
	elseif stepDownTrace.Fraction < 1 then
		return noStepPos, noStepVel
	end

	local noStepDist = Vector3.new(noStepPos.X - startPos.X, 0, noStepPos.Z - startPos.Z).Magnitude
	local stepDist = Vector3.new(steppedEnd.X - startPos.X, 0, steppedEnd.Z - startPos.Z).Magnitude

	if stepDist > noStepDist then
		return steppedEnd, stepMoveVel
	end

	return noStepPos, noStepVel
end

--==================================================
-- Player Stance / Pose System
--==================================================

local function GetHullHalfHeight()
	if CurrentPose == "Crouch" then
		return 1.5
	elseif CurrentPose == "Prone" then
		return 0.75
	else
		return 2.5
	end
end

local function ApplyPose(pose)
	if not HRP then return end

	if pose == "Stand" and CurrentPose ~= "Stand" then
		local ignore = BuildIgnoreList()
		local origin = HRP.Position + Vector3.new(0, GetHullHalfHeight(), 0)

		if RaycastIgnoreList(origin, Vector3.new(0, 3, 0), ignore) then
			return
		end
	end

	local oldHeight = GetHullHalfHeight()
	CurrentPose = pose
	local newHeight = GetHullHalfHeight()

	local heightDifference = oldHeight - newHeight

	if pose == "Crouch" then
		TargetCameraOffset = cl.crouch
		CurrentMaxSpeedStuds = MaxWalkSpeedStuds * cl.crouchspeedscale
	elseif pose == "Prone" then
		TargetCameraOffset = cl.prone
		CurrentMaxSpeedStuds = MaxWalkSpeedStuds * cl.pronespeedscale
	else
		TargetCameraOffset = cl.stand
		CurrentMaxSpeedStuds = MaxWalkSpeedStuds * cl.standspeedscale
	end

	if heightDifference ~= 0 then
		HRP.CFrame = HRP.CFrame * CFrame.new(0, -heightDifference, 0)
	end
end

--==================================================
-- Character Initialization
--==================================================

local function HandleDescendantCollision(obj)
	if obj:IsA("BasePart") and obj ~= HRP then
		obj.CanCollide = false
	end
end

local function SetupCharacterColliders(char)
	local all = GetAllChildrenRecursive(char)
	for i = 1, #all do
		HandleDescendantCollision(all[i])
	end

	BindConnection(char.ChildAdded:Connect(function(child)
		HandleDescendantCollision(child)
		local nested = GetAllChildrenRecursive(child)
		for i = 1, #nested do
			HandleDescendantCollision(nested[i])
		end
	end))
end

local function BindCharacter(char)
	DisconnectConnections()

	Character = char
	Humanoid = char:WaitForChild("Humanoid")
	HRP = char:WaitForChild("HumanoidRootPart")
	Camera = Workspace.CurrentCamera

	for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
		if state ~= Enum.HumanoidStateType.None then
			pcall(function()
				Humanoid:SetStateEnabled(state, false)
			end)
		end
	end
	Humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)

	Humanoid.AutoRotate = false
	Humanoid.WalkSpeed = 0
	Humanoid.JumpPower = 0
	if Camera then Camera.CameraSubject = Humanoid end

	SpaceHeld, JumpBuffer, JumpPressWindow, TimeAccumulator, IsGroundedGlobal, JumpLockFrames, GroundFrames, LastGrounded = false, 0, 0, 0, false, 0, 0, false
	CameraImpactRoll = 0
	CameraImpactRollVelocity = 0
	LastAppliedCameraRoll = 0
	PeakFallVelocity = 0
	LandingCooldown = 0
	InternalVelocity = Vector3.new(0, 0, 0)

	if MoveBV then
		MoveBV:Destroy()
		MoveBV = nil
	end

	MoveBV = Instance.new("BodyVelocity")
	MoveBV.Name = "PhysicsMovement"
	MoveBV.MaxForce = Vector3.new(10000000, 0, 10000000)
	MoveBV.P = 125000
	MoveBV.Velocity = Vector3.new(0, 0, 0)
	MoveBV.Parent = HRP

	HRP.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 1, 1)
	HRP.CanCollide = false

	SetupCharacterColliders(char)
	ApplyPose("Stand")
end

Player.CharacterAdded:Connect(BindCharacter)
if Player.Character then BindCharacter(Player.Character) end

--==================================================
-- Ground Detection and Snap Movement
--==================================================

local function GetGroundInfo()
	if not HRP or not Character then
		return false, nil, sv.surfacefriction
	end

	local ignore = BuildIgnoreList()
	local rootPos = HRP.Position
	local feetY = rootPos.Y - GetHullHalfHeight()

	local startY = feetY + 1.0
	local rayDist = physics.groundcheckdistance + 1.15

	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(physics.footrayside, 0, 0),
		Vector3.new(-physics.footrayside, 0, 0),
		Vector3.new(0, 0, physics.footrayside),
		Vector3.new(0, 0, -physics.footrayside)
	}

	local bestHitY = nil
	local bestNormal = nil
	local bestFriction = sv.surfacefriction

	for i = 1, #offsets do
		local origin = Vector3.new(rootPos.X + offsets[i].X, startY, rootPos.Z + offsets[i].Z)
		local hitPart, hitPos, hitNormal = RaycastIgnoreList(origin, Vector3.new(0, -rayDist, 0), ignore)
		if hitPart and hitNormal and IsWalkableNormal(hitNormal) then
			if not bestHitY or hitPos.Y > bestHitY then
				bestHitY = hitPos.Y
				bestNormal = hitNormal
				bestFriction = MaterialFriction[hitPart.Material] or sv.surfacefriction
			end
		end
	end

	if bestHitY then
		return true, bestNormal, bestFriction
	end

	return false, nil, sv.surfacefriction
end

local function GroundSnap()
	if not HRP or not Character then return false end

	local ignore = BuildIgnoreList()
	local rootPos = HRP.Position
	local feetY = rootPos.Y - GetHullHalfHeight()

	local startY = feetY + 1.0
	local rayDist = physics.maxstepheight + 1.15

	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(physics.footrayside, 0, 0),
		Vector3.new(-physics.footrayside, 0, 0),
		Vector3.new(0, 0, physics.footrayside),
		Vector3.new(0, 0, -physics.footrayside)
	}

	local bestHitY = nil
	local bestNormal = nil

	for i = 1, #offsets do
		local origin = Vector3.new(rootPos.X + offsets[i].X, startY, rootPos.Z + offsets[i].Z)
		local hitPart, hitPos, hitNormal = RaycastIgnoreList(origin, Vector3.new(0, -rayDist, 0), ignore)
		if hitPart and hitNormal and IsSnapSurface(hitNormal) then
			if not bestHitY or hitPos.Y > bestHitY then
				bestHitY = hitPos.Y
				bestNormal = hitNormal
			end
		end
	end

	if not bestHitY or not bestNormal then
		return false
	end

	local heightDiff = bestHitY - feetY
	if heightDiff >= 0 and heightDiff <= physics.groundsnapepsilon and bestNormal.Y >= 0.98 then
		HRP.CFrame = CFrame.new(rootPos + Vector3.new(0, heightDiff, 0)) * (HRP.CFrame - HRP.Position)
		return true
	end

	return false
end

--==================================================
-- Keyboard and Mouse Input
--==================================================

BindConnection(UIS.InputBegan:Connect(function(input, gp)
	if gp then return end

	if input.KeyCode == cl.keycrouch then
		ApplyPose(CurrentPose == "Crouch" and "Stand" or "Crouch")
	elseif input.KeyCode == cl.keyprone then
		ApplyPose(CurrentPose == "Prone" and "Stand" or "Prone")
	elseif input.KeyCode == Enum.KeyCode.Space then
		SpaceHeld = true
		if JumpMode == 3 then
			JumpPressWindow = 2
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		JumpMode = 1
	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		JumpMode = 2
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		JumpMode = 3
	end
end))

BindConnection(UIS.InputEnded:Connect(function(input, gp)
	if not gp and input.KeyCode == Enum.KeyCode.Space then
		SpaceHeld = false
	end
end))

BindConnection(UIS.InputChanged:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel and JumpMode == 2 and not ScrollDebounce then
		ScrollDebounce = true
		JumpBuffer = cl.scrolljumpbuffertime
		delay(cl.scrolldebouncetime, function()
			ScrollDebounce = false
		end)
	end
end))

--========================================
-- Player Movement Update
--========================================

BindConnection(RunService.Stepped:Connect(function(_, rawDt)
	if not HRP or not MoveBV or not Humanoid or Humanoid.Health <= 0 then
		return
	end

	local fixedDt = 1 / cl.tickrate
	TimeAccumulator = TimeAccumulator + math.min(rawDt, 0.1)

	while TimeAccumulator >= fixedDt do
		TimeAccumulator = TimeAccumulator - fixedDt
		JumpBuffer = math.max(JumpBuffer - fixedDt, 0)
		JumpPressWindow = math.max(JumpPressWindow - 1, 0)

		if LandingCooldown > 0 then
			LandingCooldown = math.max(LandingCooldown - fixedDt, 0)
		end

		local jumpTriggeredThisTick = false

		local x, z = GetMoveAxes()
		local wishDir, wishSpeed = Vector3.new(0, 0, 0), 0
		if x ~= 0 or z ~= 0 then
			wishDir, wishSpeed = GetWishDirAndSpeed(Workspace.CurrentCamera or Camera, x, z, CurrentMaxSpeedStuds)
		end

		local actualVelocity = HRP.Velocity
		local vel = Vector3.new(actualVelocity.X, actualVelocity.Y, actualVelocity.Z)
		local hVel = FlatVector(vel)

		local wasGrounded = IsGroundedGlobal

		local grounded, groundNormal, surfaceFriction = GetGroundInfo()
		IsGroundedGlobal = grounded

		if not IsGroundedGlobal then
			AirTime = AirTime + fixedDt

			local fallSpeed = -vel.Y
			if fallSpeed > 0 then
				PeakFallVelocity = math.max(PeakFallVelocity, fallSpeed)
			end
		end

		GroundFrames = grounded and (LastGrounded and GroundFrames + 1 or 1) or 0
		LastGrounded = grounded

		local canJump = (JumpMode == 1 and SpaceHeld) or (JumpMode == 2 and JumpBuffer > 0) or (JumpMode == 3 and JumpPressWindow > 0)

		if grounded then
			if canJump then
				local landingSpeed = PeakFallVelocity

				vel = Vector3.new(vel.X, JumpVelocityStuds, vel.Z)
				hVel = FlatVector(vel)
				HRP.Velocity = vel
				JumpBuffer = 0
				JumpPressWindow = 0

				if landingSpeed > 0 then
					TriggerLandingImpact(landingSpeed, groundNormal, actualVelocity)
				end

				PeakFallVelocity = 0
				IsGroundedGlobal = false
				JumpLockFrames = 2
				jumpTriggeredThisTick = true
			elseif JumpLockFrames <= 0 then
				if GroundFrames >= (physics.frictiondelayframes + 1) then
					hVel = ApplyFriction(hVel, fixedDt, sv.friction, StopSpeedStuds, surfaceFriction)
				end
				if wishDir.Magnitude > 0 then
					hVel = Accelerate(hVel, wishDir, wishSpeed, sv.accelerate, fixedDt, surfaceFriction)
				end
				hVel = ClampMomentum(hVel)

				if groundNormal and IsSnapSurface(groundNormal) then
					GroundSnap()
				end
			end
		else
			if wishDir.Magnitude > 0 then
				hVel = AirAccelerate(hVel, wishDir, wishSpeed, sv.airaccelerate, fixedDt)
				hVel = AirControl(hVel, wishDir, wishSpeed, fixedDt)
			end

			if JumpMode == 3 then
				JumpPressWindow = 0
			end
		end

		hVel = ClampMomentum(hVel)

		local ignoreList = BuildIgnoreList()
		local currentPos = HRP.Position
		local nextPos, nextVel = TryStepMove(currentPos, hVel, fixedDt, physics.hullhalfwidth, GetHullHalfHeight(), ignoreList)

		HRP.CFrame = (HRP.CFrame - HRP.Position) + nextPos

		InternalVelocity = Vector3.new(nextVel.X, vel.Y, nextVel.Z)
		hVel = FlatVector(InternalVelocity)

		local snappedToGround = false
		if JumpLockFrames <= 0 then
			snappedToGround = GroundSnap()
		end

		local groundedAfter, groundNormalAfter = GetGroundInfo()
		IsGroundedGlobal = groundedAfter or snappedToGround

		MoveBV.MaxForce = Vector3.new(10000000, 0, 10000000)
		if IsGroundedGlobal and JumpLockFrames <= 0 then
			MoveBV.Velocity = hVel
		else
			MoveBV.Velocity = Vector3.new(hVel.X, vel.Y, hVel.Z)
		end

		if JumpLockFrames > 0 then
			JumpLockFrames = JumpLockFrames - 1
		end

		if not wasGrounded and IsGroundedGlobal then
			local landingSpeed = PeakFallVelocity

			if AirTime >= 0.25 then
				if vel.Y < 0 then
					landingSpeed = math.max(landingSpeed, -vel.Y)
				end

				TriggerLandingImpact(landingSpeed, groundNormalAfter or groundNormal, vel)
			end

			PeakFallVelocity = 0
			AirTime = 0

		elseif IsGroundedGlobal and not jumpTriggeredThisTick and PeakFallVelocity < 1 then
			PeakFallVelocity = 0
			AirTime = 0
		end
	end
end))

--==================================================
-- Camera Update and Character Rotation
--==================================================

BindConnection(RunService.RenderStepped:Connect(function(dt)
	if Camera then
		if math.abs(LastAppliedCameraRoll) > 0.000001 then
			Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, -LastAppliedCameraRoll)
			LastAppliedCameraRoll = 0
		end

		UpdateCameraImpact(dt)

		if math.abs(CameraImpactRoll) > 0.000001 then
			Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, CameraImpactRoll)
			LastAppliedCameraRoll = CameraImpactRoll
		end
	end

	if Humanoid then
		Humanoid.CameraOffset = Humanoid.CameraOffset:Lerp(TargetCameraOffset, Clamp(cl.poselerpspeed * dt, 0, 1))
	end

	if HRP and Camera then
		local look = Camera.CoordinateFrame:vectorToWorldSpace(Vector3.new(0, 0, -1))
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.001 then
			HRP.CFrame = CFrame.new(HRP.Position, HRP.Position + flat)
		end
	end
end))
