# 🏒 Phys Hockey

**A fast, physics-driven 3v3 hockey game for Roblox.** You control your skater and your stick separately: swing it, charge shots, lift the puck, pass, check, and dash. Every puck bounce comes from a custom physics simulation I wrote, not Roblox's built-in physics.

> 🚧 **Work in progress:** Phys Hockey isn't published on Roblox yet, but it's close. A play link is coming soon.

---

## Ways to play

| Mode | What it is |
| --- | --- |
| **Quick Play** | Online 3v3 matches (5-minute games with overtime). Empty spots are filled by AI bots, including a bot goalie. |
| **Training** | A seven-drill tutorial (skate, dash, swing, dribble, pass, shoot, beat the goalie), then free practice. |
| **The Pond** | A shared open world on a frozen lake: an open rink for pickup games plus mini-games (**target shooting**, a **cone slalom**, and a **hardest-shot** challenge). |

## Highlights

### Custom physics engine
- **The whole game runs on [`Sim.lua`](src/ReplicatedStorage/Shared/Sim.lua)**, a deterministic simulation in pure Luau that runs at a fixed 60 ticks per second. Roblox parts are only for looks, so a cosmetic can never change a hitbox.
- **Realistic stick handling**: a soft-hands catch, charged shots (from 72 to 140 speed), lofted shots, stick-on-stick contact, poke checks, and body checks that knock skaters off balance.
- **No tunnelling**: the puck can't pass through sticks or boards at high speed.

### Competitive multiplayer netcode
- **Server-authoritative**: clients only send stick and skate input. They never send positions, scores, or purchases.
- **Client-side prediction and reconciliation** ([`Prediction.lua`](src/StarterPlayer/StarterPlayerScripts/Client/Prediction.lua)): your own skater responds instantly by running the same `Sim` code the server runs.
- **Compact binary protocol** ([`Protocol.lua`](src/ReplicatedStorage/Shared/Protocol.lua)): state is packed into fixed-size buffers that are sent 60 times a second. The Pond's 16 skaters and 40 pucks fit in under 1,000 bytes.
- **Anti-exploit guard** ([`SecurityService.lua`](src/ServerScriptService/Systems/SecurityService.lua)): every remote is rate-limited with token buckets and its packets are shape-checked.

### AI bots
- **[`BotBrain.lua`](src/ReplicatedStorage/Shared/BotBrain.lua)**: bots play under exactly the same rules as people. They send the same input a player would, with the same aim limits and cooldowns, so they can't cheat.
- **Field players and goalies**, with a slow think rate so server cost stays flat.

### Presentation
- **TV-style goal replays** ([`Replay.lua`](src/StarterPlayer/StarterPlayerScripts/Client/Replay.lua)): a spotlight celebration, a slash-wipe transition, slow-motion broadcast and net-cam angles, and vote-to-skip.
- **X-ray view** ([`Xray.lua`](src/StarterPlayer/StarterPlayerScripts/Client/Xray.lua)): when the puck or your stick is hidden behind a skater or the boards, the blocked part is drawn in yellow.
- **Three rinks** (Arena, Night, and the Pond) plus a locker-room lobby, all built in code.
- **An original cartoon skater** made from primitives, with a lean into turns and stick wind-up and follow-through animations.
- **Keyboard and mouse, gamepad, and touch** controls, with on-screen prompts that name the buttons on the device you're using.

### Progression and live-ops
- **Ranked ELO** from Bronze to Champion, with emblems drawn in code.
- **50-tier Season Pass** with free and premium tracks.
- **Daily challenges** and a **7-day login streak**.
- **A shop of cosmetics bought with coins earned in-game**: hats, hair, faces, outfits, back items, and sticks (a plasma saber, a baguette, a spatula, and more).
- **A Mystery Box** that shows its odds before you buy and follows Roblox's rules for paid random items.
- **Global top-50 leaderboards**.
- **Data saved safely** ([`ProfileManager.lua`](src/ServerScriptService/Data/ProfileManager.lua)): session-locked profiles, versioned save migrations, and protection against losing or duplicating data.

### Testing
- **Automated tests** ([`SimTests.lua`](src/ServerStorage/Tests/SimTests.lua)) run headless at the start of every Studio playtest.

---

## Code layout

The folders mirror the game's layout in Roblox Studio. About 46 scripts and 32,000 lines of Luau, most of it in `--!strict` typed mode.

```
src/
├── ReplicatedStorage/Shared/      # code shared by server and client
│   ├── Sim.lua                    # the physics and game model
│   ├── GameConfig.lua             # every tuning number in one place
│   ├── Protocol.lua               # binary network format
│   ├── BotBrain.lua               # AI players
│   ├── ArenaBuilder.lua           # builds the rinks and lobby
│   ├── Looks.lua, Catalog.lua     # the skater model and all cosmetics
│   └── SeasonPass, Rank, Challenges, LoginRewards, MysteryBox ...
├── ServerScriptService/
│   ├── Main.server.lua            # server loop: runs the world and validates input
│   ├── Systems/                   # Match, Team, Pond, Ranking, Season, Store, Security
│   └── Data/                      # player saves (ProfileManager, Schema, PlayerData)
├── ServerStorage/Tests/           # SimTests
└── StarterPlayer/StarterPlayerScripts/
    ├── Main.client.lua            # client entry: input, prediction, drawing
    └── Client/                    # HUD, menus, camera, replays, training, X-ray ...
```

> These are the scripts only. Meshes, models, and other assets live in the Roblox place file.

## Built with

Roblox Studio · Luau (strict typing) · DataStoreService · MarketplaceService
