--!strict
-- Settings module for the Flamethrower. Used as a fallback when no Studio-authored
-- module exists at ReplicatedStorage.Modules.Flamethrower.
--
-- Schema reference (every field is optional unless noted) — fields the
-- ViewmodelController reads:
--
--   First-person animation IDs (loaded onto viewmodel.AnimationController.Animator):
--     fireAnim, emptyFireAnim, equipAnim, deEquipAnim,
--     reloadAnim, emptyReloadAnim, inspectAnim, idleAnim
--
--   Third-person animation IDs (loaded onto character.Humanoid.Animator):
--     TPIdleAnim, TPEquipAnim, TPFireAnim, TPReloadAnim
--
--   Sound instances (cloned + played on the corresponding action):
--     fireSound, equipSound, deEquipSound, reloadSound, emptyReloadSound, inspectSound
--
--   fireMode: "Continuous" | "Auto" | "Semi"
--     - Continuous: fireAnim loops while LMB held, stops on release
--     - Auto/Semi:  fireAnim plays once each fire-start
--
--   projectileName: string key into ReplicatedStorage.Shared.Projectiles
--   muzzleAttachmentName: name of the Attachment to look up in the viewmodel
--   muzzleFallbackOffset: offset on RightArm if no matching Attachment is found
--
--   thirdPersonGrip: optional explicit CFrame for welding the weapon to the
--                    character's Right Arm. If omitted, the controller reads
--                    the grip from ReplicatedStorage.ThirdPersonRigs.<name>'s
--                    Right-Arm Motor6D.

return {
	name = "Flamethrower",

	fireMode = "Continuous",
	projectileName = "Flame",
	muzzleAttachmentName = "Muzzle",
	muzzleFallbackOffset = CFrame.new(0, -1.5, 0),

	idleAnim = nil :: string?,
	equipAnim = nil :: string?,
	deEquipAnim = nil :: string?,
	fireAnim = nil :: string?,
	emptyFireAnim = nil :: string?,
	reloadAnim = nil :: string?,
	emptyReloadAnim = nil :: string?,
	inspectAnim = nil :: string?,

	TPIdleAnim = nil :: string?,
	TPEquipAnim = nil :: string?,
	TPFireAnim = nil :: string?,
	TPReloadAnim = nil :: string?,

	fireSound = nil :: Sound?,
	equipSound = nil :: Sound?,
	deEquipSound = nil :: Sound?,
	reloadSound = nil :: Sound?,
	emptyReloadSound = nil :: Sound?,
	inspectSound = nil :: Sound?,

	thirdPersonGrip = nil :: CFrame?,
}
