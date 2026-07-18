# RetrBloxSource (RRS)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/Textures/RSS%20logo.svg">
    <source media="(prefers-color-scheme: light)" srcset="Assets/Textures/RSS%20logo.svg">
    <img alt="RetrBloxSource Logo" src="Assets/Textures/RSS%20logo.svg" width="450">
  </picture>
</p>

<p align="left">
  <span style="vertical-align: middle;">icon: </span>
  <picture style="vertical-align: middle;">
    <source media="(prefers-color-scheme: dark)" srcset="Assets/Textures/RSS%20icon.svg">
    <source media="(prefers-color-scheme: light)" srcset="Assets/Textures/RSS%20icon.svg">
    <img alt="RetrBloxSource Icon" src="Assets/Textures/RSS%20icon.svg" width="48" style="vertical-align: middle;">
  </picture>
</p>

RetrBloxSource (RRS) is a legacy Roblox custom movement controller built to recreate Source Engine and Quake-style player movement on older Roblox versions.

Instead of relying on Roblox’s default character controller, RRS uses a custom physics-based movement system focused on momentum, acceleration, and collision handling. The goal is to bring back the feel of classic FPS movement in a way that still works with the APIs and engine behavior available in older Roblox builds.

## Target Build

RRS was developed and tested primarily on:

**Roblox Studio / Client**  
**Build:** 0.304.0.145042  
**Date:** August 23, 2017

That build is the main compatibility target for the project.

## What RRS Does

RRS replaces standard movement with a custom controller built around classic FPS movement ideas, including:

* Bunny hopping
* Air acceleration
* Ground friction
* Momentum preservation
* Custom gravity
* Collision-based movement
* Step movement
* Velocity-driven physics

Movement is handled through simulation rather than `Humanoid.WalkSpeed`, which gives the system much more control over how the player moves.

## Core Services Used

RRS only depends on legacy Roblox services that were available in older builds:

* `Players`
* `RunService`
* `UserInputService`
* `Workspace`

Example:

```lua
game:GetService("Players")
game:GetService("RunService")
game:GetService("UserInputService")
game:GetService("Workspace")
```

## Character Requirements

RRS expects a standard Roblox character setup with:

* `HumanoidRootPart`
* `Humanoid`

Typical access patterns include:

```lua
Players.LocalPlayer
player.Character
character:FindFirstChild()
```

## Physics Support

The framework works with classic Roblox physics properties, especially:

* `BasePart.Velocity`
* `BasePart.Position`
* `BasePart.CFrame`
* `BasePart.CanCollide`

It does not depend on modern character controllers or newer physics systems.

## CFrame and Vector Support

RRS uses the older CFrame and Vector3 APIs that were available in legacy Roblox builds.

Supported CFrame features:

```lua
CFrame.new()
CFrame.Angles()
CFrame.lookVector
```

Supported Vector3 features:

```lua
Vector3.new()
Vector3.Magnitude
Vector3.Unit
Vector3.Dot()
```

These are used for movement direction, speed control, acceleration, and collision response.

## Raycasting

RRS uses the older raycasting methods instead of modern `Workspace:Raycast()` calls:

```lua
Workspace:FindPartOnRay()
Workspace:FindPartOnRayWithIgnoreList()
```

This keeps the project compatible with legacy Roblox versions.

## Input System

Input is handled through the older `UserInputService` APIs:

```lua
UserInputService:IsKeyDown()
UserInputService.InputBegan
UserInputService.InputEnded
```

These are used for movement input, jump timing, and player control.

## Legacy Compatibility

RRS is intentionally built without modern Lua or Roblox features that were not available in the target build.

It does not require:

```lua
math.clamp()
table.clear()
Instance:GetDescendants()
Workspace:Raycast()
RaycastParams
CFrame.lookAt()
```

It also avoids modern Humanoid movement systems.

## Physics Model

The movement model is inspired by classic Source and Quake mechanics, with emphasis on:

* Acceleration
* Air control
* Friction
* Velocity preservation
* Collision clipping
* Step movement
* Custom gravity

The idea is to preserve the feel of older FPS movement while staying within the limits of legacy Roblox physics.

## Project Goals

RRS exists for developers who want to experiment with retro Roblox movement and physics. The main goals are:

* Keep compatibility with older Roblox builds
* Recreate Source-style movement
* Study legacy engine behavior
* Build a custom movement framework
* Work within historical API limitations

## Compatibility Notes

RRS is intended for:

* Roblox Studio 2017-era builds
* Legacy Roblox clients
* Custom movement experiments
* Retro Roblox projects
* Physics-focused gameplay systems

Modern Roblox versions may require adjustments because some APIs and engine behaviors have changed since then.

**Note:** RRS targets historical Roblox builds and is not designed for current Roblox engine versions without modifications.
