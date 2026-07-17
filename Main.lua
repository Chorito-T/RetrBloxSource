local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--========================================
-- STATE
--========================================

local Character = nil
local Humanoid = nil
local HRP = nil
local MoveBV = nil

local CharacterConnections = {}
local CurrentPose = "Stand"
local TargetCameraOffset = Vector3.new(0, 0, 0)
local CurrentMaxSpeedStuds = 0

local JumpMode = 1
local JumpBuffer = 0
local ScrollDebounce = false
local SpaceHeld = false

local TimeAccumulator = 0
local IsGroundedGlobal = false
local JumpLockFrames = 0
local GroundFrames = 0
local LastGrounded = false

--========================================
-- INPUT / CAMERA
--========================================

UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
UIS.MouseIconEnabled = false

--========================================
-- HELPERS
--========================================

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

local function GetPartShapeName(part)
	if not part or not part:IsA("BasePart") then
		return "Unknown"
	end

	local ok, shape = pcall(function()
		return part.Shape
	end)

	if not ok then
		return "Unknown"
	end

	if shape == Enum.PartType.Block then
		return "Block"
	elseif shape == Enum.PartType.Ball then
		return "Ball"
	elseif shape == Enum.PartType.Cylinder then
		return "Cylinder"
	end

	return "Unknown"
end

--========================================
-- CONFIG
--========================================

local INCHES_PER_UNIT = 0.75
local STUDS_PER_INCH = 1 / 11.0236

local function ToStuds(units)
	return units * INCHES_PER_UNIT * STUDS_PER_INCH
end

local Config = {
	UseSourceGravity = true,
	SourceGravity = 800,

	MaxWalkSpeed = 210,
	AirWishSpeed = 160,
	AirSpeedCap = 120,

	GroundAccel = 14,
	AirAccel = 150,
	Friction = 4,
	StopSpeed = 100,

	SurfaceFriction = 1,
	JumpVelocity = 268,
	MaxMomentum = 30000,

	MaxStepHeight = 0.45,
	StepForwardCheck = 0.45,
	GroundCheckDistance = 0.5,
	GroundNormalMin = 0.7,
	GroundSnapMinNormalY = 0.7,
	CeilingNormalMin = 0.7,
	FootRaySide = 0.85,

	PhysicsTickRate = 60,

	ScrollJumpBufferTime = 0.07,
	ScrollDebounceTime = 0.05,

	CamStand = Vector3.new(0, 0, 0),
	CamCrouch = Vector3.new(0, -1.5, 0),
	CamProne = Vector3.new(0, -3, 0),

	KeyCrouch = Enum.KeyCode.C,
	KeyProne = Enum.KeyCode.V,

	StandSpeedScale = 1,
	CrouchSpeedScale = 0.33,
	ProneSpeedScale = 0.15,
	PoseLerpSpeed = 15,

	GroundSnapEpsilon = 0.06,
	FrictionDelayFrames = 1,
	AirControl = false,
	AirControlFactor = 0.25,

	HullHalfWidth = 0.75,

	MaterialFrictionMultipliers = {
		[Enum.Material.Ice] = 0.2,
		[Enum.Material.Glacier] = 0.25,
		[Enum.Material.Mud] = 1.5,
		[Enum.Material.Concrete] = 1,
		[Enum.Material.Grass] = 0.9,
		[Enum.Material.Sand] = 1.15,
		[Enum.Material.Wood] = 0.95
	}
}

local SourceGravityStuds = ToStuds(Config.SourceGravity)
local JumpVelocityStuds = ToStuds(Config.JumpVelocity)
local MaxMomentumStuds = ToStuds(Config.MaxMomentum)
local MaxWalkSpeedStuds = ToStuds(Config.MaxWalkSpeed)
local AirWishSpeedStuds = ToStuds(Config.AirWishSpeed)
local AirSpeedCapStuds = ToStuds(Config.AirSpeedCap)
local StopSpeedStuds = ToStuds(Config.StopSpeed)

