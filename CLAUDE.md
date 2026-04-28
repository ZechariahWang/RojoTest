# CLAUDE.md

Project context for Claude Code when working in this Roblox game.

## Project: Burn Rush

A round-based Roblox tag-style game. One player starts "burning" and converts others by proximity. Built with Rojo + Luau.

- **Rojo project**: `default.project.json` (services map to `src/<Service>/`)
- **Toolchain**: `aftman.toml`
- **Scripts**: Luau (`.luau` ModuleScript, `.server.luau` Script, `.client.luau` LocalScript)
- **Style**: Functional modules (no OOP). Each system is a table with `init()` and public functions.

## Architecture

### Server (`src/ServerScriptService/`)

- `Main.server.luau` — bootstrap. Requires and `init()`s every system in this order:
  `PlayerState → MapManager → AbilitySystem → InfectionSystem → FireSpreadSystem → RoundManager`
- `Systems/PlayerState.luau` — per-player state (`Lobby` / `Safe` / `Burning`). Replicates via `PlayerStateChanged` RemoteEvent. Exposes `StateChanged` BindableEvent.
- `Systems/RoundManager.luau` — game loop and round lifecycle. Owns the phase state machine and the 3-stage in-round progression.
- `Systems/InfectionSystem.luau` — damage-over-time engine. Iterates safe players each Heartbeat, applies damage from any in-range burner or registered hazard. When HP hits 0, fires `PlayerInfected` and restores HP.
- `Systems/FireSpreadSystem.luau` — owns Stage 2 fire trails and Stage 3 touch-ignition. Both create flaming parts and register them as hazards with `InfectionSystem`.
- `Systems/MapManager.luau` — clones map from `ServerStorage.Maps`, manages spawn points and lobby teleport.
- `Systems/AbilitySystem.luau` — dash mechanic for safe players (Q key).

### Client (`src/StarterPlayerScripts/`)

- `Main.client.luau` — bootstrap. Inits `DashController` and `UIController`.
- `Controllers/UIController.luau` — reads phase + stage + player-state remotes, renders status text into `PlayerGui.Game.StatusFrame.Status`.
- `Controllers/DashController.luau` — sends `DashRequest` on Q.

### Character (`src/StarterCharacterScripts/`)

- `Health.client.luau` — empty override of Roblox's default Health script. Disables passive HP regen so damage from burners persists between encounters.

### Shared (`src/ReplicatedStorage/`)

- `Shared/Constants.luau` — all tunables (round/stage timing, damage rates, radii, walkspeeds, tag names, state strings).
- `Shared/Types.luau` — Luau type aliases (currently lightly used).

### Remotes (`ReplicatedStorage.Remotes`)

Created in Studio (not in Rojo source). Required at runtime via `WaitForChild`:

- `RoundStateChanged` (RemoteEvent) — server broadcasts `(phase, duration?, extra?)`. During `Round`, `extra` is `{ stage = 1|2|3 }`. At `End`, `extra` is `{ winner, reason }`.
- `PlayerStateChanged` (RemoteEvent) — server broadcasts `(player, state)`.
- `DashRequest` (RemoteEvent) — client → server.
- `InfectionProgress` (RemoteEvent) — legacy; no longer fired (kept to avoid Studio-side cleanup).

## Round Flow

`Lobby → Intermission (10s) → Round (90s, 3 × 30s stages) → End (5s) → Lobby`

### Stages (within Round phase)

| Stage | Duration | Behavior |
|-------|----------|----------|
| 1     | 0–30s    | Proximity damage only (10 HP/s within 8 studs of a burner). |
| 2     | 30–60s   | Adds: burners drop a fire trail every 0.25s; trail parts last 5s and deal 5 HP/s within 4 studs. |
| 3     | 60–90s   | Adds: anything a burner physically touches catches fire for 5s (4-stud radius, 5 HP/s), unless tagged `Fireproof` or part of a player character. |

### Conversion rule

Players are **never killed**. When a safe player's HP would reach 0:
- HP is restored to `MaxHealth`.
- `InfectionSystem.PlayerInfected` fires; `RoundManager.onPlayerInfected` calls `setBurning(player, withGrace=true)`.
- `Humanoid.BreakJointsOnDeath` is set `false` on every spawn so a 0-HP frame never triggers ragdoll.

### Grace period

A freshly converted burner gets `NEW_BURNER_GRACE` (1.0s) before they appear in the burner list, preventing instant-cascade infection.

## Map Authoring

Maps live in `ServerStorage.Maps` (each is a `Model`). Required structure:
- `SpawnPoints/` folder containing `BasePart`s named `SpawnPoint`.

For Stage 3 to behave correctly, **tag any part that should NOT catch fire** with the `Fireproof` CollectionService tag (typically: ground, walls, large terrain). Untagged parts will ignite when a burner touches them. This is opt-out by design — most props should burn.

## Hazard System

`FireSpreadSystem` creates two kinds of hazards, both registered with `InfectionSystem.registerHazard(part, radius)`:

- **Trail parts** — anchored neon parts placed under `Workspace.FireHazards` folder. Self-destruct after `TRAIL_DURATION`.
- **Ignited parts** — `Fire` instance added directly to the touched map part. Fire is removed after `IGNITE_DURATION`; the part itself is left intact.

Both deal `HAZARD_DAMAGE_PER_SEC` (half of direct burner damage). Direct burner contact takes priority over hazards in the damage check.

`FireSpreadSystem.stop()` (called from `endRound`) destroys the hazard folder and clears any lingering ignited fires from map geometry.

## Conventions

- New tunables go in `Constants.luau`. Don't hardcode magic numbers in systems.
- New cross-system signals: prefer `BindableEvent` over polling. Existing examples: `PlayerState.StateChanged`, `InfectionSystem.PlayerInfected`.
- Server creates Workspace instances; they replicate to clients automatically. No need for a remote for visual effects.
- Per-frame work goes through `RunService.Heartbeat` (server) or `RenderStepped` (client).
- Phase changes broadcast via the existing `RoundStateRemote` `extra` payload — add fields rather than creating new remotes for round metadata.

## Testing

In Studio, use **Test → Local Server → 2 Players** for end-to-end testing. To shorten iteration, temporarily lower `STAGE_DURATION` and `ROUND_TIME` in `Constants.luau`.

Quick smoke checklist after changes:
1. Round starts, UI shows "STAGE 1/3" → "STAGE 2/3" → "STAGE 3/3" at the right times.
2. Standing in burner range drains the default health bar at the expected rate; moving away stops the drain (no regen).
3. HP hitting 0 swaps the player to burning — no death animation, no respawn.
4. Stage 2 trails appear behind burners and damage safe players who walk through them.
5. Stage 3 burner-touch ignites props but not `Fireproof`-tagged terrain.
6. Round end clears all trail parts and ignited fires; `Workspace.FireHazards` is gone.
