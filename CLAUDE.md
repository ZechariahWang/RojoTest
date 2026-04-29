# CLAUDE.md

Project context for Claude Code when working in this Roblox game.

## Project: Burn Rush

A round-based Roblox tag-style game. One player starts "burning" and converts others by proximity damage. Built with Rojo + Luau.

- **Rojo project**: `default.project.json` (services map to `src/<Service>/`)
- **Toolchain**: `aftman.toml`
- **Scripts**: Luau (`.luau` ModuleScript, `.server.luau` Script, `.client.luau` LocalScript)
- **Style**: Functional modules (no OOP). Each system is a table with `init()` and public functions.

## Architecture

### Server (`src/ServerScriptService/`)

- `Main.server.luau` — bootstrap. Requires and `init()`s every system in this order:
  `PlayerState → MapManager → AbilitySystem → InfectionSystem → FireSpreadSystem → RoundManager`
- `Systems/PlayerState.luau` — per-player state (`Lobby` / `Safe` / `Burning`). Replicates via `PlayerStateChanged` RemoteEvent. Exposes `StateChanged` BindableEvent.
- `Systems/RoundManager.luau` — game loop and round lifecycle. Owns the phase state machine, the 3-stage in-round progression, character setup (regen disable via `BreakJointsOnDeath = false`), per-burner Fire/Highlight visuals, and the kill-feed broadcast.
- `Systems/InfectionSystem.luau` — damage-over-time engine. Iterates safe players each Heartbeat, applies damage from any in-range burner or registered hazard. When HP hits 0, fires `PlayerInfected` and restores HP (no actual death).
- `Systems/FireSpreadSystem.luau` — owns Stage 2 fire trails and Stage 3 touch-ignition. Per-burner `ParticleEmitter` for visuals; invisible hazard parts for damage hitboxes.
- `Systems/MapManager.luau` — clones map from `ServerStorage.Maps` into `Workspace.LoadedMap`, manages spawn points and lobby teleport. Warns at `init()` if `ServerStorage.Maps` is missing or empty.
- `Systems/AbilitySystem.luau` — dash mechanic for safe players (Q key).

### Client (`src/StarterPlayerScripts/`)

- `Main.client.luau` — bootstrap. Inits `DashController`, `UIController`, `KillFeedController`.
- `Controllers/UIController.luau` — reads phase/stage/player-state remotes, renders RichText into two labels: `Game.StatusFrame.Status` (main announcements + stage) and `Game.SecondaryStatus.Secondary` (timer + alive count).
- `Controllers/KillFeedController.luau` — listens to `KillFeed` remote, clones `Game.ID_Objects.KillData` into `Game.Killfeed` per kill, animates entrance/exit (TweenService), maintains a queue.
- `Controllers/DashController.luau` — sends `DashRequest` on Q.

### Character (`src/StarterCharacterScripts/`)

- `Health.client.luau` — empty override of Roblox's default Health script. Disables passive HP regen so damage from burners persists between encounters.

### Shared (`src/ReplicatedStorage/`)

- `Shared/Constants.luau` — all tunables (round/stage timing, damage rates, radii, walkspeeds, tag names, state strings).
- `Shared/Types.luau` — Luau type aliases (currently lightly used).

### Remotes (`ReplicatedStorage.Remotes`)

The `Remotes` folder lives in Studio (not Rojo source); it is preserved across syncs because `ReplicatedStorage` has `ignoreUnknownInstances: true`.

- `RoundStateChanged` (RemoteEvent) — server broadcasts `(phase, duration?, extra?)`. During `Round`, `extra` is `{ stage = 1|2|3 }`. At `End`, `extra` is `{ winner, reason }`.
- `PlayerStateChanged` (RemoteEvent) — server broadcasts `(player, state)`.
- `DashRequest` (RemoteEvent) — client → server.
- `KillFeed` (RemoteEvent) — server broadcasts `(killerName?, victimName)` per conversion. **Auto-created** by `RoundManager.init()` if not already present.
- `InfectionProgress` (RemoteEvent) — legacy; no longer fired (kept to avoid Studio-side cleanup).

### GUI structure (`PlayerGui.Game`, a ScreenGui authored in Studio)

- `StatusFrame.Status` (TextLabel) — main HUD line. Stage info during round, "GET READY!" / winner banner otherwise. RichText, all uppercase.
- `SecondaryStatus.Secondary` (TextLabel) — secondary HUD line. Timer + `safe/total` alive count joined by ` | `.
- `Killfeed` (Frame) — kill feed entries are parented here.
- `ID_Objects.KillData` (TextLabel) — template cloned per kill into `Killfeed`. Hidden by default; `Visible = true` set on the clone.

## Round Flow

`Lobby → Intermission (10s) → Round (90s, 3 × 30s stages) → End (5s) → Lobby`