if Config.UseSourceGravity then
	Workspace.Gravity = SourceGravityStuds
end

local function IsWalkableNormal(normal)
	return normal and normal.Y >= Config.GroundNormalMin
end

local function IsSnapSurface(normal)
	return normal and normal.Y >= Config.GroundSnapMinNormalY
end

local function GetSurfaceCategory(hitPart, hitNormal)
	if not hitNormal then
		return "None"
	end

	local y = hitNormal.Y
	local shape = GetPartShapeName(hitPart)
	local curved = (shape == "Ball" or shape == "Cylinder")

	if y >= Config.GroundNormalMin then
		if curved then
			return "WalkableCurved"
		end
		return "Walkable"
	elseif y > 0 then
		if curved then
			return "SteepCurved"
		end
		return "Steep"
	elseif y <= -Config.CeilingNormalMin then
		if curved then
			return "CeilingCurved"
		end
		return "Ceiling"
	end

	if curved then
		return "WallCurved"
	end
	return "Wall"
end

--========================================
-- CONNECTION HELPERS
--========================================

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

--========================================
-- MOVEMENT MATH
--========================================

local STOP_EPSILON = 0.1
local OVERBOUNCE = 1.001

local function ClipVelocity(velocity, normal, overbounce)
	overbounce = overbounce or OVERBOUNCE
	local backoff = velocity:Dot(normal) * overbounce
	local out = velocity - (normal * backoff)

	if math.abs(out.X) < STOP_EPSILON then out = Vector3.new(0, out.Y, out.Z) end
	if math.abs(out.Y) < STOP_EPSILON then out = Vector3.new(out.X, 0, out.Z) end
	if math.abs(out.Z) < STOP_EPSILON then out = Vector3.new(out.X, out.Y, 0) end

	return out
end

local function ClampMomentum(v)
	if v.Magnitude > MaxMomentumStuds then
		return v.Unit * MaxMomentumStuds
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

local function GetWishDir(cam, moveX, moveZ)
	if not cam then return Vector3.new(0, 0, 0) end
	local look, right = GetCameraLookRight(cam)
	local wish = (SafeUnit(FlatVector(look)) * moveZ) + (SafeUnit(FlatVector(right)) * moveX)
	return SafeUnit(wish)
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

local function AirAccelerateSource(vel, wishDir, wishSpeed, accel, dt)
	local cappedWishSpeed = (AirSpeedCapStuds > 0) and math.min(wishSpeed, AirSpeedCapStuds) or wishSpeed
	local currentSpeed = vel:Dot(wishDir)
	local addSpeed = cappedWishSpeed - currentSpeed
	if addSpeed <= 0 then return vel end
	local accelSpeed = math.min(accel * cappedWishSpeed * dt, addSpeed)
	return vel + wishDir * accelSpeed
end

local function AirControlSource(vel, wishDir, wishSpeed, dt)
	if not Config.AirControl then return vel end
	local flatVel = FlatVector(vel)
	if flatVel.Magnitude < 0.001 then return vel end
	local flatWish = FlatVector(wishDir)
	if flatWish.Magnitude < 0.001 then return vel end

	local dot = math.max(SafeUnit(flatVel):Dot(SafeUnit(flatWish)), 0)
	local k = Config.AirControlFactor * dot * dot * dt
	local newFlat = flatVel + (SafeUnit(flatWish) * (wishSpeed * k))
	return Vector3.new(newFlat.X, vel.Y, newFlat.Z)
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

--========================================
-- HULL COLLISION
--========================================

local function TraceHull(startPos, endPos, halfWidth, halfHeight, ignoreList)
	local dir = endPos - startPos
	local dist = dir.Magnitude
	if dist < 0.0001 then
		return { Fraction = 1, EndPos = startPos, AllSolid = false }
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
					PlaneNormal = hitNormal,
					HitPart = hitPart,
					HitPos = hitPos,
					AllSolid = true
				}
			end
		end
	end

	return { Fraction = 1, EndPos = endPos, AllSolid = false }
