# Worldbound — project handoff for the next LLM

## October 1, 2026 access and packaging update

The user requested that anyone with the downloaded files can play without a
ChatGPT login. The existing Site access was changed from custom to public using
Sites (access revision 2). An anonymous HTTP request returned 200 with Worldbound
content and no login redirect. No bypass token or owner session is distributed.
The desktop wrapper is version 1.0.1, with current launch instructions and only
the game host trusted for in-app navigation. Run scripts/package-windows.ps1 to
build and verify release/Worldbound-Windows.zip from the bundled Windows runtime.
Internet and the hosted backend are still required. This supersedes the private
access and outstanding friend invitation statements in the historical handoff
below. Full Street View gameplay has not been re-tested in this update.

Last verified: September 30, 2026, America/New_York (October 1 UTC).

## 1. What this project is

Worldbound is a GeoGuessr-inspired geography game built iteratively with the user. Players explore Google Street View, place a guess on a Google map, and receive a round result. It has a hosted web application and an initial portable Windows desktop wrapper.

This document is a context handoff, not a request to implement additional changes. Read the current source before editing. Preserve the user's existing gameplay and visual choices. Do not restart the project or replace it with a generic template.

## 2. Current source and deployment

| Item | Value |
| --- | --- |
| Live website | https://worldbound-explorer.grantexec-0223.chatgpt.site |
| Sites project ID | `appgprj_6ab34a05e2a48191a36aeebfb76d913e` |
| Latest verified published version | 24 |
| Latest verified source commit | `e0488b960c56a7c51db7f49ef78244ec9184aa39` |
| Source branch | `main` |
| Existing local checkout | `/workspace/sites/worldbound` |
| Git remote | `https://git.chatgpt-team.site/aebe16b1-6e4b-4b54-a437-9f0492684bbe/appgprj_6ab34a05e2a48191a36aeebfb76d913e.git` |
| Hosting | Sites, Cloudflare Worker, D1 |
| Access | Private: custom audience, one owner allowed; external invitations enabled |

The checkout was present and clean when this document was created. Workspace maintenance can remove local files. Restore website source through the existing Sites repository; do not create a replacement Site. IDs are opaque and must be copied exactly. Read the current hosting manifest and current Sites metadata before deployment.

## 3. User requirements to preserve

- Street View only. Photo mode was explicitly removed. Do not bring back static photo rounds, famous-place photo collections, or J. Hannan-Briggs photos.
- Use Google Maps for selecting guesses in every mode. No coordinate-entry fields.
- Default timed round is **3 minutes**. Final **20 seconds** trigger a red glow pulsing around the screen edges; reduced-motion users receive a static treatment.
- Choose diverse locations across the approved countries. The user disliked UK-heavy selection and locations with almost no movement.
- Location loading must be bounded and recoverable. Do not leave players indefinitely searching or trapped with an unusable panorama.
- No large top navigation bar during gameplay.
- Preserve the purple/dark-violet visual direction, rounded controls, Nunito/Lilita One typography, and green Guess/Next Round buttons. The user disliked the original dark-green theme, blocky panels, and basic Arial appearance.
- Do not infer new gameplay requirements from decorative elements in reference screenshots that the user said to ignore.

## 4. Game modes and rules

| Mode | Behavior |
| --- | --- |
| World | Five Street View rounds; distance-based scoring, up to 5,000 per round and 25,000 total. |
| Streaks | Guess the correct country. Correct guess adds exactly +1. Incorrect country, no guess, or timeout ends the streak. No distance-based points. |
| Daily | One run per saved player per day, reset at midnight America/New_York; five rounds, 180 seconds, moving mode, city-biased candidates. Unfinished runs can resume; completed runs cannot replay. |
| Custom Map | Search/select a continent, country, state, or city with a supported boundary; play five distance-scored rounds restricted to it. |

Home originally had only World, Streaks, and Daily. Custom Map was subsequently explicitly requested and is now the fourth mode; do not remove it based on the older three-mode request.

