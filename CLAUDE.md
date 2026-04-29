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
- `Systems/FireSpreadSystem.luau` — owns Stage 2 fire-wall trails and Stage 3 touch-ignition. Wall segments are visible Neon parts with flame `ParticleEmitter`s — they double as the visual and the damage hitbox.
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

- `RoundStateChanged` (RemoteEvent) — server broadcasts `(phase, duration?, extra?)`. During `Reveal`, `extra` is `{ burner = name }`. During `Round`, `extra` is `{ stage = 1|2|3 }`. At `End`, `extra` is `{ winners = { name, ... }, reason }` — `winners` may be empty (everyone burned / aborted).
- `PlayerStateChanged` (RemoteEvent) — server broadcasts `(player, state)`.
- `DashRequest` (RemoteEvent) — client → server.
- `KillFeed` (RemoteEvent) — server broadcasts `(killerName?, victimName)` per conversion. **Auto-created** by `RoundManager.init()` if not already present.
- `InfectionProgress` (RemoteEvent) — legacy; no longer fired (kept to avoid Studio-side cleanup).

### GUI structure (`PlayerGui.Game`, a ScreenGui authored in Studio)

- `StatusFrame.Status` (TextLabel) — main HUD line. Stage info during round, "GET READY!" during intermission, `"<NAME> IS BURNING!"` during reveal, winner banner at end (1 / 2 / `N PLAYERS` formats). RichText, all uppercase.
- `SecondaryStatus.Secondary` (TextLabel) — secondary HUD line. Timer + `safe/total` alive count joined by ` | `.
- `Killfeed` (Frame) — kill feed entries are parented here.
- `ID_Objects.KillData` (TextLabel) — template cloned per kill into `Killfeed`. Hidden by default; `Visible = true` set on the clone.

## Round Flow

`Lobby → Intermission (10s) → Reveal (6s) → Round (90s, 3 × 30s stages) → End (5s) → Lobby`

`gameLoop` loads the map **before** broadcasting `Intermission`. If the map fails to load (no `ServerStorage.Maps`, or it's empty), it warns and stays in the `Lobby` phase instead of getting stuck cycling through intermission.

**Reveal phase** is a no-damage grace window between teleport-to-arena and the actual round. The initial burner has been chosen and gets the visible fire + outline so everyone can see who they are; safe players use the time to position themselves. `InfectionSystem` and `FireSpreadSystem` are deliberately NOT started until reveal ends, so no damage, walls, or ignition can happen during it.

`endRound` order is important: stop systems → **heal everyone to MaxHealth** → teleport everyone to lobby → unload map → THEN broadcast `End` and wait `END_TIME`. The map disappears the instant the round ends; players watch the announcement from the lobby with full HP.

The round does **not** end early when only one safe player remains — the timer must run out. A round only ends early if (a) every safe player is converted (`AllInfected`), or (b) the player count drops below `MIN_PLAYERS` (`Aborted`). When the timer runs out, **every** remaining safe player is a winner.

### Stages (within Round phase)

| Stage | Duration | Behavior |
|-------|----------|----------|
| 1 (TAG) | 0–30s | Proximity damage only — 10 HP/s within 8 studs of a burner. |
| 2 (TRAILS) | 30–60s | Adds: each burner leaves a continuous **fire wall** behind them. Tall (6 studs), thin Neon segments are dropped between successive foot positions whenever the burner moves at least `TRAIL_SEGMENT_MIN_LENGTH` studs. Walls last 5s and deal 5 HP/s to anything within `TRAIL_RADIUS` of the wall surface (≈ "touching it"). |
| 3 (INFERNO) | 60–90s | Adds: anything a burner physically touches catches fire **for the rest of the round** (4-stud, 5 HP/s) — ignited parts never extinguish until `endRound`. Does not apply to parts with a `Fireproof` `BoolValue` child set to `true`, or to player characters. |

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
- Need a new RemoteEvent? Either create it in Studio under `ReplicatedStorage.Remotes`, or programmatically `Instance.new` it in a server `init()` if it doesn't exist (see `RoundManager.init()` for `KillFeed` as the reference pattern).
- UI text colors: use `colorize(color, text)` helper in `UIController` to wrap text in RichText `<font>` tags. Both labels have `RichText = true` set automatically on first resolve.

## Testing

In Studio, use **Test → Local Server → 2 Players** for end-to-end testing. To shorten iteration, temporarily lower `STAGE_DURATION` and `ROUND_TIME` in `Constants.luau`.

Quick smoke checklist after changes:
1. Round starts, Status frame shows "STAGE 1/3 — TAG" → "STAGE 2/3 — TRAILS" → "STAGE 3/3 — INFERNO" at the right times (color shifts yellow → orange → red).
2. Secondary frame shows `1:30  |  2/3` (timer flips red below 30s).
3. Standing in burner range drains the default health bar at ~10 HP/s; moving away stops the drain (no regen).
4. HP hitting 0 swaps the player to burning — no death animation, no respawn. Kill feed shows `"Killer burned Victim"`.
5. Stage 2: tall fire walls trail behind moving burners and stay around for ~5 seconds; safe players who walk into one take ~5 HP/s.
6. Stage 3: burner brushes a prop → prop ignites with flames visible on **every face** and stays burning for the rest of the round; brushes a wall with a `Fireproof` `BoolValue` child (`Value = true`) → nothing.
7. All burners visibly outlined orange (visible through walls).
8. Round end clears all trail walls, ignited fires, hazard folder, **and the cloned map** (`Workspace.LoadedMap` is gone).

If you start the server and immediately hear the intermission countdown loop forever, check Output for `MapManager: ServerStorage.Maps ...` warnings — that's the cause.
