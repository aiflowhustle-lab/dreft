import SwiftUI

/// Shared right-click / long-press menus for compact and interactive card chrome.
enum CanvasCardContextMenuAttachment {
  @ViewBuilder
  static func apply<ContextView: View>(
    to view: ContextView,
    card: CanvasCard,
    workspace: WorkspaceStore,
    store: CanvasStore,
    entitlements: EntitlementManager,
    sidebarVisible: Binding<Bool>,
    sidebarPanel: Binding<SidebarPanel>,
    onZoom: @escaping () -> Void,
    onRemove: @escaping () -> Void,
    onRename: @escaping () -> Void,
    onSwap: (() -> Void)? = nil
  ) -> some View {
    switch card.kind {
    case .image:
      view.contextMenu {
        CanvasImageCardContextMenu(
          workspace: workspace,
          store: store,
          entitlements: entitlements,
          card: card,
          sidebarVisible: sidebarVisible,
          sidebarPanel: sidebarPanel,
          onZoom: onZoom,
          onSwap: onSwap ?? {},
          onRemove: onRemove,
          onRename: onRename
        )
      }
    case .note, .text:
      view.contextMenu {
        CanvasNoteCardContextMenu(
          workspace: workspace,
          store: store,
          entitlements: entitlements,
          card: card,
          sidebarVisible: sidebarVisible,
          sidebarPanel: sidebarPanel,
          onZoom: onZoom,
          onRemove: onRemove,
          onRename: onRename
        )
      }
    }
  }
}