### Scoring and time

- `lib/game.ts` calculates great-circle distance in kilometers.
- Street View scoring calls `score(km, false)`: 5,000 at distance <=0.05 km; otherwise `round(5000 * exp(-km / 2000))`. Rounding can also produce 5,000 just beyond the threshold.
- Round-results UI converts kilometers to miles with `0.621371192237334`. Do not change stored distance units when changing display units.
- Timer starts only after the server accepts the selected panorama (`ready`). Loading time is not deducted.
- Server enforces deadline on submission. Expired guesses become null and score zero.
- Internal round index is zero-based; API/UI round is one-based.
- Game states are `active`, `result`, and `complete`.

### Daily limitations

The once-per-day rule is tied to the `wb_player` cookie, not a verified global account identity. Clearing cookies or using another browser/app profile creates another saved player. Daily uses a deterministic date seed and stored run; independently fetched Street View panoramas are not guaranteed to be identical for every player. Do not advertise strict account-wide anti-cheating or identical daily panoramas.

## 5. Current UI

### Home

- A rotating 3D Earth rendered with Three.js, with sunlight/glare and a larger shadowed lower portion.
- A red-and-white 3D map pin hovering above Earth. There is **no traveler character** anymore.
- The pin was lowered slightly at the user's request. It bobs slowly and turns gently left/right.
- Pin shadow changes spread/opacity as the pin moves closer/farther; shadow was enlarged slightly afterward.
- Floating/twinkling background stars.
- Preserve the established globe/pin appearance unless explicitly asked to change it.

### Mid-round

- Top center: compass coordinated with Street View facing direction, including N, NE, E, SE, S, SW, W, NW. Cardinal labels should not all appear highlighted.
- Below compass: small capsule/racetrack timer; purple perimeter stroke shrinks as time expires. Red treatment near expiry.
- Top right: compact purple five-round score strip with numbered pin shapes, current-round emphasis, completed scores, and total. Streaks has a corresponding streak display.
- Bottom right: compact translucent square-ish Google guessing map; it grows on hover. Size controls allow larger/smaller choices. Green Guess button sits slightly detached below and expands with the map.
- Hovering the guess-map surface shows a crosshair. Dragging shows a grabbing cursor; results map uses a grab cursor.
- Guess markers are small red/white pins with a brief placement animation.
- Street View navigation controls and Return to Start belong on the bottom left; do not confuse these with controls on the separate guessing map.

### After each round — latest requested layout

- Map occupies most of the screen.
- Round-by-round score strip remains at the **top right**, without a countdown timer.
- Bottom bar: **distance in miles on the left**, **green Next Round button in the middle**, **that round's score out of 5,000 on the right**.
- Distance has a blue glow; points have a warm orange glow, based on the supplied reference.
- Do not add the screenshot's bottom-left hint/photo card.
- Current map shows all completed guess/actual pairs, with straight black dotted lines (`geodesic: false`). It opens at a world-scale view rather than automatically fitting only the latest pair.
- No extra actual-location name text on the results screen; user explicitly removed it.
- After round five, the center button is **See results**. It opens final total/medal display.
- On narrow screens, the center button moves below the two metrics to fit.

### Final results

World/Daily/Custom final score uses these exact tiers:

| Medal | Total score |
| --- | --- |
| Bronze | 0–14,999 |
| Silver | 15,000–22,499 |
| Gold | 22,500–24,999 |
| Platinum | 25,000 |

Streaks does not receive a 25,000-point medal. When streaks ends, show Play Again and Return to Menu. Daily completion does not offer replay. Other completed games offer replay/menu. Preserve the final medal screen while changing per-round results.

## 6. Source map

