# Dreft — Onboarding Copy Spec

All user-facing onboarding strings live here. Code must read from `OnboardingCopy`, which mirrors this file.

---

## Screen 1 · Welcome

- **Headline:** Build worlds that stay together
- **Subline:** Notes, canvas, and lore — local on your device.
- **Primary button:** Get started

---

## Screen 2 · What are you building?

- **Headline:** What are you building?
- **Subline:** We'll tailor Dreft to how you create.

| ID | Title | Subtitle | SF Symbol |
|---|---|---|---|
| story | A story or novel | Characters, plot threads, and chapters | book.closed |
| webtoon | A webtoon or comic | Cast, episodes, and visual boards | paintpalette |
| campaign | A TTRPG campaign | Factions, locations, and session prep | map |
| notes | Linked notes & lore | Wikilinks, tags, and a living wiki | note.text |

---

## Screen 3 · Mirror (per creator type)

### story
- **Headline:** Every thread, one place
- **Body:** Track characters and plot lines on a canvas. Link lore in notes. See how it all connects in the graph.
- **Button:** Show me my world
- **Illustration asset:** onboarding/mirror_story

### webtoon
- **Headline:** From sketch to episode
- **Body:** Board cast and scene cards on canvas. Keep episode notes linked. Never lose a thread between chapters.
- **Button:** Show me my world
- **Illustration asset:** onboarding/mirror_webtoon

### campaign
- **Headline:** Your table, mapped
- **Body:** Faction boards, location cards, and session notes — linked so your party's world stays consistent.
- **Button:** Show me my world
- **Illustration asset:** onboarding/mirror_campaign

### notes
- **Headline:** A wiki that's yours
- **Body:** Write in markdown, link with [[wikilinks]], and explore connections on canvas and graph.
- **Button:** Show me my world
- **Illustration asset:** onboarding/mirror_notes

---

---

## Screen 4 · The why

- **Headline:** What's your main goal?
- **Subline:** We'll highlight the right tool on your first canvas.

**Confirmation flashes (screen 4, ~700ms before advance):**

| Maps to | Message |
|---|---|
| finish | Got it. Let's keep momentum going. |
| canon | Got it. Your canon, protected. |
| map | Got it. We'll show you the big picture. |
| own | Got it. Your files stay on your device. |

### story
| Label | Subtitle | Maps to | SF Symbol |
|---|---|---|---|
| Finish my draft | I need momentum to get to the end | finish | flag.checkered |
| Keep canon straight | Characters, timelines, and facts must stay consistent | canon | brain |
| See how it connects | I want the big picture of my world | map | point.3.connected.trianglepath.dotted |

### webtoon
| Label | Subtitle | Maps to | SF Symbol |
|---|---|---|---|
| Ship the next episode | I need to keep episodes moving | finish | flag.checkered |
| Keep cast consistent | Names, arcs, and timelines stay aligned | canon | brain |
| Board scenes visually | I think in panels and layouts | map | point.3.connected.trianglepath.dotted |

### campaign
| Label | Subtitle | Maps to | SF Symbol |
|---|---|---|---|
| Prep sessions faster | Less digging, more playing | finish | flag.checkered |
| Track lore and NPCs | Canon stays at the table | canon | brain |
| Map factions and places | I need a living campaign map | map | point.3.connected.trianglepath.dotted |

### notes
| Label | Subtitle | Maps to | SF Symbol |
|---|---|---|---|
| Capture ideas quickly | Inbox → organized lore | finish | flag.checkered |
| Build a reliable wiki | Links and tags I can trust | canon | brain |
| Own my data locally | Files on my device, no cloud lock-in | own | lock |

---

## Screen 5 · Name your world

- **Headline:** Name your world
- **Subline:** You can change this anytime.
- **Primary button:** Create my world
- **Skip link:** Skip for now
- **Default world name (when skipped):** My world

| Creator type | Placeholder |
|---|---|
| story | The Shattered Crown |
| webtoon | Starfall Academy |
| campaign | Thornwall Reach |
| notes | My Lore Wiki |

---

## Screen 6 · Vault

- **Headline:** Ready to explore
- **Subline:** Start with a sample world, or bring your own vault.
- **Primary button:** Start with a sample world
- **Secondary create:** Create new vault
- **Secondary open:** Open a folder
- **Obsidian hint:** Already use Obsidian? Open your vault folder directly.

---

## Building transition

- **Title template:** Building {worldName}…
- **Fallback world name:** your world
- **Check rows (sequential):** Canvas · Lore · Graph

---

## Guided first action (post-onboarding)

| Core desire | Message |
|---|---|
| finish | Tap the wand to replay how your world grew. |
| canon | Type [[ in a note to link lore together. |
| map | Drag from a card's handle to connect ideas. |
| own | Your vault lives on your device — open Manage vaults anytime. |

---

## Analytics events

Fire in order through the happy path:

1. `onboarding_welcome_continue`
2. `onboarding_creator_selected`
3. `onboarding_mirror_continue`
4. `onboarding_desire_selected`
5. `onboarding_world_named` OR `onboarding_world_skipped`
6. `onboarding_sample_world_started` OR `onboarding_vault_created` OR `onboarding_vault_opened`
7. `onboarding_building_complete`
8. `onboarding_completed`
9. `onboarding_guided_action_dismissed` (when applicable)
