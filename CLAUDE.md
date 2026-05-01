# CLAUDE.md

Project context for Claude Code when working in this Roblox game.

## Project: Burn Rush

A round-based Roblox tag-style game. One player starts "burning" and converts others by spraying them with a flamethrower (with stage-based passive hazards layered on top). Built with Rojo + Luau.

- **Rojo project**: `default.project.json` (services map to `src/<Service>/`)
- **Toolchain**: `aftman.toml`
- **Scripts**: Luau (`.luau` ModuleScript, `.server.luau` Script, `.client.luau` LocalScript)
- **Style**: Functional modules (no OOP). Each system is a table with `init()` and public functions.

## Architecture

### Server (`src/ServerScriptService/`)

- `Main.server.luau` — bootstrap. Requires and `init()`s every system in this order:
  `PlayerState → MapManager → AbilitySystem → FireAttackSystem → InfectionSystem → FireSpreadSystem → RoundManager`
- `Systems/PlayerState.luau` — per-player state (`Lobby` / `Safe` / `Burning`). Replicates via `PlayerStateChanged` RemoteEvent. Exposes `StateChanged` BindableEvent.
- `Systems/RoundManager.luau` — game loop and round lifecycle. Owns the phase state machine, the 3-stage in-round progression, character setup (regen disable via `BreakJointsOnDeath = false`), per-burner Fire/Highlight visuals, and the kill-feed broadcast. Starts/stops `FireAttackSystem` alongside `InfectionSystem`/`FireSpreadSystem`.
- `Systems/FireAttackSystem.luau` — active flamethrower for burners. Holds per-burner fuel, spawns/destroys the visual `ParticleEmitter` stream on the torso when the player is firing, and exposes `getFiringBurners()` (used by `InfectionSystem` to do cone damage). Auto-creates the `FireRequest` and `FuelChanged` remotes on `init()`. Drains fuel only while firing; regenerates passively otherwise.
- `Systems/InfectionSystem.luau` — damage engine. Each Heartbeat, iterates safe players; for each, checks (a) the cone of every actively-firing burner from `FireAttackSystem`, then (b) registered hazards (trail walls, ignited parts). Sends `DamageDealt`/`DamageTaken` RemoteEvents when a tick lands. When HP hits 0, fires `PlayerInfected` and restores HP (no actual death). Auto-creates the `DamageDealt` and `DamageTaken` remotes on `init()`.
- `Systems/FireSpreadSystem.luau` — owns Stage 2 fire-wall trails and Stage 3 touch-ignition. Wall segments are visible Neon parts with flame `ParticleEmitter`s — they double as the visual and the damage hitbox.
- `Systems/MapManager.luau` — clones map from `ServerStorage.Maps` into `Workspace.LoadedMap`, manages spawn points and lobby teleport. Warns at `init()` if `ServerStorage.Maps` is missing or empty.
- `Systems/AbilitySystem.luau` — dash mechanic for safe players (Q key). Phase-gated via `start()` / `stop()`: dash is rejected outside the active `Round` phase, so safe players cannot dash during reveal/role-reveal/lobby. `start()` also clears `lastDash` so cooldowns don't carry across rounds.

### Client (`src/StarterPlayerScripts/`)