| File | Responsibility |
| --- | --- |
| `app/page.tsx` | Main client state, settings, API calls, countdown, guesses, home/game flow, warning vignette. |
| `app/globals.css` | Most custom styling; contains historical rules and later overrides. Read the cascade before changing classes. |
| `components/home-screen.tsx` | Home mode selection and launch/settings UI. |
| `components/globe-scene.tsx` | Three.js Earth, hovering pin/shadow, stars. |
| `components/panorama.tsx` | Google loader, Street View search/rendering, heading callbacks, controls and recovery. |
| `components/heading-compass.tsx` | Direction compass. |
| `components/guess-map.tsx` | Google guess/results map, custom pins, dotted connecting lines, map cursor. |
| `components/round-hud.tsx` | Capsule timer and top-right score strip; `showTimer=false` on results. |
| `components/round-results.tsx` | Per-round footer, final result transition, medal thresholds, miles display. |
| `components/custom-map-picker.tsx` | Explicit place search, disambiguation, selection/boundary preparation. |
| `app/api/config/route.ts` | Reads hosted Google browser key and sends it to the client. |
| `app/api/game/route.ts` | Start/ready/guess/next/search-again, restore, daily availability, validation and persistence. |
| `app/api/coverage/route.ts` | Allowed-country and optional custom-boundary validation for panorama coordinates. |
| `app/api/custom-map/route.ts` | Place lookup and boundary-selection API. |
| `lib/game.ts` | Distance, scoring, seeded shuffling. |
| `lib/round-result.ts` | Round resolution, streak correctness and terminal state. |
| `lib/daily.ts` | New York date and daily game ID. |
| `lib/streetview-sampler.ts` | Approved countries, point-in-country, world/urban candidate sampling. |
| `lib/streetview-quality.ts` | Checks onward panorama movement. |
| `lib/streetview-search.ts` | Search helpers. |
| `lib/custom-regions.ts` | Built-in areas, OSM ring construction, region containment and candidate sampling. |
| `lib/custom-map-store.ts` | D1 cache, provider throttles, boundary fetch/validation. |
| `lib/land.json` | Natural Earth country geometry for approved countries. |
| `lib/urban-centers.json` | Daily city-center candidates. |
| `lib/store.ts` | D1 binding access. |
| `db/schema.ts`, `drizzle/` | Database schema and migrations. |
| `tests/custom-regions.cjs`, `tests/custom-game.cjs` | Boundary and game-flow regression checks. |

There is still historical/dead summary UI in `app/page.tsx`, historical CSS, and a legacy `photo` parameter name in the scoring helper. These are not evidence that photo mode is an active feature. Avoid reviving old branches inadvertently.

## 7. Architecture and persistence

- React 19 / TypeScript, Next-style app routes running through **Vinext + Vite** with Cloudflare Worker output.
- Node requirement in package: >=22.13.0. Package manager: pnpm; preserve `pnpm-lock.yaml` and existing framework scripts.
- `package.json` still has the starter package name; branding in the product is Worldbound.
- D1 binding is `DB`; no R2 binding currently.
- `games` table: `id`, `owner`, JSON `data`, integer `version`, `created_at`.
- `map_cache` table: `key`, JSON/string `data`, expiry timestamp `expires`.
- Ownership uses an HttpOnly `wb_player` cookie with SameSite=Lax and Secure on HTTPS.
- Game reads/writes check owner; writes use optimistic version checks.
- `?game=<id>` restores a game for the same saved player.
- `catalogVersion` is `streetview-countries-v2`; incompatible older sessions are rejected with restart guidance.
- POST routes check Origin when supplied.
- Client discovers Street View via Google's browser service, then posts panorama ID/coordinates. Server validates geographic constraints, candidate proximity, duplicates and round token. It does **not** independently authenticate panorama metadata against Google; this is not a hardened competitive anti-cheat system.

## 8. Location selection and custom maps

### World and Daily

World selects approved countries randomly, then polygon-weighted land samples within the chosen country. It generates batches of 100 candidates. This is **not uniform sampling of all Google panoramas**. Google's availability, nearby panorama lookup, and quality checks affect which locations succeed.

