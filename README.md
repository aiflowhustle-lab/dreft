# Dreft

Native SwiftUI infinite canvas workspace — an Obsidian-style editor for Mac and iPad.

## Platforms

- **macOS** 14+
- **iPadOS** 17+ (iPad only)

## Open

```bash
open Dreft.xcodeproj
```

Run on **My Mac** or an **iPad** simulator.

## Features

- Dark Obsidian-like shell (icon rail, sidebar, tabs) on Mac; collapsible sidebar on iPad
- Infinite canvas with dotted background, pan, and pinch/⌘-scroll zoom
- Note cards with editable text, color palette, resize handles
- Image cards via Photos picker (iPad) or Open Panel (Mac), drag-and-drop, and paste
- Bézier connector edges between cards with side handles
- Vault search sheet for adding notes from sample files
- Bottom toolbar: add card, vault note, image

## Project structure

```
Dreft/
├── Models/          Canvas & workspace types
├── Store/           CanvasStore (@Observable state)
├── Views/Canvas/    Infinite canvas, cards, edges
├── Views/Shell/     Workspace chrome
└── Theme/           Colors matching the web UI
```

## Next steps (not yet implemented)

- File persistence / real vault on disk
- Graph view, daily notes, terminal panel
- Undo/redo stack
- iPhone layout (currently iPad + Mac only)
