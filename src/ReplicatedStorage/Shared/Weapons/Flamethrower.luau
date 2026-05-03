--!strict
return {
	name = "Flamethrower",

	-- Optional: a Model in ReplicatedStorage.Weapons with this name will be cloned
	-- and welded to the viewmodel's RightArm. If absent, ViewmodelController
	-- falls back to a bare Muzzle attachment on RightArm so the projectile still
	-- has somewhere to spawn from.
	modelName = "Flamethrower",

	-- Where the weapon model's PrimaryPart sits relative to RightArm.
	rightHandGrip = CFrame.new(0, -1, -0.5) * CFrame.Angles(math.rad(-90), 0, 0),

	-- Attachment name expected on the weapon model. Spawned on RightArm in fallback mode.
	muzzleAttachmentName = "Muzzle",
	-- Used by the fallback path (no weapon model): attachment offset relative to RightArm.
	muzzleFallbackOffset = CFrame.new(0, -1.5, 0),

	projectileName = "Flame",

	-- Optional Roblox animation IDs (e.g. "rbxassetid://12345"). Loaded lazily by
	-- ViewmodelController if non-empty.
	idleAnim = nil :: string?,
	fireAnim = nil :: string?,
	equipAnim = nil :: string?,
}