Daily uses urban-center candidates and a smaller search radius (5 km vs World 50 km). Search uses parallel workers and a bounded approximately 20-second search window. Road-quality checks require at least two exits and onward links from neighbors. Coverage can change, and some allowed countries may fail to produce usable locations.

### Custom Map

- Continents/countries use existing local country data and aliases.
- Cities/states use Photon search (`https://photon.komoot.io/api/`) and actual OpenStreetMap relation boundaries (`https://api.openstreetmap.org/api/0.6/relation/<id>/full.json`).
- No additional geocoding key was added.
- Search is submit-driven; do not issue public-provider requests on every keystroke.
- Search cache is 7 days; place/boundary caches generally 30 days. Provider throttles are shared through D1 at 2 seconds per provider.
- Remote JSON timeout is 25 seconds; response cap 12 MB. Relation geometry has a vertex limit and rejects unsupported/incomplete boundaries.
- Boundary assembly joins/reverses way fragments, handles outer/inner rings and holes, and refuses incomplete or unsupported nested relation boundaries. Date-line-crossing custom boundaries are rejected with broader-selection guidance.
- Result coordinates must remain inside the selected region **and** an approved country. The server rechecks actual panorama positions; a search radius crossing the border must not let an out-of-area panorama through.
- Unsupported boundary or insufficient coverage should show a useful retry/broader-area message.
- Continents include transcontinental countries according to the current country-based grouping; Europe is not a strict longitude-clipped geometric continent. Antarctica has no allowed countries.
- Do not promise that every named city/state works. Only supported administrative relations with usable Street View can work.
- Public provider suitability must be rechecked before significant scaling. Do not silently replace this with public Nominatim or Overpass: they were considered and rejected in the earlier implementation due to policy/availability constraints.

### Approved country list (97)

Albania, Andorra, Argentina, Australia, Austria, Bangladesh, Belgium, Bhutan, Bolivia, Botswana, Brazil, Bulgaria, Cambodia, Canada, Chile, Colombia, Costa Rica, Croatia, Cyprus, Czechia, Denmark, Dominican Republic, Ecuador, Estonia, Eswatini, Finland, France, Georgia, Germany, Ghana, Greece, Greenland, Guatemala, Hungary, Iceland, India, Indonesia, Ireland, Israel, Italy, Japan, Jordan, Kenya, Kyrgyzstan, Latvia, Lebanon, Lesotho, Liechtenstein, Lithuania, Luxembourg, Malaysia, Mexico, Mongolia, Montenegro, Namibia, Nepal, Netherlands, New Zealand, Nigeria, North Macedonia, Norway, Oman, Palestine, Panama, Paraguay, Peru, Philippines, Poland, Portugal, Qatar, Romania, Russia, Rwanda, San Marino, Senegal, Serbia, Singapore, Slovakia, Slovenia, South Africa, South Korea, Spain, Sri Lanka, Sweden, Switzerland, São Tomé and Príncipe, Taiwan, Thailand, Tunisia, Turkey, Uganda, Ukraine, United Arab Emirates, United Kingdom, United States, Uruguay, Vietnam.

This list is a user constraint, not a guarantee of currently available road coverage in every country. Preserve the source dataset and matching names.

## 9. Google Maps configuration

Hosted runtime variable: `GOOGLE_MAPS_BROWSER_KEY`.

A saved key already exists in the deployed environment. `/api/config` returns it for Google's browser SDK. The user wanted automatic connection without pasting it every session. A replacement typed into settings applies only to that tab.

**Do not put the key, repository credentials, session cookies, or Sites bypass tokens in this document, Git, logs, screenshots, or desktop packages.** Preserve the deployed key. A Google browser key is intentionally delivered to the browser and should be restricted through Google Cloud to the appropriate website/API. New origins or packaging changes may require reviewing referrer restrictions. Do not claim Google Maps usage is inherently free; imagery/API usage and billing remain with the configured Google project.

The desktop wrapper loads the existing HTTPS origin rather than copying the game into a `file://` page, which preserves the website's API origin and hosted backend.

## 10. Build, verification, and publication