end

local function TryPlayerMove(startPos, velocity, dt, halfWidth, halfHeight, ignoreList)
	local timeLeft = dt
	local currentPos = startPos
	local currentVel = velocity
	local numBounces = 4

	for bounce = 1, numBounces do
		if timeLeft <= 0 or currentVel.Magnitude < 0.001 then break end
		local endPos = currentPos + currentVel * timeLeft
		local trace = TraceHull(currentPos, endPos, halfWidth, halfHeight, ignoreList)

		currentPos = trace.EndPos
		timeLeft = timeLeft * (1 - trace.Fraction)

		if trace.Fraction < 1 and trace.PlaneNormal then
			currentVel = ClipVelocity(currentVel, trace.PlaneNormal, OVERBOUNCE)
		end
	end

	return currentPos, currentVel
end

local function TryStepMove(startPos, velocity, dt, halfWidth, halfHeight, ignoreList)
	local currentPos = startPos
	local currentVel = velocity

	local destNoStep, velNoStep = TryPlayerMove(currentPos, currentVel, dt, halfWidth, halfHeight, ignoreList)

	local stepUpPos = currentPos + Vector3.new(0, Config.MaxStepHeight, 0)
	local traceUp = TraceHull(currentPos, stepUpPos, halfWidth, halfHeight, ignoreList)
	local elevatedPos = traceUp.EndPos

	local destStep, velStep = TryPlayerMove(elevatedPos, currentVel, dt, halfWidth, halfHeight, ignoreList)

	local stepDownPos = destStep - Vector3.new(0, Config.MaxStepHeight, 0)
	local traceDown = TraceHull(destStep, stepDownPos, halfWidth, halfHeight, ignoreList)

	if traceDown.Fraction < 1 and traceDown.PlaneNormal and IsWalkableNormal(traceDown.PlaneNormal) then
		local movedDistNoStep = (destNoStep - currentPos).Magnitude
		local movedDistStep = (traceDown.EndPos - currentPos).Magnitude
		if movedDistStep > movedDistNoStep then
			return traceDown.EndPos, velStep
		end
	end

	return destNoStep, velNoStep
end

--========================================
-- POSES
--========================================

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
	if not HRP or (pose == "Stand" and CurrentPose ~= "Stand") then
		local ignore = BuildIgnoreList()
		local origin = HRP.Position + Vector3.new(0, GetHullHalfHeight(), 0)
		if RaycastIgnoreList(origin, Vector3.new(0, 3, 0), ignore) then return end
	end

	local oldPose = CurrentPose
	CurrentPose = pose
	local cframeAdjustmentY = 0

	if pose == "Crouch" then
		TargetCameraOffset, CurrentMaxSpeedStuds = Config.CamCrouch, MaxWalkSpeedStuds * Config.CrouchSpeedScale
		if oldPose == "Stand" and not IsGroundedGlobal then cframeAdjustmentY = 1 end
	elseif pose == "Prone" then
		TargetCameraOffset, CurrentMaxSpeedStuds = Config.CamProne, MaxWalkSpeedStuds * Config.ProneSpeedScale
	else
		TargetCameraOffset, CurrentMaxSpeedStuds = Config.CamStand, MaxWalkSpeedStuds * Config.StandSpeedScale
		if oldPose == "Crouch" and not IsGroundedGlobal then cframeAdjustmentY = -1 end
	end

	if cframeAdjustmentY ~= 0 then
		HRP.CFrame = HRP.CFrame * CFrame.new(0, cframeAdjustmentY, 0)
	end
end

--========================================
-- CHARACTER SETUP
--========================================

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

	SpaceHeld, JumpBuffer, TimeAccumulator, IsGroundedGlobal, JumpLockFrames, GroundFrames, LastGrounded = false, 0, 0, false, 0, 0, false

	if MoveBV then
		MoveBV:Destroy()
		MoveBV = nil
	end

	MoveBV = Instance.new("BodyVelocity")
	MoveBV.Name = "SourceMovement"
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