`gameLoop` loads the map **before** broadcasting `Intermission`. If the map fails to load (no `ServerStorage.Maps`, or it's empty), it warns and stays in the `Lobby` phase instead of getting stuck cycling through intermission.

`endRound` order is important: stop systems → teleport everyone to lobby → unload map → THEN broadcast `End` and wait `END_TIME`. The map disappears the instant the round ends; players watch the announcement from the lobby.

### Stages (within Round phase)

| Stage | Duration | Behavior |
|-------|----------|----------|
| 1 (TAG) | 0–30s | Proximity damage only — 10 HP/s within 8 studs of a burner. |
| 2 (TRAILS) | 30–60s | Adds: each burner emits a continuous flame `ParticleEmitter`, and an invisible hazard part is dropped at their feet every 0.25s. Hazard parts last 5s and deal 5 HP/s within 4 studs. |
| 3 (INFERNO) | 60–90s | Adds: anything a burner physically touches catches fire for 5s (4-stud, 5 HP/s), unless tagged `Fireproof` or part of a player character. |

### Conversion rule

Players are **never killed**. When a safe player's HP reaches 0:
- HP is restored to `MaxHealth`.
- `InfectionSystem.PlayerInfected` fires; `RoundManager.onPlayerInfected` calls `setBurning(player, withGrace=true)` and fires `KillFeed:FireAllClients(killerName, victimName)`.
- `Humanoid.BreakJointsOnDeath` is set `false` on every spawn so a 0-HP frame never triggers ragdoll.

The killer name is `nil` when the kill came from a hazard (trail/ignited part) — the kill feed renders that as `"Victim burned"` instead of `"Killer burned Victim"`.

### Grace period

A freshly converted burner gets `NEW_BURNER_GRACE` (1.0s) before they appear in the burner list, preventing instant-cascade infection.

## Visual identity (per burner)

Set up by `RoundManager.setBurning` on conversion and torn down by `setSafe`/`setLobby`:

- **`BurnFire`** — `Fire` instance on the burner's torso (visible flames on the body).
- **`BurnOutline`** — `Highlight` named `BurnOutline`, orange (`255,130,0`), `FillTransparency = 1` (outline-only), `DepthMode = AlwaysOnTop`. Lets safe players spot burners through walls.

`FireSpreadSystem` adds two more, only during stages 2/3:

- **Trail emitter** — `ParticleEmitter` named `TrailEmitter` on a foot-level `Attachment` named `TrailEmitterPoint` under `HumanoidRootPart`. `LockedToPart = false` so particles stay world-positioned as the burner walks. On detach, `Enabled = false` first; instance destroyed 2.5s later so live particles can finish.
- **Touched listeners** — Stage 3 only. One per `BasePart` of the burner's character.

## Map Authoring

Maps live in `ServerStorage.Maps` (each is a `Model`). At runtime they are cloned into `Workspace.LoadedMap` (a Folder created on demand). `MapManager.unloadMap()` destroys the whole folder, so even if the `currentMap` reference is lost no orphan parts can survive.

Required structure inside each map Model:
- `SpawnPoints/` folder containing `BasePart`s named `SpawnPoint`.

For Stage 3 to behave correctly, **tag any part that should NOT catch fire** with the `Fireproof` CollectionService tag (typically: ground, walls, large terrain). Untagged parts will ignite when a burner touches them. This is opt-out by design — most props should burn.

## Hazard System

`FireSpreadSystem` creates two kinds of damage hazards, both registered with `InfectionSystem.registerHazard(part, radius)`:

- **Trail hazards** — fully invisible (`Transparency = 1`, no `Fire` child) parts placed under `Workspace.FireHazards`. Pure damage hitboxes. Visual fire is provided separately by the per-burner `ParticleEmitter`.
- **Ignited parts** — `Fire` instance added directly to the touched map part. Fire is removed after `IGNITE_DURATION`; the part itself is left intact.

Both deal `HAZARD_DAMAGE_PER_SEC` (half of direct burner damage). Direct burner contact takes priority over hazards in the damage check.

`FireSpreadSystem.stop()` (called from `endRound`) destroys the hazard folder, clears any lingering ignited fires from map geometry, and detaches all per-burner trail emitters and Touched listeners.

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
- Need a new RemoteEvent? Either create it in Studio under `ReplicatedStorage.Remotes`, or programmatically `Instance.new` it in a server `init()` if it doesn't exist (see `RoundManager.init()` for `KillFeed` as the reference pattern).
- UI text colors: use `colorize(color, text)` helper in `UIController` to wrap text in RichText `<font>` tags. Both labels have `RichText = true` set automatically on first resolve.

## Testing

In Studio, use **Test → Local Server → 2 Players** for end-to-end testing. To shorten iteration, temporarily lower `STAGE_DURATION` and `ROUND_TIME` in `Constants.luau`.

Quick smoke checklist after changes:
1. Round starts, Status frame shows "STAGE 1/3 — TAG" → "STAGE 2/3 — TRAILS" → "STAGE 3/3 — INFERNO" at the right times (color shifts yellow → orange → red).
2. Secondary frame shows `1:30  |  2/3` (timer flips red below 30s).
3. Standing in burner range drains the default health bar at ~10 HP/s; moving away stops the drain (no regen).
4. HP hitting 0 swaps the player to burning — no death animation, no respawn. Kill feed shows `"Killer burned Victim"`.
5. Stage 2: continuous flame ribbon visible behind burners; safe players walking through it take ~5 HP/s.
6. Stage 3: burner brushes a prop → prop ignites; brushes a `Fireproof`-tagged wall → nothing.
7. All burners visibly outlined orange (visible through walls).
8. Round end clears all trail parts, ignited fires, hazard folder, **and the cloned map** (`Workspace.LoadedMap` is gone).

If you start the server and immediately hear the intermission countdown loop forever, check Output for `MapManager: ServerStorage.Maps ...` warnings — that's the cause.