Use current Sites skills/tools for actual hosting work. This README is not a substitute for their current instructions. A documentation handoff alone does not require changing or redeploying the website.

Useful commands from the website checkout:

```sh
npx tsc --noEmit --incremental false
npm run build
node tests/custom-regions.cjs
node tests/custom-game.cjs
git diff --check
```

- Existing build goes through `scripts/run-framework.mjs` and the established bounded framework build flow. Do not replace it with generic Next.js export instructions.
- Worker entrypoint: `dist/server/index.js`.
- Hosting metadata and migrations are packaged under `dist/.openai/` by the build integration.
- `npm run dev` and `npm start` use the project's managed framework/Wrangler flows; consult the current Sites preview instructions for this environment.
- Current tests use a TypeScript loader and, for game tests, Node's SQLite support. Use a runtime supporting the test imports; the minimum application Node version alone may not establish test compatibility.
- Optional actual Paris/Virginia fixture tests existed in prior scratch files. Those fixtures may be gone; default test runs must not depend on them.
- Do not print secrets when checking environment configuration.

### Existing publishing workflow

1. Read the existing Site via `get_site`, preserving its project ID and audience.
2. Obtain a short-lived source write credential and open/synchronize source using the installed `site-workflow.mjs` helper.
3. Make the targeted change; run only relevant checks plus required build.
4. Use the workflow helper to commit/push the exact source, build/package the output, and return the verified SHA/archive.
5. For the currently verified owner-private audience, native `save_version_and_deploy_private` was used. If access has changed, reread it and use the appropriate current workflow; do not reset audience just to deploy.
6. Wait for deployment success before claiming it is live. Keep tokens in memory/stdin, never shell command text or files.

The plugin path in the prior environment was `/root/.codex/plugins/cache/openai-curated-remote/sites/0.1.75/scripts/site-workflow.mjs`; discover the installed version rather than hardcoding this forever. Earlier in the project helpers temporarily went missing, but they were available again for the latest updates.

## 11. Portable Windows app

The user explicitly requested a downloadable Windows app to send to a friend. A first portable build was created **after** website version 24; the desktop source is separate from the website Git repository.

| Item | Value |
| --- | --- |
| Download artifact | `Worldbound-Windows.zip` |
| Persistent file ID | `libfile_7ea7b3607ac48191ad01df2d1332cc03` |
| Artifact size at creation | 157,918,948 bytes |
| Original local ZIP | `/workspace/scratch/fb91bf48b4c7/Worldbound-Windows.zip` |
| Original packaging directory | `/workspace/scratch/fb91bf48b4c7/worldbound-desktop` |
| Runtime | Electron 44.5.1, Windows x64 |
| App version | 1.0.0 |
| Launch | Extract all files, then run `Worldbound-Windows/Worldbound.exe` |
| Editable wrapper source inside ZIP | `Worldbound-Windows/resources/app/main.cjs`, `connection.html`, `package.json` |

This is a real packaged Electron runtime loading the hosted website. It is **not an offline version**, self-contained server, signed installer, or independently hosted clone.

- Requires internet and permission to access the private Site.
- Does not include a copied Google key, owner session, or bypass token.
- Uses sandboxing, context isolation, no Node integration in renderer, HTTPS navigation restrictions, explicit external-link confirmation, and denied unneeded permissions/downloads.
- Stores its own persistent session (`persist:worldbound`), separate from normal browser cookies. This can also create a separate saved-player identity for Daily.
- Supports F11 fullscreen, Ctrl+R reconnect, Open in Browser, and an offline/connection-error screen.
- Game changes load from the live website automatically. The Electron runtime itself has **no automatic updater**.
- Sign-in redirects/popups are limited to known hosts. Other SSO providers or embedded-browser restrictions may prevent sign-in. Opening the site in the system browser is a fallback, not a mechanism to copy browser authentication into Electron.
- Runtime archive SHA-256 was checked against the official Electron release checksum. ZIP integrity, Windows x64 PE format, JavaScript syntax, and mocked initialization/navigation/permission behavior were checked.
- **No actual Windows execution, Google Street View gameplay, or end-to-end desktop sign-in was tested.** The build is unsigned and may show an unknown-publisher warning. Do not describe it as fully tested.
- A future handoff can recover the persistent ZIP and extract `resources/app/` if the packaging directory was pruned.

