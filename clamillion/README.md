# 🎤 Clamillion

**A game-show trivia game for Roblox where the rarest answer wins.** Step onto the stage, hear the host read the question, and type any correct answer you can think of. Everyone knows "Kangaroo," but "Kouprey" is worth ten times as much.

🎮 **[Play Clamillion on Roblox](https://www.roblox.com/games/109597980629770/CLAMILLION-Trivia-Game-Show)**

---

## How it plays

- **Pick a mode** by standing on a pad in the lobby: **Solo**, **1v1**, or **1v1v1**.
- **Three rounds of five questions.** Each question gives you 30 seconds to answer, and you can keep trying until you find a right answer.
- **Score by rarity:**

| Tier | Points |
| --- | --- |
| Common | 10 |
| Too Clever | 15 |
| Uncommon | 30 |
| Rare | 60 |
| Very Rare | 85 |
| Extremely Rare | 100 |

- **Tiebreakers** settle close games, and the winner gets a trophy, confetti, and a victory emote on stage.

## Highlights

### Smart answer checking
**[`AnswerValidationService.lua`](src/ServerScriptService/Clamillion/Services/AnswerValidationService.lua)** turns whatever a player types into the right answer:
- It ignores capitals, accents, punctuation, spacing, "&" vs. "and," and a leading "The."
- It understands number words and Roman numerals ("Rocky IV" = "Rocky 4," "Toy Story Two" = "Toy Story 2").
- It accepts plurals, nicknames, abbreviations, and alternate spellings.
- Typos get a **"Did you mean…?"** prompt for the player to confirm.

### The show
- **A talking host** voiced with Roblox text-to-speech, with timing matched to each line.
- **A full studio audience**: hundreds of individually dressed fans, animated cheaply in bulk ([`CrowdBuilder.lua`](src/ReplicatedStorage/Clamillion/Shared/CrowdBuilder.lua)).
- **A big question screen and lit-up podiums**, driven by a server-run show state machine ([`MatchService.lua`](src/ServerScriptService/Clamillion/Services/MatchService.lua)).
- **Fresh questions every time**: players never see a repeat until they've played through the whole question bank ([`QuestionService.lua`](src/ServerScriptService/Clamillion/Services/QuestionService.lua)).

### The lobby
- **A mini obby** with checkpoints, lava, a spinning bar, and a **"fastest today" leaderboard** shared across every server ([`ObbyService.lua`](src/ServerScriptService/Clamillion/Services/ObbyService.lua)).
- **A Daily Wheel** that resets every morning with title prizes.
- **Leaderboards** for Solo, 1v1, and 1v1v1, plus badges.
- **Animated ad boards** that advertise updates and shop items.

### Shop and customization
- **10 podium themes** (Unicorn, Dino, Galaxy, and more), **6 arenas** (Classic, Aquarium, Candy, Jungle, Space, Winter), **titles**, and **victory emotes**.
- **3D shop previews** that use the same code as the real stage, so what you see is what you get.
- **A Mystery Box** with its odds always shown before purchase.
- **Purchases and inventory saved** with DataStores, with receipts handled safely.

### Live events
- **A limited-time Halloween event** that switched on and off by itself on schedule. It repainted the lobby, added flying witches, bats, ghosts, and dancing skeletons, and offered event rewards ([`HalloweenEvent.lua`](src/ServerScriptService/Clamillion/Services/HalloweenEvent.lua)).

### Kid-safe
- **A profanity filter** ([`Profanity.lua`](src/ReplicatedStorage/Clamillion/Shared/Profanity.lua)) that stars out bad words everywhere they could show up (while typing, in reveals, and in recaps), including leetspeak like "sh1t," without blocking innocent words.

---

## Code layout

The folders mirror the game's layout in Roblox Studio. About 30 scripts and 9,000 lines of Luau.

```
src/
├── ServerScriptService/Clamillion/
│   ├── Main.server.lua            # server entry point
│   ├── Config.lua                 # modes, rounds, timing, scoring tiers
│   └── Services/                  # Match, Question, AnswerValidation, Stage, Queue,
│                                  # Shop, Lobby, Obby, Badges, Halloween event ...
├── ReplicatedStorage/Clamillion/Shared/
│   ├── ArenaThemes.lua            # the 6 arena looks
│   ├── PodiumThemes.lua           # the 10 podium themes
│   ├── CrowdBuilder.lua           # the studio audience
│   ├── ShopCatalog.lua            # everything players can own
│   └── Profanity, EmotePlayer, Events, UIConstants ...
├── ServerStorage/ClamillionData/
│   └── QuestionBank.lua           # question loader (the question data isn't included)
└── StarterPlayer/StarterPlayerScripts/
    ├── ClamillionClient.client.lua   # all UI and presentation
    ├── MysteryBoxClient.client.lua
    └── HalloweenLobbyFX.client.lua
```

> These are the scripts only. The question data, the lobby and studio builds, and other assets live in the Roblox place file.

## Built with

Roblox Studio · Luau · DataStoreService · MessagingService · MarketplaceService · Text-to-Speech