- `Main.client.luau` — bootstrap. Inits `DashController`, `UIController`, `KillFeedController`, `RoleRevealController`, `FireAttackController`, `CombatFeedbackController` (in that order).
- `Controllers/UIController.luau` — reads phase/stage/player-state remotes, renders RichText into two labels: `Game.StatusFrame.Status` (main announcements + stage) and `Game.SecondaryStatus.Secondary` (timer + alive count). Alive count excludes the local player (`safe / total-1`). Both labels are blanked during `PHASE_ROLE_REVEAL` so the role UI has the screen to itself.
- `Controllers/KillFeedController.luau` — listens to `KillFeed` remote, clones `Game.ID_Objects.KillData` into `Game.Killfeed` per kill, animates entrance/exit (TweenService), maintains a queue.
- `Controllers/DashController.luau` — sends `DashRequest` on Q.
- `Controllers/RoleRevealController.luau` — drives the per-player role-reveal animation during `PHASE_ROLE_REVEAL`. Reads `extra.burner` from the phase broadcast to derive `localIsBurner`, then animates `Game.Role` (Frame, with TextLabel children `Title` (static heading, never touched) and `ROLE` (cycled)). Timeline: 0.3s entrance (UIScale 0→1, Back/Out) → 2s cycle (`ROLE.Text` swaps SURVIVOR/TAGGER, interval easing from 0.04s → 0.30s) → 0.5s settle (final role with a UIScale punch on the label) → 0.5s exit (UIScale 1→0, Quad/In). Uses a `revealGen` generation counter so an in-flight animation bails if the phase changes mid-anim. Late joiners (`duration < ROLE_REVEAL_TIME * 0.6`) skip the cycle.
- `Controllers/FireAttackController.luau` — burner offense input. While the local player is `Burning`, holding LMB sends `FireRequest(true)`; releasing sends `FireRequest(false)`. Listens to `FuelChanged` to drive `Game.FuelMeter.BarBG.Fill` (size tween) and `Game.FuelMeter.BarBG.EmptyOverlay` (visible when fuel is below `FIRE_FUEL_MIN_TO_START`). Hides the meter for non-burners. Has a `RenderStepped` safety check that releases the hold if mouse-up was missed (e.g., focus lost).
- `Controllers/CombatFeedbackController.luau` — purely cosmetic. Listens to `DamageDealt` (burner side: throttled hit-confirm sound, batches damage into floating numbers above the victim's head via the `ReplicatedStorage.Assets.UI.DamageNumber` BillboardGui template) and `DamageTaken` (victim side: vignette pulse, camera shake, HP-threshold grunts at 75/50/25%, looping sizzle while taking damage). Also listens to `KillFeed` for kill-confirm whoosh / convert-impact effects. Uses `Game.Vignette` and `Game.Crosshair` GuiObjects. Sound IDs are stubbed (`""`) — see the `SOUND_IDS` table at the top of the file when assets are ready.
  - **Burner mode**: listens to both `PlayerStateChanged` and `RoundStateChanged` for the local player. Burner mode is active iff `state == Burning AND phase ∈ {Reveal, Round}` — deliberately **off** during `PHASE_ROLE_REVEAL` so the camera doesn't lock during the role-reveal animation. When active, it shows the custom `Game.Crosshair`, sets `Player.CameraMode = LockFirstPerson`, and disables `UserInputService.MouseIconEnabled` to hide Roblox's default cursor/reticle. When inactive (round end, lobby, role-reveal in progress) it hides the crosshair, restores `CameraMode = Classic`, and re-enables the mouse icon.
  - **Crosshair**: a continuous two-state visual driven by LMB hold (gated on `isBurner`) — idle while not firing, larger/red while firing, with a smooth 0.12s tween between them. There is **no** per-hit pulse: the crosshair stays in its firing state for the entire LMB-hold, mirroring the continuous flame stream.

### Character (`src/StarterCharacterScripts/`)

- `Health.client.luau` — empty override of Roblox's default Health script. Disables passive HP regen so damage from burners persists between encounters.

### Shared (`src/ReplicatedStorage/`)

- `Shared/Constants.luau` — all tunables (round/stage timing, damage rates, radii, walkspeeds, tag names, state strings).
- `Shared/Types.luau` — Luau type aliases (currently lightly used).

### Remotes (`ReplicatedStorage.Remotes`)

The `Remotes` folder lives in Studio (not Rojo source); it is preserved across syncs because `ReplicatedStorage` has `ignoreUnknownInstances: true`. Several remotes are **auto-created** by their owning system if missing (the `ensureRemote` pattern), so you don't have to author them in Studio.

- `RoundStateChanged` (RemoteEvent) — server broadcasts `(phase, duration?, extra?)`. During `RoleReveal` and `Reveal`, `extra` is `{ burner = name }` (same shape — clients use `extra.burner == localPlayer.Name` to derive `localIsBurner`). During `Round`, `extra` is `{ stage = 1|2|3 }`. At `End`, `extra` is `{ winners = { name, ... }, reason }` — `winners` may be empty (everyone burned / aborted).
- `PlayerStateChanged` (RemoteEvent) — server broadcasts `(player, state)`.
- `DashRequest` (RemoteEvent) — client → server.
- `FireRequest` (RemoteEvent) — client → server `(active: bool)`. Burner press/release of LMB. Auto-created by `FireAttackSystem.init()`.
- `FuelChanged` (RemoteEvent) — server → client `(fuel, max)`. Throttled (only fires on >=0.05s change, plus forced edges at full/empty). Auto-created by `FireAttackSystem.init()`.
- `DamageDealt` (RemoteEvent) — server → attacker `(victim, dmg, victimHP)` per damage tick (only when source was a Player). Auto-created by `InfectionSystem.init()`.
- `DamageTaken` (RemoteEvent) — server → victim `(attacker?, dmg, currentHP)` per damage tick. `attacker` is `nil` for hazard damage. Auto-created by `InfectionSystem.init()`.
- `KillFeed` (RemoteEvent) — server broadcasts `(killerName?, victimName)` per conversion. Auto-created by `RoundManager.init()`.
- `InfectionProgress` (RemoteEvent) — legacy; no longer fired (kept to avoid Studio-side cleanup).

### GUI structure (`PlayerGui.Game`, a ScreenGui authored in Studio)

- `StatusFrame.Status` (TextLabel) — main HUD line. Stage info during round, "GET READY!" during intermission, `"<NAME> IS BURNING!"` during reveal, winner banner at end (1 / 2 / `N PLAYERS` formats). RichText, all uppercase.
- `SecondaryStatus.Secondary` (TextLabel) — secondary HUD line. Timer + `safe/total` alive count joined by ` | `.
- `Killfeed` (Frame) — kill feed entries are parented here.
- `ID_Objects.KillData` (TextLabel) — template cloned per kill into `Killfeed`. Hidden by default; `Visible = true` set on the clone.
- `FuelMeter` (GuiObject) — fuel bar shown only while local player is `Burning`. Children: `BarBG.Fill` (sized 0..1 by `FireAttackController`) and `BarBG.EmptyOverlay` (visible while fuel is below `FIRE_FUEL_MIN_TO_START`).
- `Vignette` (Frame) — full-screen damage overlay; `BackgroundTransparency` is tweened by `CombatFeedbackController` on every damage tick taken.
- `Crosshair` (Frame) — small centered reticle; punched (size + color tween) by `CombatFeedbackController` on every confirmed hit landed.
- `Role` (Frame) — role-reveal UI shown during `PHASE_ROLE_REVEAL`. Children: `Title` (TextLabel, static heading authored in Studio — never modified by code) and `ROLE` (TextLabel whose `.Text` and `.TextColor3` are cycled then settled by `RoleRevealController`). The frame's UIScale is created on first resolve if missing.

### Asset templates (`ReplicatedStorage.Assets.UI`)

- `DamageNumber` (BillboardGui) — must contain a `Label` (TextLabel) with a `UIStroke` and `UIScale`. Cloned and parented to the victim's `Head` per damage burst by `CombatFeedbackController`. Authored in Studio (not in Rojo source).

## Round Flow

`Lobby → Intermission (10s) → RoleReveal (3.5s) → Reveal (10s) → Round (90s, 3 × 30s stages) → End (5s) → Lobby`

`gameLoop` loads the map **before** broadcasting `Intermission`. If the map fails to load (no `ServerStorage.Maps`, or it's empty), it warns and stays in the `Lobby` phase instead of getting stuck cycling through intermission.

**RoleReveal phase** is a per-player UI animation window. The burner has already been chosen and `setBurning` has been called (so they have fire + outline) before the phase broadcast. `RoleRevealController` cycles `Game.Role.ROLE` between SURVIVOR (#1BB420) and TAGGER (#FF383C), settles on the local player's actual role, then fades out. `CombatFeedbackController` deliberately does NOT activate burner mode (first-person lock + custom crosshair) during this phase to preserve the suspense.

**Reveal phase** is a no-damage, no-ability positioning window. Safe players use the time to position themselves; the burner is in first-person with their crosshair active. `FireAttackSystem`, `InfectionSystem`, `FireSpreadSystem`, and `AbilitySystem` are all deliberately NOT started until reveal ends, so no damage, walls, ignition, fuel drain, or dashing can happen during it.

`endRound` order is important: stop all four active systems (`FireAttackSystem`, `InfectionSystem`, `FireSpreadSystem`, `AbilitySystem`) → **heal everyone to MaxHealth** → teleport everyone to lobby → unload map → THEN broadcast `End` and wait `END_TIME`. The map disappears the instant the round ends; players watch the announcement from the lobby with full HP.

The round does **not** end early when only one safe player remains — the timer must run out. A round only ends early if (a) every safe player is converted (`AllInfected`), or (b) the player count drops below `MIN_PLAYERS` (`Aborted`). When the timer runs out, **every** remaining safe player is a winner.

### Stages (within Round phase)

The flamethrower (see "Fire Attack" below) is available to every burner for the entire round, in all three stages. Stages add **passive hazards** on top of it.

| Stage | Duration | Behavior |
|-------|----------|----------|
| 1 (TAG) | 0–30s | Active flamethrower only — no passive hazards. Burners must aim and fire at safe players to do damage. |
| 2 (TRAILS) | 30–60s | Adds: each burner leaves a continuous **fire wall** behind them. Tall (6 studs), thin Neon segments are dropped between successive foot positions whenever the burner moves at least `TRAIL_SEGMENT_MIN_LENGTH` studs. Walls last 5s and deal `HAZARD_DAMAGE_PER_SEC` (5 HP/s) to anything within `TRAIL_RADIUS` of the wall surface (≈ "touching it"). |
| 3 (INFERNO) | 60–90s | Adds: anything a burner physically touches catches fire **for the rest of the round** (`IGNITE_RADIUS` = 5 studs, 5 HP/s) — ignited parts never extinguish until `endRound`. Does not apply to parts with a `Fireproof` `BoolValue` child set to `true`, or to player characters. |

### Fire Attack (active flamethrower, all stages)

Burners aim with the camera and hold **LMB** to spew a cone of flame from their torso.

- **Cone**: `FIRE_CONE_RANGE` (14 studs) long, `FIRE_CONE_HALF_ANGLE` (35°) half-angle. `InfectionSystem` precomputes the dot threshold (`cos(35°)`) once at module load and tests every safe player's HRP against `(burner.lookVector ⋅ toTarget.Unit)` each Heartbeat. Standing on top of the burner (distance < 0.001) always counts as in-cone.
- **Damage**: `FIRE_DAMAGE_PER_SEC` (18 HP/s, ~5.5 seconds to drain a full health bar). Active fire takes priority over hazard damage in the per-tick check — a player in both a wall and a cone takes only the cone tick.
- **Fuel**: `FIRE_FUEL_MAX` (3.0 seconds of continuous fire). Drains at 1.0/sec while firing; regenerates at `FIRE_FUEL_REGEN_PER_SEC` (1.0/sec) while not firing — i.e., 1:1 burn-to-recover. `FIRE_FUEL_MIN_TO_START` (0.3) prevents tap-spam at empty: a burner must let fuel recover above the threshold before they can re-trigger. Hitting 0 while firing force-stops the stream.
- **Visual**: an `Attachment` named `FlameAttachment` is placed 2 studs in front of the torso (`UpperTorso` / `Torso` / `HumanoidRootPart` fallback), with a `ParticleEmitter` (`FlamethrowerStream`) and a `PointLight` (`FlamethrowerLight`) child. On stop, the emitter is disabled and destroyed 0.7s later so in-flight particles can taper out cleanly.
- **Burner grace** still applies: `FireAttackSystem.getFiringBurners()` returns *all* firing burners; `InfectionSystem.step` then filters out burners whose `NEW_BURNER_GRACE` window hasn't elapsed.

### Conversion rule

Players are **never killed**. When a safe player's HP reaches 0:
- HP is restored to `MaxHealth`.
- `InfectionSystem.PlayerInfected` fires; `RoundManager.onPlayerInfected` calls `setBurning(player, withGrace=true)` and fires `KillFeed:FireAllClients(killerName, victimName)`.
- `Humanoid.BreakJointsOnDeath` is set `false` on every spawn so a 0-HP frame never triggers ragdoll.

The killer name is `nil` when the kill came from a hazard (trail/ignited part) — the kill feed renders that as `"Victim burned"` instead of `"Killer burned Victim"`. Cone damage from a firing burner attributes the kill to that burner.

### Grace period

A freshly converted burner gets `NEW_BURNER_GRACE` (1.0s) before they appear in the burner list, preventing instant-cascade infection.

## Visual identity (per burner)

Set up by `RoundManager.setBurning` on conversion and torn down by `setSafe`/`setLobby`:

- **`BurnFire`** — `Fire` instance on the burner's torso (visible flames on the body).
- **`BurnOutline`** — `Highlight` named `BurnOutline`, orange (`255,130,0`), `FillTransparency = 1` (outline-only), `DepthMode = AlwaysOnTop`. Lets safe players spot burners through walls.

`FireSpreadSystem` adds these, only during stages 2/3:

- **Fire-wall trail** — Stage 2+. Not parented to the burner; lives in `Workspace.FireHazards`. Each segment is a `Part` named `TrailWall` (Neon, orange, ~35% transparent) with a `WallFlame` `ParticleEmitter` child. New segments are produced from the heartbeat loop in `step` whenever the burner has moved at least `TRAIL_SEGMENT_MIN_LENGTH` from the last anchor. After `TRAIL_DURATION` the emitter is disabled and the part is destroyed `WALL_FADE_OUT` later so particles can finish.
- **Touched listeners** — Stage 3 only. One per `BasePart` of the burner's character.

## Map Authoring

Maps live in `ServerStorage.Maps` (each is a `Model`). At runtime they are cloned into `Workspace.LoadedMap` (a Folder created on demand). `MapManager.unloadMap()` destroys the whole folder, so even if the `currentMap` reference is lost no orphan parts can survive.

Required structure inside each map Model:
- `SpawnPoints/` folder containing `BasePart`s named `SpawnPoint`.

For Stage 3 to behave correctly, **mark any part that should NOT catch fire** by parenting a `BoolValue` named `Fireproof` (with `Value = true`) under it (typically: ground, walls, large terrain). Parts without that child will ignite when a burner touches them. This is opt-out by design — most props should burn.

## Hazard System

`FireSpreadSystem` creates two kinds of damage hazards, both registered with `InfectionSystem.registerHazard(part, radius)`:

- **Trail walls** — visible Neon orange `TrailWall` parts in `Workspace.FireHazards`. Both the visual and the damage hitbox.
- **Ignited parts** — six `BurnFlames_<Face>` `ParticleEmitter`s parented directly to the touched map part (one per `NormalId`: Top/Bottom/Front/Back/Left/Right) so flames cover **every face** of the object, not just the centre or the top. Each emitter's `Rate` is scaled by that face's area (clamped 6–80). Ignited parts **never self-extinguish** — they keep burning until `FireSpreadSystem.stop()` is called at round end, which removes the emitters and unregisters the hazards. The part itself is left intact.

Both deal `HAZARD_DAMAGE_PER_SEC` (half of direct burner damage). `InfectionSystem` measures distance from the **closest point on the hazard's bounding box** to the player's HRP, so long wall segments damage along their full length, not just near their center. Direct burner contact takes priority over hazards in the damage check.

`FireSpreadSystem.stop()` (called from `endRound`) destroys the hazard folder, clears any lingering ignited fires from map geometry, and detaches all Touched listeners.

## Rojo & Project Config

`default.project.json`:
- No `Baseplate` is defined — sync does not re-create one.
- `$ignoreUnknownInstances: true` is set on the DataModel root, `Workspace`, `StarterPlayer`, `Lighting`, `SoundService`. All folder-mapped services have the same flag in their `init.meta.json`. **Anything you build in Studio that isn't in source is preserved across syncs** (Remotes folder, Maps, Lobby, GUI assets, etc.).
- Files that *are* in source remain authoritative — Studio edits to those will be overwritten on next sync.

## Conventions

- New tunables go in `Constants.luau`. Don't hardcode magic numbers in systems.
- New cross-system signals: prefer `BindableEvent` over polling. Existing examples: `PlayerState.StateChanged`, `InfectionSystem.PlayerInfected`.
- Server creates Workspace instances; they replicate to clients automatically. No remote needed for visual effects.
- Per-frame work goes through `RunService.Heartbeat` (server) or `RenderStepped` (client).
- Phase changes broadcast via the existing `RoundStateRemote` `extra` payload — add fields rather than creating new remotes for round metadata.
- Need a new RemoteEvent? Use the `ensureRemote(parent, name)` pattern at the top of any server module (`FireAttackSystem`, `InfectionSystem`, `RoundManager` all do this) — it returns the existing remote if present, else creates one. Don't rely on Studio-authored remotes for new functionality.
- UI text colors: use `colorize(color, text)` helper in `UIController` to wrap text in RichText `<font>` tags. Both labels have `RichText = true` set automatically on first resolve.
- Cosmetic-only client feedback (sounds, screen shake, vignette, damage numbers) belongs in `CombatFeedbackController` — driven by `DamageDealt` / `DamageTaken` / `KillFeed` remotes. Don't add gameplay logic here; if a feature needs server authority, route it through the existing remotes instead.

## Testing

In Studio, use **Test → Local Server → 2 Players** for end-to-end testing. To shorten iteration, temporarily lower `STAGE_DURATION` and `ROUND_TIME` in `Constants.luau`.

Quick smoke checklist after changes:
1. After intermission, the `Role` frame pops up (UIScale entrance), `ROLE` cycles SURVIVOR (green) ↔ TAGGER (red), settles on the correct role per player, fades out. Status / secondary banners are blank during this window. Burner stays in third-person during the animation.
2. After the role reveal fades out, the 10s positioning window begins. Status shows "<NAME> IS BURNING!", secondary shows "Position yourself! 10s". The burner's camera locks to first-person and the custom crosshair appears at this point. Pressing Q does **not** dash; LMB does **not** spawn a flame stream.
3. Round starts, Status frame shows "STAGE 1/3 — TAG" → "STAGE 2/3 — TRAILS" → "STAGE 3/3 — INFERNO" at the right times (color shifts yellow → orange → red). Dash and flamethrower work normally.
4. Secondary frame shows `1:30  |  2/3` (timer flips red below 30s; alive count excludes self).
5. As a burner, holding LMB spawns a flame cone in front of the torso, drains the `FuelMeter` bar over ~3s, and force-stops at 0; releasing LMB regens the bar at the same rate. Cone-tagging a safe player drains their HP at ~18 HP/s (~5.5s to convert from full HP).
6. As a victim, taking damage shows a vignette pulse + light camera shake; the screen does NOT shake while you're not being hit. Damage numbers stream out over the victim's head every ~0.25s while damage is landing.
7. HP hitting 0 swaps the player to burning — no death animation, no respawn. Kill feed shows `"Killer burned Victim"` for cone kills, `"Victim burned"` for hazard kills.
8. Stage 2: tall fire walls trail behind moving burners and stay around for ~5 seconds; safe players who walk into one take ~5 HP/s. A safe player simultaneously in a wall AND a cone takes the cone tick, not both.
9. Stage 3: burner brushes a prop → prop ignites with flames visible on **every face** and stays burning for the rest of the round; brushes a wall with a `Fireproof` `BoolValue` child (`Value = true`) → nothing.
10. All burners visibly outlined orange (visible through walls). The `FuelMeter` is hidden for safe players and visible for burners.
11. Round end clears all trail walls, ignited fires, hazard folder, flame attachments, **and the cloned map** (`Workspace.LoadedMap` is gone). All players are at full HP back in the lobby. Camera returns to Classic, default cursor returns, the `Role` frame is hidden.
12. Start a second round: dash works once STAGE 1 begins (no stale cooldown carrying from the previous round).

If you start the server and immediately hear the intermission countdown loop forever, check Output for `MapManager: ServerStorage.Maps ...` warnings — that's the cause.