### Outstanding friend access

The last response asked the user for their friend's email to grant access. **No friend email was supplied and no invitation/access change was made.** The Site remains owner-only as of this handoff.

Do not make the Site public or package owner credentials as a shortcut. If the user supplies a friend email and asks to grant access, use the current Sites sharing flow, verify external invitations remain enabled, preserve existing viewers, and follow applicable recipient-resolution requirements. Adding an external viewer may send an invitation email.

## 12. Verification history and known gaps

### Confirmed by source/build/test checks

- Latest round-results update compiled and deployed successfully as version 24.
- TypeScript checks and production builds passed for recent UI changes.
- All seven medal cutoff checks passed: 0, 14,999, 15,000, 22,499, 22,500, 24,999, 25,000.
- Custom boundary/game tests passed for containment, deterministic samples, hole handling, broken-boundary rejection, selected-region persistence, default timer, ready validation, scoring, next-round flow, and classic compatibility.
- Actual downloaded Paris and Virginia OSM fixtures were parsed and checked against inside/outside points.

### Not fully verified or intentionally limited

- Local Custom Map preview could not reach the live place-search service and lacked the production Google key. Independent provider downloads and boundary tests succeeded, but a complete live city/state custom game was not demonstrated there.
- Latest timer/result layouts were source/type/build checked; do not infer a complete live gameplay visual QA from deployment success.
- Windows build has not run on Windows and desktop sign-in may require follow-up.
- Shared public place providers can throttle or fail; supported geometry/Street View coverage is not universal.
- Country borders use the included dataset and can be approximate near edges. Streak country checks follow that dataset, not a geocoding service's label.
- Uniform country selection is not uniform worldwide Street View coverage.
- The current world-scale results view can make close guesses appear nearly coincident; preserve it unless the user requests auto-fit/zoom changes.
- Replaying a restored Custom Map session may deserve verification: replay currently uses home-selection state through `start(...)`, so do not assume restored custom selection is always hydrated.
- Historical dead UI/CSS and dense one-line source make broad replacements risky. Inspect the active render path first.

## 13. Reference screenshots and user communication

Most recent relevant references:

- Mid-round capsule timer and score strip: `image(20261001-010249).png`, persistent ID `libfile_1ab15a466c848191810e9a8ecda20f06`.
- End-of-round map with green center button / left distance / right points: `image(20261001-011814).png`, persistent ID `libfile_ba29c69da3d88191a45eb09d74e5fe57`.

Earlier messages sometimes said images could not be read, but both of these were subsequently opened successfully. Their scratch paths may disappear; recover the actual image rather than guessing its contents. References establish layout/style, not permission to add ignored screenshot content or replace Worldbound branding with GeoGuessr branding.

The user prefers action, concise updates, and concrete results. They often provide short typo-heavy requests; infer obvious wording without turning routine edits into an interview. Ask only when a real ambiguity blocks the work. Explain verification limits honestly, especially around live APIs and desktop builds.

## 14. How to resume

1. Read this handoff and the user's latest request; do not implement every known gap automatically.
2. Inspect current source, branch status, runtime/tool instructions, and live Site state. Treat the checkout as authoritative over this dated snapshot.
3. Recover desktop/source/reference artifacts only as needed; do not assume scratch survives.
4. Make the smallest coherent change that preserves the latest UI and gameplay requirements.
5. Verify the changed behavior; distinguish mocked/build checks from live end-to-end tests.
6. Publish website edits through the existing Site; deliver desktop artifacts separately. Never claim a published website implies a rebuilt desktop runtime.

No access credentials or API key values are included in this handoff.