--========================================
-- GROUND DETECTION / SNAP
--========================================

local function GetGroundInfo()
	if not HRP or not Character then
		return false, nil, Config.SurfaceFriction, nil, nil, "None"
	end

	local ignore = BuildIgnoreList()
	local rootPos = HRP.Position
	local feetY = rootPos.Y - GetHullHalfHeight()

	local startY = feetY + 1.0
	local rayDist = Config.GroundCheckDistance + 1.15

	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(Config.FootRaySide, 0, 0),
		Vector3.new(-Config.FootRaySide, 0, 0),
		Vector3.new(0, 0, Config.FootRaySide),
		Vector3.new(0, 0, -Config.FootRaySide)
	}

	local bestHitY = nil
	local bestNormal = nil
	local bestPart = nil
	local bestPos = nil
	local bestFriction = Config.SurfaceFriction
	local bestCategory = "None"

	for i = 1, #offsets do
		local origin = Vector3.new(rootPos.X + offsets[i].X, startY, rootPos.Z + offsets[i].Z)
		local hitPart, hitPos, hitNormal = RaycastIgnoreList(origin, Vector3.new(0, -rayDist, 0), ignore)
		if hitPart and hitNormal and IsWalkableNormal(hitNormal) then
			if not bestHitY or hitPos.Y > bestHitY then
				bestHitY = hitPos.Y
				bestNormal = hitNormal
				bestPart = hitPart
				bestPos = hitPos
				bestFriction = Config.MaterialFrictionMultipliers[hitPart.Material] or Config.SurfaceFriction
				bestCategory = GetSurfaceCategory(hitPart, hitNormal)
			end
		end
	end

	if bestHitY then
		return true, bestNormal, bestFriction, bestPart, bestPos, bestCategory
	end

	return false, nil, Config.SurfaceFriction, nil, nil, "None"
end

local function GroundSnap()
	if not HRP or not Character then return false end

	local ignore = BuildIgnoreList()
	local rootPos = HRP.Position
	local feetY = rootPos.Y - GetHullHalfHeight()

	local startY = feetY + 1.0
	local rayDist = Config.MaxStepHeight + 1.15

	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(Config.FootRaySide, 0, 0),
		Vector3.new(-Config.FootRaySide, 0, 0),
		Vector3.new(0, 0, Config.FootRaySide),
		Vector3.new(0, 0, -Config.FootRaySide)
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
	if heightDiff <= Config.MaxStepHeight and heightDiff >= -Config.MaxStepHeight then
		HRP.CFrame = CFrame.new(rootPos + Vector3.new(0, heightDiff + Config.GroundSnapEpsilon, 0)) * (HRP.CFrame - HRP.Position)
		return true
	end

	return false
end

--========================================
-- INPUT
--========================================

BindConnection(UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Config.KeyCrouch then
		ApplyPose(CurrentPose == "Crouch" and "Stand" or "Crouch")
	elseif input.KeyCode == Config.KeyProne then
		ApplyPose(CurrentPose == "Prone" and "Stand" or "Prone")
	elseif input.KeyCode == Enum.KeyCode.Space then
		SpaceHeld = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		JumpMode = 1
	elseif input.KeyCode == Enum.KeyCode.LeftAlt then
		JumpMode = 2
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
		JumpBuffer = Config.ScrollJumpBufferTime
		delay(Config.ScrollDebounceTime, function()
			ScrollDebounce = false
		end)
	end
end))

--========================================
-- MAIN PHYSICS LOOP
--========================================

