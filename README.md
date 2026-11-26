# Game Development

Games I've designed and built: a browser geography game with a Windows desktop app, and two multiplayer Roblox games.

| Game | Platform | Genre | Code | Play |
| --- | --- | --- | --- | --- |
| [🏒 Phys Hockey](#-phys-hockey) | Roblox | Physics sports, 3v3 | [`phys-hockey/`](phys-hockey/) | 🚧 In development, launching soon |
| [🎤 Clamillion](#-clamillion) | Roblox | Game-show trivia | [`clamillion/`](clamillion/) | [Play on Roblox](https://www.roblox.com/games/109597980629770/CLAMILLION-Trivia-Game-Show) |
| [🌍 Worldbound](#-worldbound) | Web + Windows | Geography / exploration | [`worldbound/`](worldbound/) | [Play in browser](https://worldbound-explorer.grantexec-0223.chatgpt.site) |

---

## 🏒 Phys Hockey

> 🚧 **Work in progress:** not published on Roblox yet, but close!

**A fast, physics-driven 3v3 hockey game.** You control your skater and stick separately to swing, charge shots, lift the puck, pass, and check. Every bounce comes from a custom physics engine instead of Roblox's built-in physics.

- **Custom physics simulation** in pure Luau, running at a fixed 60 ticks per second
- **Competitive netcode**: a server-authoritative design, client-side prediction, and a compact binary protocol
- **AI bots** (field players and goalies) that play under the same rules as people
- **TV-style goal replays**, an X-ray view of hidden pucks, and three rinks
- **The Pond**: a shared open world with pickup games and mini-games
- **Progression**: ranked ELO, a 50-tier season pass, daily challenges, and a cosmetics shop

📖 [Full write-up →](phys-hockey/README.md) · about 46 scripts and 32,000 lines of strict-typed Luau

---

## 🎤 Clamillion

**A game-show trivia game where the rarest answer wins.** Answer "Name an animal that starts with K" with "Kangaroo" for 10 points, or "Kouprey" for 100.

- **Solo, 1v1, and 1v1v1** shows with three rounds, a talking host, and a cheering studio audience
- **Smart answer checking** that handles typos, plurals, nicknames, Roman numerals, and "Did you mean…?" prompts
- **A lobby** with a mini obby, a cross-server daily leaderboard, a Daily Wheel, and ad boards
- **A shop** with 10 podium themes, 6 arenas, titles, emotes, and a Mystery Box
- **A Halloween live event** that turned itself on and off on schedule
- **A kid-safe profanity filter**

🎮 [Play on Roblox](https://www.roblox.com/games/109597980629770/CLAMILLION-Trivia-Game-Show) · 📖 [Full write-up →](clamillion/README.md) · about 30 scripts and 9,000 lines of Luau

---

## 🌍 Worldbound

**Drop into a random spot on Earth, look around in Google Street View, and guess where you are on the map.** The closer your guess, the more points you score.

📁 Source: [`worldbound/`](worldbound/) · 🎮 [Play in your browser](https://worldbound-explorer.grantexec-0223.chatgpt.site) · 💻 Windows app instructions in [`worldbound/START-HERE.txt`](worldbound/START-HERE.txt)

### Game modes

| Mode | How it works |
| --- | --- |
| **World** | Five Street View rounds anywhere across 97 countries. Up to 5,000 points per round, 25,000 total. |
| **Streaks** | Name the correct country as many times in a row as you can. One wrong guess or timeout ends the run. |
| **Daily** | One shared challenge per day (resets at midnight Eastern). Five city-focused rounds; unfinished runs can be resumed. |
| **Custom Map** | Search for any continent, country, state, or city and play five rounds restricted to that area. |

### Highlights

- **Distance-based scoring** using great-circle distance, with end-of-game medals: Bronze, Silver, Gold, and Platinum for a perfect 25,000.
- **3-minute timed rounds** with a capsule timer and a pulsing red screen-edge warning in the final 20 seconds (with a reduced-motion alternative).
- **Animated 3D home screen**: a rotating Earth built with Three.js, a hovering map pin with a moving shadow, and twinkling stars.
- **Custom HUD**: a compass synced to Street View, a five-round score strip, and an expandable guessing map with animated pins.
- **Round results map** showing every guess connected to its real location with dotted lines.
- **Smart location picking** that spreads rounds across countries and skips dead-end spots where you can't move around.
- **Custom Map boundaries** built from real OpenStreetMap region outlines, including regions with holes.
- **Windows desktop app** packaged with Electron so friends can play by double-clicking an `.exe`. It runs sandboxed and has fullscreen (F11) and reconnect (Ctrl+R) shortcuts.

### Built with

React 19 · TypeScript · Three.js · Google Maps & Street View APIs · Cloudflare Workers + D1 (SQL database) · OpenStreetMap · Electron
