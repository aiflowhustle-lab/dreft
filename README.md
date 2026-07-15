# Dreft

Native SwiftUI infinite canvas workspace — an Obsidian-style editor for Mac and iPad.

## Platforms

- **macOS** 14+
- **iPadOS** 17+ (iPad only)

## Open

```bash
open Dreft.xcodeproj
```

Run on **My Mac** or an **iPad** simulator. Use the shared **Dreft** scheme for archives and CI.

## Features

- Light and dark themes with Obsidian-like shell (icon rail, sidebar, tabs)
- Infinite canvas with dotted background, pan, and pinch / scroll zoom
- Note cards with markdown editing, wikilinks, and color palette
- Image cards via Photos picker (iPad), Open Panel (Mac), drag-and-drop, and paste
- Connection lines with direction, custom colors, inline labels, and floating toolbar
- Local vault persistence (notes, canvases, bookmarks, version history)
- Graph view with force-directed layout
- Undo/redo on canvas and notes; version restore
- Canvas PNG export with labels, colors, and arrows
- Split panes (Obsidian-style) with independent tab bars per pane
- iPad-optimized floating sidebar and canvas toolbars

## App Store prep

- App icons in `Assets.xcassets/AppIcon.appiconset/`
- Privacy manifest: `Dreft/PrivacyInfo.xcprivacy`
- Export compliance: `ITSAppUsesNonExemptEncryption = NO`
- Help & support: [Notion help page](https://lavish-birthday-3cc.notion.site/Dreft-Help-Support-39e2796a24538094b200c799f7ddf41d)
- Privacy policy: [Notion privacy page](https://lavish-birthday-3cc.notion.site/Dreft-Privacy-Policy-39e2796a245380869bb7f48509695d5e)

## Project structure

```
Dreft/
├── Models/          Canvas & workspace types
├── Store/           CanvasStore, WorkspaceStore, vault persistence
├── Views/Canvas/    Infinite canvas, cards, edges, export
├── Views/Shell/     Workspace chrome, notes, graph
└── Theme/           AppColors, light/dark themes
```

## Tests

```bash
xcodebuild test -scheme Dreft -destination 'platform=macOS'
```

## License

Copyright © 2026 AiFlowHustle. All rights reserved.