BindConnection(RunService.Stepped:Connect(function(_, rawDt)
	if not HRP or not MoveBV or not Humanoid or Humanoid.Health <= 0 then return end

	local fixedDt = 1 / Config.PhysicsTickRate
	TimeAccumulator = TimeAccumulator + math.min(rawDt, 0.1)

	while TimeAccumulator >= fixedDt do
		TimeAccumulator = TimeAccumulator - fixedDt
		JumpBuffer = math.max(JumpBuffer - fixedDt, 0)

		local x, z = GetMoveAxes()
		local wishDir = (x ~= 0 or z ~= 0) and GetWishDir(Workspace.CurrentCamera or Camera, x, z) or Vector3.new(0, 0, 0)

		local vel = HRP.Velocity
		local hVel = vel

		local grounded, groundNormal, surfaceFriction, groundPart, groundPos, groundKind = GetGroundInfo()
		IsGroundedGlobal = grounded

		GroundFrames = grounded and (LastGrounded and GroundFrames + 1 or 1) or 0
		LastGrounded = grounded

		local canJump = (JumpMode == 1 and SpaceHeld) or (JumpMode == 2 and JumpBuffer > 0)

		if grounded then
			if canJump then
				HRP.Velocity = Vector3.new(vel.X, JumpVelocityStuds, vel.Z)
				JumpBuffer = 0
				IsGroundedGlobal = false
				JumpLockFrames = 2
			elseif JumpLockFrames <= 0 then
				if GroundFrames >= (Config.FrictionDelayFrames + 1) then
					hVel = ApplyFriction(hVel, fixedDt, Config.Friction, StopSpeedStuds, surfaceFriction)
				end
				if wishDir.Magnitude > 0 then
					hVel = Accelerate(hVel, wishDir, CurrentMaxSpeedStuds, Config.GroundAccel, fixedDt, surfaceFriction)
				end
				if groundNormal then
					hVel = ClipVelocity(hVel, groundNormal, 1.0)
				end
				hVel = ClampMomentum(hVel)

				if groundNormal and IsSnapSurface(groundNormal) then
					GroundSnap()
				end
			end
		else
			if wishDir.Magnitude > 0 then
				hVel = AirAccelerateSource(hVel, wishDir, AirWishSpeedStuds, Config.AirAccel, fixedDt)
				hVel = AirControlSource(hVel, wishDir, AirWishSpeedStuds, fixedDt)
			end
		end

		hVel = ClampMomentum(hVel)

		local ignoreList = BuildIgnoreList()
		local currentPos = HRP.Position
		local nextPos, nextVel = TryStepMove(currentPos, hVel, fixedDt, Config.HullHalfWidth, GetHullHalfHeight(), ignoreList)

		HRP.CFrame = (HRP.CFrame - HRP.Position) + nextPos
		hVel = nextVel

		local snappedToGround = false
		if JumpLockFrames <= 0 then
			snappedToGround = GroundSnap()
		end

		local groundedAfter, groundNormalAfter, surfaceFrictionAfter, groundPartAfter, groundPosAfter, groundKindAfter = GetGroundInfo()
		IsGroundedGlobal = groundedAfter or snappedToGround

		if IsGroundedGlobal and JumpLockFrames <= 0 then
			MoveBV.MaxForce = Vector3.new(10000000, 10000000, 10000000)
			MoveBV.Velocity = hVel
		else
			MoveBV.MaxForce = Vector3.new(10000000, 0, 10000000)
			MoveBV.Velocity = Vector3.new(hVel.X, 0, hVel.Z)
		end

		if JumpLockFrames > 0 then
			JumpLockFrames = JumpLockFrames - 1
		end
	end
end))

--========================================
-- CAMERA / ROTATION
--========================================

BindConnection(RunService.RenderStepped:Connect(function(dt)
	if Humanoid then
		Humanoid.CameraOffset = Humanoid.CameraOffset:Lerp(TargetCameraOffset, Clamp(Config.PoseLerpSpeed * dt, 0, 1))
	end

	if HRP and Camera then
		local look = Camera.CoordinateFrame:vectorToWorldSpace(Vector3.new(0, 0, -1))
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.001 then
			HRP.CFrame = CFrame.new(HRP.Position, HRP.Position + flat)
		end
	end
end))
