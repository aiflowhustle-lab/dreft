import SwiftUI
import Combine
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif

struct InfiniteCanvasView: View {
  @Bindable var store: CanvasStore
  @Bindable var workspace: WorkspaceStore
  var entitlements: EntitlementManager
  @Binding var sidebarVisible: Bool
  @Binding var sidebarPanel: SidebarPanel
  var documentTitle: String = "Untitled"
  var vaultURL: URL?
  /// When true (split panes), this view owns its camera and does not follow `store.transform`.
  var independentCamera = false
  /// When true, this pane writes its camera into the shared document on gesture end.
  var persistsCamera = true

  /// Single render transform — never nil-flipped during gestures (prevents shake).
  @State private var displayTransform = CanvasViewTransform()
  @State private var interaction = CanvasInteractionState()
  @State private var viewport = CanvasViewportController()
  @State private var showCanvasSettings = false
  @AppStorage("canvasShowGrid") private var showCanvasGrid = true
  @State private var showImagePicker = false
  @State private var swapImageCardID: String?
  @State private var showImageSwapPicker = false
  @State private var edgeInteractionActive = false
  @State private var pendingEdgeInteractionID: String?
  @State private var edgeInteractionStartLocation: CGPoint?
  @State private var cardToolbarColorRowOpen = false
  @State private var cardToolbarCustomColorOpen = false
  @State private var edgeToolbarColorRowOpen = false
  @State private var edgeToolbarCustomColorOpen = false
  @State private var imageTitleRenameTokens: [String: Int] = [:]
  @State private var hoverEdgeID: String?
  @State private var editingEdgeLabelID: String?
  @State private var edgeLabelDraft = ""
  @StateObject private var canvasNoteToolbarBridge = NoteFormattingToolbarBridge()
  #if os(iOS)
  @State private var showNoteAttachmentMenu = false
  @State private var showNotePhotoPicker = false
  @State private var showNoteCamera = false
  @State private var showNoteFileImporter = false
  #endif
  #if canImport(PhotosUI)
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var noteAttachmentPhotoItem: PhotosPickerItem?
  #endif
  @State private var timelapsePlaying = false
  @State private var timelapseVisibleCardIDs: Set<String>?
  @State private var timelapseVisibleEdgeIDs: Set<String>?
  @State private var timelapseCurrentDate: Date?
  @State private var timelapseTask: Task<Void, Never>?
  @State private var timelapseRevision = 0
  /// Locks note edit typography when a card enters edit mode so typing stays the same size.
  @State private var noteEditFontSize: CGFloat?
  @State private var noteEditImageInserter: NoteImageInserter?
  #if os(iOS)
  @StateObject private var noteEditKeyboardObserver = KeyboardHeightObserver()
  @State private var canvasPanYOffsetForKeyboard: CGFloat = 0
  @State private var canvasSafeAreaBottom: CGFloat = 0
  @State private var keyboardAvoidanceTask: Task<Void, Never>?
  #endif

  private var effectiveVaultURL: URL? {
    vaultURL ?? store.vaultURL
  }

  var body: some View {
    GeometryReader { geo in
      canvasGeometryContent(geo: geo)
    }
  }

  @ViewBuilder
  private func canvasGeometryContent(geo: GeometryProxy) -> some View {
    let size = geo.size
    let safeBottom = geo.safeAreaInsets.bottom
    let vaultFiles = VaultFile.openableFiles(from: workspace.files)
    let edgesInView = mountedEdges(for: size)

    canvasImportAndPlatformModifiers(size: size) {
      canvasGestureAndLifecycleModifiers(size: size, safeBottom: safeBottom) {
        canvasChromeOverlays(
          size: size,
          safeBottom: safeBottom,
          vaultFiles: vaultFiles
        ) {
          canvasSelectionChangeHandlers(size: size) {
            canvasLayerStack(
              size: size,
              vaultFiles: vaultFiles,
              edgesInView: edgesInView
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
              CanvasAccessibility.canvasLabel(
                zoomPercent: Int((displayTransform.zoom * 100).rounded()),
                cardCount: store.cards.count
              )
            )
            .frame(width: size.width, height: size.height)
            .clipped()
          }
        }
      }
    }
  }

  @ViewBuilder
  private func canvasLayerStack(
    size: CGSize,
    vaultFiles: [VaultFile],
    edgesInView: [CanvasEdge]
  ) -> some View {
    ZStack {
      AppColors.canvasBackground

      if showCanvasGrid {
        DotGridBackground(
          panOffset: CGSize(width: displayTransform.x, height: displayTransform.y),
          dotColor: AppColors.gridDotColor
        )
        .accessibilityHidden(true)
      }

      canvasInteractionBackground(canvasSize: size)

      canvasCardsLayer(canvasSize: size, vaultFiles: vaultFiles)
        .zIndex(3)

      canvasEdgeHitOverlay(edgesInView: edgesInView)
        .zIndex(4)

      CanvasEdgesScreenOverlay(
        transform: displayTransform,
        cardIndex: cardIndex,
        edges: edgesInView,
        connectingFrom: store.connectingFrom,
        positionOverrides: interaction.cardDragOverrides,
        resizeOverrides: interaction.cardResizeOverrides,
        selectedEdgeID: store.selectedEdgeID,
        editingEdgeID: editingEdgeLabelID,
        editingLabelDraft: edgeLabelDraft
      )
      .zIndex(5)

      CanvasEdgeLabelLayer(
        transform: displayTransform,
        cardIndex: cardIndex,
        edges: edgesInView,
        positionOverrides: interaction.cardDragOverrides,
        resizeOverrides: interaction.cardResizeOverrides,
        editingEdgeID: editingEdgeLabelID,
        labelDraft: $edgeLabelDraft,
        onCommit: { edgeID, label in
          store.setEdgeLabel(edgeID, label: label)
          editingEdgeLabelID = nil
        },
        onBeginEdit: { edgeID in
          beginEdgeLabelEdit(edgeID: edgeID)
        }
      )
      .zIndex(6)

      if store.isDragOver { dropOverlay }

      if store.contextMenu != nil {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            store.dismissPendingEndpoint()
            store.selectedCardID = nil
            store.endContentEdit()
            store.focusCardID = nil
          }
          .zIndex(99)
      }

      if let menu = store.contextMenu {
        contextMenuOverlay(menu, canvasSize: size)
      }
    }
  }

  @ViewBuilder
  private func canvasEdgeHitOverlay(edgesInView: [CanvasEdge]) -> some View {
    let overlay = CanvasEdgeHitOverlay(
      transform: displayTransform,
      cardIndex: cardIndex,
      edges: edgesInView,
      positionOverrides: interaction.cardDragOverrides,
      resizeOverrides: interaction.cardResizeOverrides,
      edgeEndpoint: { edge in
        store.edgeEndpoint(
          for: edge,
          positionOverrides: interaction.cardDragOverrides,
          resizeOverrides: interaction.cardResizeOverrides
        )
      },
      onHoverEdge: { edgeID in
        Task { @MainActor in
          hoverEdgeID = edgeID
        }
      }
    )

    #if os(macOS)
    overlay
      .allowsHitTesting(!timelapsePlaying && store.selectedCardID == nil)
      .canvasEdgeHandCursor(
        isActive: hoverEdgeID != nil
          || store.selectedEdgeID != nil
          || edgeInteractionActive
          || pendingEdgeInteractionID != nil
          || store.editingEdgeID != nil,
        isGrabbing: edgeInteractionActive
          || pendingEdgeInteractionID != nil
          || store.editingEdgeID != nil
      )
    #else
    overlay
      .allowsHitTesting(false)
    #endif
  }

  @ViewBuilder
  private func canvasSelectionChangeHandlers<Content: View>(
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .onChange(of: store.selectedCardID) { _, _ in
        settleInFlightCardInteraction()
        cardToolbarColorRowOpen = false
        cardToolbarCustomColorOpen = false
        edgeToolbarColorRowOpen = false
        edgeToolbarCustomColorOpen = false
        replaceMountedContent(for: size)
      }
      .onChange(of: cardToolbarColorRowOpen) { _, isOpen in
        if isOpen, interaction.isCardDragging || interaction.isCardResizing || interaction.panActive {
          settleInFlightCardInteraction()
        }
      }
      .onChange(of: cardToolbarCustomColorOpen) { _, isOpen in
        if isOpen, interaction.isCardDragging || interaction.isCardResizing || interaction.panActive {
          settleInFlightCardInteraction()
        }
      }
      .onChange(of: store.selectedEdgeID) { _, newValue in
        if let editingID = editingEdgeLabelID, newValue != editingID {
          commitEdgeLabelEdit(for: editingID)
        }
        if newValue == nil {
          edgeToolbarColorRowOpen = false
          edgeToolbarCustomColorOpen = false
        }
      }
      .onChange(of: store.historyRevision) { _, _ in
        clearCardInteractionState()
        replaceMountedContent(for: size)
      }
      .onChange(of: imageTitleRenameTokens) { _, _ in
        clearCardInteractionState()
      }
  }

  @ViewBuilder
  private func canvasChromeOverlays<Content: View>(
    size: CGSize,
    safeBottom: CGFloat,
    vaultFiles: [VaultFile],
    @ViewBuilder content: () -> Content
  ) -> some View {
    canvasFloatingToolbarOverlays(size: size, safeBottom: safeBottom, vaultFiles: vaultFiles) {
      canvasTouchOverlayIfNeeded(canvasSize: size) {
        content()
      }
    }
  }

  @ViewBuilder
  private func canvasTouchOverlayIfNeeded<Content: View>(
    canvasSize: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    #if os(iOS)
    content()
      .overlay {
        canvasTouchCaptureOverlay(canvasSize: canvasSize)
      }
    #else
    content()
    #endif
  }

  @ViewBuilder
  private func canvasFloatingToolbarOverlays<Content: View>(
    size: CGSize,
    safeBottom: CGFloat,
    vaultFiles: [VaultFile],
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .overlay(alignment: .topTrailing) {
        canvasRightToolbar(canvasSize: size)
          .zIndex(300)
          .opacity(timelapsePlaying ? 0.45 : 1)
          .allowsHitTesting(!timelapsePlaying)
      }
      .overlay(alignment: .bottom) {
        if store.focusCardID == nil {
          canvasBottomToolbar(canvasSize: size, safeAreaBottom: safeBottom)
            .zIndex(300)
            .opacity(timelapsePlaying ? 0.45 : 1)
            .allowsHitTesting(!timelapsePlaying)
        }
      }
      .overlay(alignment: .bottomLeading) {
        zoomIndicator(safeAreaBottom: safeBottom)
      }
      .overlay(alignment: .bottomTrailing) {
        backlinkBadge(safeAreaBottom: safeBottom)
      }
      .overlay {
        canvasNoteEditOverlay(canvasSize: size, vaultFiles: vaultFiles)
          .zIndex(250)
      }
      .overlay {
        canvasCardToolbarLayer(canvasSize: size)
          .zIndex(260)
      }
      .overlay {
        if store.isVaultOpen {
          VaultSearchSheet(store: store, workspace: workspace, canvasSize: size)
            .zIndex(200)
        }
      }
      .contentShape(Rectangle())
      .clipped()
      .coordinateSpace(name: "canvasScreen")
      .overlay(alignment: .topLeading) {
        canvasTimelapseChrome(canvasSize: size)
          .zIndex(400)
      }
      .overlay(alignment: .top) {
        if entitlements.isReadOnly {
          ReadOnlyBanner {
            entitlements.presentPaywall(.readOnlyBanner)
          }
          .zIndex(350)
        }
      }
      #if os(iOS)
      .overlay {
        NoteInsertAttachmentMenuOverlay(
          isPresented: $showNoteAttachmentMenu,
          anchor: canvasAttachmentMenuAnchor(canvasSize: size),
          onPhotoLibrary: { showNotePhotoPicker = true },
          onTakePhoto: { showNoteCamera = true },
          onChooseFile: { showNoteFileImporter = true }
        )
        .zIndex(600)
      }
      #endif
      .background(AppColors.canvasBackground)
      #if os(iOS)
      .onReceive(noteEditKeyboardObserver.$height) { _ in
        requestCanvasKeyboardAvoidanceUpdate(canvasSize: size)
      }
      .onReceive(noteEditKeyboardObserver.$isVisible) { visible in
        if visible, store.focusCardID != nil {
          requestCanvasKeyboardAvoidanceUpdate(canvasSize: size)
        }
      }
      .onChange(of: store.focusCardID) { _, newID in
        keyboardAvoidanceTask?.cancel()
        keyboardAvoidanceTask = nil
        if newID == nil {
          store.endContentEdit()
          showNoteAttachmentMenu = false
          clearCanvasKeyboardPanTracking()
          noteEditImageInserter = nil
          canvasNoteToolbarBridge.detachFromEditor()
        } else {
          requestCanvasKeyboardAvoidanceUpdate(canvasSize: size)
        }
      }
      #endif
  }

  #if os(iOS)
  private func canvasTouchCaptureOverlay(canvasSize: CGSize) -> some View {
    CanvasTouchCaptureView(
      passesThroughHits: true,
      isEnabled: canvasPanZoomEnabled,
      blocksNavigationAt: { point in
        blocksCanvasNavigation(at: point, canvasSize: canvasSize)
      },
      onPan: { delta in
        if interaction.mode != .canvasNavigation {
          interaction.mode = .canvasNavigation
        }
        displayTransform.x += delta.width
        displayTransform.y += delta.height
      },
      onPanBegan: {
        interaction.beginCanvasNavigation(
          anchor: CGSize(width: displayTransform.x, height: displayTransform.y)
        )
        cancelPendingEdgeInteraction()
      },
      onPanEnded: {
        interaction.endCanvasNavigation()
        finishCanvasInteraction()
      },
      onPinchBegan: { _ in
        guard !interaction.isCardDragging, !interaction.isCardResizing else { return }
        if interaction.mode == .idle {
          interaction.mode = .canvasNavigation
        }
        interaction.pinchStartZoom = displayTransform.zoom
      },
      onPinchChanged: { scale, anchor in
        guard !interaction.isCardDragging, !interaction.isCardResizing else { return }
        let startZoom = interaction.pinchStartZoom ?? displayTransform.zoom
        let newZoom = min(
          CanvasViewTransform.maxZoom,
          max(CanvasViewTransform.minZoom, startZoom * scale)
        )
        applyZoom(at: anchor, targetZoom: newZoom)
      },
      onPinchEnded: {
        interaction.pinchStartZoom = nil
        finishCanvasInteraction()
      },
      onLongPress: { location in
        handleCanvasLongPress(at: location, canvasSize: canvasSize)
      }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(false)
  }
  #endif

  @ViewBuilder
  private func canvasGestureAndLifecycleModifiers<Content: View>(
    size: CGSize,
    safeBottom: CGFloat = 0,
    @ViewBuilder content: () -> Content
  ) -> some View {
    canvasMacScrollModifiers(size: size) {
      content()
        #if os(iOS)
        .onAppear { canvasSafeAreaBottom = safeBottom }
        .onChange(of: safeBottom) { _, newValue in
          canvasSafeAreaBottom = newValue
        }
        #endif
        .simultaneousGesture(edgeInteractionGesture(canvasSize: size))
        .onAppear {
          displayTransform = store.transform
          store.vaultURL = vaultURL
          store.viewportSize = size
          store.fitAllNoteCardsToContent()
          replaceMountedContent(for: size)
          scheduleOnboardingTimelapseIfNeeded(canvasSize: size)
        }
        .onDisappear {
          stopCanvasTimelapse(showAll: true)
          CanvasImageCache.shared.setPinnedKeys([])
        }
        .onChange(of: size) { _, newSize in
          store.viewportSize = newSize
          replaceMountedContent(for: newSize)
        }
        .onChange(of: vaultURL) { _, newURL in
          store.vaultURL = newURL
        }
        .onChange(of: store.transform) { _, newValue in
          guard !independentCamera, !interaction.isCanvasInteracting, !interaction.isCardDragging else { return }
          displayTransform = newValue
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $store.isDragOver) { providers, location in
          importDroppedImages(providers, at: location, canvasSize: size)
        }
    }
  }

  @ViewBuilder
  private func canvasMacScrollModifiers<Content: View>(
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    #if os(macOS)
    content()
      .onCanvasScroll(shouldPassToContent: { location in
        shouldPassScrollToNoteCard(at: location, canvasSize: size)
      }) { delta, location, zoomRequested, phaseEnded in
        if store.contextMenu != nil || store.isVaultOpen { return }
        if interaction.mode == .idle {
          interaction.mode = .canvasNavigation
        }
        if zoomRequested {
          applyZoom(at: location, factor: exp(-delta.height * 0.0015))
        } else {
          displayTransform.x += delta.width
          displayTransform.y += delta.height
        }
        if phaseEnded {
          finishCanvasInteraction()
        }
      }
      .simultaneousGesture(store.contextMenu == nil ? pinchGesture(in: size) : nil)
    #else
    content()
    #endif
  }

  @ViewBuilder
  private func canvasImportAndPlatformModifiers<Content: View>(
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    canvasMacPlatformModifiers(size: size) {
      canvasFileImportModifiers {
        canvasPhotoImportModifiers(size: size, content: content)
      }
    }
  }

  @ViewBuilder
  private func canvasPhotoImportModifiers<Content: View>(
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    #if canImport(PhotosUI)
    canvasNoteAttachmentModifiers(size: size, content: {
      content()
        .photosPicker(isPresented: $showImagePicker, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in
          Task { await importPickedPhotos(items, canvasSize: size) }
        }
    })
    #elseif os(macOS)
    canvasNoteAttachmentModifiers(size: size, content: content)
    #else
    content()
    #endif
  }

  #if os(iOS)
  @ViewBuilder
  private func canvasNoteAttachmentModifiers<Content: View>(
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .noteAttachmentImportModifiers(
        showAttachmentMenu: $showNoteAttachmentMenu,
        showPhotoPicker: $showNotePhotoPicker,
        showCamera: $showNoteCamera,
        showFileImporter: $showNoteFileImporter,
        photoItem: $noteAttachmentPhotoItem,
        menuAnchor: { canvasAttachmentMenuAnchor(canvasSize: size) },
        presentsMenuOverlay: false,
        onInsertImage: { data, name in
          insertNoteAttachment(data: data, suggestedName: name)
        },
        onImportFile: importNoteAttachmentFile,
        onRegisterInsertAttachment: {
          canvasNoteToolbarBridge.onInsertAttachment = {
            showNoteAttachmentMenu = true
          }
        }
      )
  }
  #elseif os(macOS)
  @ViewBuilder
  private func canvasNoteAttachmentModifiers<Content: View>(
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .onAppear {
        canvasNoteToolbarBridge.onInsertAttachment = {
          openMacNoteAttachmentPanel()
        }
      }
  }
  #endif

  @ViewBuilder
  private func canvasFileImportModifiers<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .fileImporter(
        isPresented: $showImageSwapPicker,
        allowedContentTypes: [.image],
        allowsMultipleSelection: false
      ) { result in
        importSwappedImage(from: result)
      }
  }

  @ViewBuilder
  private func canvasMacPlatformModifiers<Content: View>(
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) -> some View {
    #if os(macOS)
    content()
      .onReceive(NotificationCenter.default.publisher(for: .openImagePanel)) { _ in
        openMacImagePanel(canvasSize: size)
      }
      .focusable(store.focusCardID == nil)
      .focusEffectDisabled()
      .background {
        if store.focusCardID == nil {
          canvasKeyboardShortcuts(canvasSize: size)
        }
      }
    #else
    content()
    #endif
  }

  #if os(macOS)
  private func canvasKeyboardShortcuts(canvasSize: CGSize) -> some View {
    Group {
      Button("") { store.undo() }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!store.canUndo)
      Button("") { store.redo() }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!store.canRedo)
      Button("") { zoomToFitAll(canvasSize: canvasSize) }
        .keyboardShortcut("1", modifiers: .shift)
      Button("") { zoomToSelection(canvasSize: canvasSize) }
        .keyboardShortcut("2", modifiers: .shift)
      Button("") { deleteSelectedCard() }
        .keyboardShortcut(.delete, modifiers: [])
      Button("") { deleteSelectedCard() }
        .keyboardShortcut(KeyEquivalent("\u{8}"), modifiers: [])
    }
    .opacity(0)
    .frame(width: 0, height: 0)
  }

  private func deleteSelectedCard() {
    guard store.focusCardID == nil, let id = store.selectedCardID else { return }
    guard entitlements.requireWriteAccess(context: documentTitle) else { return }
    store.deleteCard(id)
  }
  #endif

  // MARK: - World

  private var cardIndex: [String: CanvasCard] {
    Dictionary(store.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }

  private var timelapseActive: Bool {
    timelapseVisibleCardIDs != nil
  }

  private var timelapseFilteredCards: [CanvasCard] {
    guard let visible = timelapseVisibleCardIDs else { return store.cards }
    return store.cards.filter { visible.contains($0.id) }
  }

  private var activeCanvasEdges: [CanvasEdge] {
    guard timelapseActive else { return store.edges }
    let visibleEdges = timelapseVisibleEdgeIDs ?? []
    let visibleCards = timelapseVisibleCardIDs ?? []
    return store.edges.filter { edge in
      guard visibleEdges.contains(edge.id), visibleCards.contains(edge.fromID) else { return false }
      if let toID = edge.toID {
        return visibleCards.contains(toID)
      }
      return true
    }
  }

  private func canvasViewportPadding() -> CGFloat {
    if interaction.isCardResizing || interaction.isCardDragging {
      return CanvasConstants.interactionViewportPadding
    }
    return CanvasConstants.viewportPadding
  }

  private func viewportEnvironment(canvasSize: CGSize) -> CanvasViewportEnvironment {
    CanvasViewportEnvironment(
      canvasSize: canvasSize,
      displayTransform: displayTransform,
      cards: store.cards,
      edges: activeCanvasEdges,
      cardIndex: cardIndex,
      cardDragOverrides: interaction.cardDragOverrides,
      cardResizeOverrides: interaction.cardResizeOverrides,
      selectedCardID: store.selectedCardID,
      hoverCardID: store.hoverCardID,
      focusCardID: store.focusCardID,
      selectedEdgeID: store.selectedEdgeID,
      editingEdgeLabelID: editingEdgeLabelID,
      storeEditingEdgeID: store.editingEdgeID,
      pendingEdgeInteractionID: pendingEdgeInteractionID,
      isCardDragging: interaction.isCardDragging,
      isCardResizing: interaction.isCardResizing,
      isCanvasInteracting: interaction.isCanvasInteracting,
      timelapseActive: timelapseActive,
      spatialIndex: store.spatialIndexForCulling()
    )
  }

  private func replaceMountedContent(for canvasSize: CGSize) {
    viewport.replaceMountedContent(using: viewportEnvironment(canvasSize: canvasSize))
  }

  private func expandMountedContent(for canvasSize: CGSize) {
    viewport.expandMountedContent(using: viewportEnvironment(canvasSize: canvasSize))
  }

  private func handleViewportChanged(canvasSize: CGSize) {
    viewport.handleViewportChanged(using: viewportEnvironment(canvasSize: canvasSize))
  }

  private func computeVisibleCardIDs(for canvasSize: CGSize, padding: CGFloat? = nil) -> Set<String> {
    viewport.computeVisibleCardIDs(using: viewportEnvironment(canvasSize: canvasSize), padding: padding)
  }

  private func computeVisibleEdgeIDs(for canvasSize: CGSize, padding: CGFloat? = nil) -> Set<String> {
    viewport.computeVisibleEdgeIDs(using: viewportEnvironment(canvasSize: canvasSize), padding: padding)
  }

  private func mountedCards(for canvasSize: CGSize) -> [CanvasCard] {
    let sourceCards = timelapseActive ? timelapseFilteredCards : store.cards
    return viewport.mountedCards(
      sourceCards: sourceCards,
      using: viewportEnvironment(canvasSize: canvasSize)
    )
  }

  private func mountedEdges(for canvasSize: CGSize) -> [CanvasEdge] {
    viewport.mountedEdges(
      sourceEdges: activeCanvasEdges,
      using: viewportEnvironment(canvasSize: canvasSize)
    )
  }

  private func liveVisibleEdges(for canvasSize: CGSize) -> [CanvasEdge] {
    let ids = computeVisibleEdgeIDs(for: canvasSize)
    return activeCanvasEdges.filter { ids.contains($0.id) }
  }

  /// Legacy name kept for hit-testing — uses live viewport, not the sticky mounted superset.
  private func visibleEdges(for canvasSize: CGSize) -> [CanvasEdge] {
    liveVisibleEdges(for: canvasSize)
  }

  /// Pan / tap target behind cards — screen space so iOS hit-testing stays accurate.
  private func canvasInteractionBackground(canvasSize: CGSize) -> some View {
    Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        canvasPanGestureEnabled ? canvasPanGesture : nil
      )
      .onTapGesture(count: 2, coordinateSpace: .named("canvasScreen")) { location in
        handleCanvasTap(at: location, canvasSize: canvasSize)
      }
      .onTapGesture(coordinateSpace: .named("canvasScreen")) { location in
        guard !interaction.isCanvasInteracting, !interaction.panActive else { return }
        // Tapping a connection line selects it (floating toolbar); the edge drag
        // gesture also selects, but this tap fires later and must not clear it.
        if let edgeID = hitTestEdge(at: location, canvasSize: canvasSize) {
          store.selectEdge(edgeID)
          return
        }
        // Never clear selection/edit when the tap landed on a card — sibling
        // background taps can otherwise race card gestures and block re-edit.
        let world = store.screenToWorld(location, in: canvasSize, transform: displayTransform)
        if store.card(
          at: world,
          positionOverrides: interaction.cardDragOverrides,
          resizeOverrides: interaction.cardResizeOverrides
        ) != nil {
          return
        }
        store.selectedCardID = nil
        store.selectedEdgeID = nil
        store.endContentEdit()
        store.focusCardID = nil
        commitEdgeLabelEditIfNeeded()
        canvasNoteToolbarBridge.dismissKeyboard()
      }
  }

  private var canvasPanZoomEnabled: Bool {
    store.contextMenu == nil
      && !interaction.isCardDragging
      && !interaction.isCardResizing
      && !store.isConnectingLine
      && store.focusCardID == nil
      && !store.isVaultOpen
  }

  private var canvasNavigationEnabled: Bool {
    canvasPanZoomEnabled && !timelapsePlaying
  }

  private var canvasPanGestureEnabled: Bool {
    #if os(iOS)
    false
    #else
    canvasPanZoomEnabled
    #endif
  }

  /// Double-click empty canvas → place a new note card at the click location.
  private func handleCanvasTap(at screenPoint: CGPoint, canvasSize: CGSize) {
    guard canvasNavigationEnabled, !store.isVaultOpen else { return }
    if let until = interaction.suppressCanvasTapUntil, Date() < until { return }

    store.dismissPendingEndpoint()

    let worldPoint = store.screenToWorld(screenPoint, in: canvasSize, transform: displayTransform)
    if store.card(
      at: worldPoint,
      positionOverrides: interaction.cardDragOverrides,
      resizeOverrides: interaction.cardResizeOverrides
    ) != nil {
      return
    }

    addNoteAndFocus(at: worldPoint)
  }

  private func addNoteAndFocus(at worldPoint: CGPoint) {
    guard entitlements.canWrite else {
      entitlements.presentPaywall(.editBlocked, context: documentTitle)
      return
    }
    store.addCompactNote(at: worldPoint)
    store.focusCardID = store.selectedCardID
  }

  private func beginCardEdit(for card: CanvasCard) {
    guard entitlements.canWrite else {
      entitlements.presentPaywall(.editBlocked, context: documentTitle)
      return
    }
    store.selectedCardID = card.id
    store.selectedEdgeID = nil
    store.focusCardID = card.id
    store.beginContentEdit(for: card.id)
  }

  private func commitEdgeLabelEditIfNeeded() {
    guard let edgeID = editingEdgeLabelID else { return }
    commitEdgeLabelEdit(for: edgeID)
  }

  private func commitEdgeLabelEdit(for edgeID: String) {
    store.setEdgeLabel(edgeID, label: edgeLabelDraft)
    if editingEdgeLabelID == edgeID {
      editingEdgeLabelID = nil
    }
  }

  private func beginEdgeLabelEdit(edgeID: String) {
    guard entitlements.requireWriteAccess(context: documentTitle) else { return }
    if let editingID = editingEdgeLabelID, editingID != edgeID {
      commitEdgeLabelEdit(for: editingID)
    }
    editingEdgeLabelID = edgeID
  }

  #if os(iOS)
  /// Pencil/finger long-press on empty canvas → add-card menu (Apple Pencil creation flow).
  private func handleCanvasLongPress(at screenPoint: CGPoint, canvasSize: CGSize) {
    guard canvasNavigationEnabled, !store.isVaultOpen else { return }
    if let until = interaction.suppressCanvasTapUntil, Date() < until { return }

    let worldPoint = store.screenToWorld(screenPoint, in: canvasSize, transform: displayTransform)
    if store.card(
      at: worldPoint,
      positionOverrides: interaction.cardDragOverrides,
      resizeOverrides: interaction.cardResizeOverrides
    ) != nil {
      return
    }

    store.showCanvasMenu(at: screenPoint, worldPoint: worldPoint)
  }
  #endif

  private func cardScreenOrigin(for liveFrame: CGRect, transform: CanvasViewTransform) -> CGPoint {
    store.worldToScreen(liveFrame.origin, transform: transform)
  }

  private func cardScreenCenter(for liveFrame: CGRect, transform: CanvasViewTransform) -> CGPoint {
    let origin = cardScreenOrigin(for: liveFrame, transform: transform)
    let zoom = transform.zoom
    return CGPoint(
      x: origin.x + (liveFrame.width * zoom) / 2,
      y: origin.y + (liveFrame.height * zoom) / 2
    )
  }

  private func noteCardScreenRect(
    for card: CanvasCard,
    transform: CanvasViewTransform? = nil
  ) -> CGRect {
    let worldFrame = cardDisplayFrame(card)
    let resolvedTransform = transform ?? cardRenderTransform
    let origin = cardScreenOrigin(for: worldFrame, transform: resolvedTransform)
    let zoom = resolvedTransform.zoom
    return CGRect(
      x: origin.x,
      y: origin.y,
      width: worldFrame.width * zoom,
      height: worldFrame.height * zoom
    )
  }

  #if os(iOS)
  /// Card screen rect before keyboard-avoidance pan — avoids pan ↔ measure feedback loops.
  private func noteCardScreenRectBeforeKeyboardPan(for card: CanvasCard) -> CGRect {
    var transform = cardRenderTransform
    transform.y += canvasPanYOffsetForKeyboard
    return noteCardScreenRect(for: card, transform: transform)
  }
  #endif

  #if os(macOS)
  /// Let note-card scroll views consume the wheel when the pointer is over editable/selected card content.
  private func shouldPassScrollToNoteCard(at location: CGPoint, canvasSize: CGSize) -> Bool {
    _ = canvasSize
    if store.contextMenu != nil || store.isVaultOpen { return false }

    if let focusID = store.focusCardID,
       let card = cardIndex[focusID],
       card.kind != .image {
      return noteCardScreenRect(for: card).contains(location)
    }

    if let selectedID = store.selectedCardID,
       let card = cardIndex[selectedID],
       card.kind != .image {
      return noteCardScreenRect(for: card).contains(location)
    }

    return false
  }
  #endif

  private var cardRenderTransform: CanvasViewTransform {
    interaction.cardRenderTransform(displayTransform: displayTransform)
  }

  private func beginCardInteractionFreeze() {
    interaction.cardInteractionFrozenTransform = displayTransform
  }

  private func endCardInteractionFreeze() {
    interaction.cardInteractionFrozenTransform = nil
  }

  /// Drop any in-flight card drag/resize so camera, cards, and edges share one transform.
  private func clearCardInteractionState() {
    interaction.clearCardInteraction()
  }

  /// Persist and clear card drag/resize when SwiftUI drops a gesture without onEnded (common on iPad toolbar/color UI).
  private func settleInFlightCardInteraction() {
    for cardID in Array(interaction.cardDragOverrides.keys) {
      handleCardMoveEnd(cardID: cardID)
    }
    for cardID in Array(interaction.cardResizeOverrides.keys) {
      if let frame = interaction.cardResizeOverrides[cardID] {
        store.resizeCard(cardID, frame: frame)
        interaction.cardResizeOverrides.removeValue(forKey: cardID)
      }
    }
    if interaction.isCardResizing || interaction.isCardDragging {
      interaction.endCardDragOrResize()
      endCardInteractionFreeze()
    }
    if interaction.panActive || interaction.isCanvasInteracting {
      interaction.endCanvasNavigation()
      finishCanvasInteraction()
    }
  }

  #if os(iOS)
  /// Keep canvas pan/pinch off cards so dragging doesn't briefly scale the view.
  private func blocksCanvasNavigation(at screenPoint: CGPoint, canvasSize: CGSize) -> Bool {
    if isPointOnCanvasToolbar(screenPoint, canvasSize: canvasSize) { return true }
    if isPointOnSelectedCardToolbar(screenPoint, ignoringDragState: true) { return true }
    let world = store.screenToWorld(screenPoint, in: canvasSize, transform: displayTransform)
    return store.card(
      at: world,
      positionOverrides: interaction.cardDragOverrides,
      resizeOverrides: interaction.cardResizeOverrides
    ) != nil
  }
  #endif

  /// Cards render in screen space (like edges) — avoids transformEffect breaking drag on iOS.
  private func canvasCardsLayer(canvasSize: CGSize, vaultFiles: [VaultFile]) -> some View {
    let transform = cardRenderTransform
    let zoom = transform.zoom
    let cards = mountedCards(for: canvasSize)
    let _ = store.imageCacheRevision
    let _ = store.historyRevision
    let prefetchKey = imagePrefetchKey(for: canvasSize, zoom: zoom)

    return ZStack(alignment: .topLeading) {
      ForEach(cards) { card in
        let layoutFrame = cardLayoutFrame(card)
        let liveFrame = cardDisplayFrame(card)
        let screenOrigin = cardScreenOrigin(for: liveFrame, transform: transform)

        canvasCardView(
          card: card,
          displayFrame: layoutFrame,
          canvasSize: canvasSize,
          vaultFiles: vaultFiles
        )
          .frame(width: layoutFrame.width, height: layoutFrame.height)
          .scaleEffect(zoom, anchor: .topLeading)
          .offset(x: screenOrigin.x, y: screenOrigin.y)
          .transaction { transaction in
            transaction.disablesAnimations = true
          }
      }
    }
    .task(id: prefetchKey) {
      await prefetchVisibleImages(canvasSize: canvasSize)
    }
    .onChange(of: displayTransform) { _, _ in
      handleViewportChanged(canvasSize: canvasSize)
    }
    .onChange(of: store.hoverCardID) { _, _ in
      if store.isConnectingLine {
        expandMountedContent(for: canvasSize)
      }
    }
    .allowsHitTesting(!timelapsePlaying)
    .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
  }

  private func imagePrefetchKey(for canvasSize: CGSize, zoom: CGFloat) -> String {
    let pad = canvasViewportPadding() + CanvasConstants.prefetchViewportPadding
    let imageIDs = computeVisibleCardIDs(for: canvasSize, padding: pad)
      .filter { id in store.cards.first(where: { $0.id == id })?.kind == .image }
      .sorted()
      .joined(separator: ",")
    return "\(imageIDs)|\(String(format: "%.3f", zoom))"
  }

  private func prefetchVisibleImages(canvasSize: CGSize) async {
    let strictPad = canvasViewportPadding()
    let prefetchPad = strictPad + CanvasConstants.prefetchViewportPadding
    let strictIDs = computeVisibleCardIDs(for: canvasSize, padding: strictPad)
    let prefetchIDs = computeVisibleCardIDs(for: canvasSize, padding: prefetchPad)

    var pinKeys = Set<String>()
    for card in store.cards where strictIDs.contains(card.id) && card.kind == .image {
      pinKeys.insert(CanvasImageCache.keyString(forCardID: card.id, content: card.content))
    }
    await MainActor.run {
      CanvasImageCache.shared.setPinnedKeys(pinKeys)
    }

    let centerWorld = store.screenToWorld(
      CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
      in: canvasSize,
      transform: displayTransform
    )

    func cardCenter(_ card: CanvasCard) -> CGPoint {
      if let frame = interaction.cardResizeOverrides[card.id] {
        return CGPoint(x: frame.midX, y: frame.midY)
      }
      let origin = interaction.cardDragOverrides[card.id] ?? CGPoint(x: card.x, y: card.y)
      return CGPoint(x: origin.x + card.width / 2, y: origin.y + card.height / 2)
    }

    func distance(from card: CanvasCard) -> CGFloat {
      let c = cardCenter(card)
      return hypot(c.x - centerWorld.x, c.y - centerWorld.y)
    }

    let strictImages = store.cards
      .filter { strictIDs.contains($0.id) && $0.kind == .image }
      .sorted { distance(from: $0) < distance(from: $1) }
    let ringImages = store.cards
      .filter { prefetchIDs.contains($0.id) && !strictIDs.contains($0.id) && $0.kind == .image }
      .sorted { distance(from: $0) < distance(from: $1) }

    var loadedAnyImage = false

    for card in strictImages + ringImages {
      let loaded = await CanvasImageCache.shared.prepareDisplayImageIfNeeded(
        forCardID: card.id,
        content: card.content,
        vaultURL: effectiveVaultURL
      )
      if loaded { loadedAnyImage = true }
    }

    let visibleNotes = store.cards.filter { prefetchIDs.contains($0.id) && $0.kind != .image }
    for card in visibleNotes {
      guard let vault = effectiveVaultURL else { continue }
      let markdown = CanvasCardContent.markdownBody(for: card, vaultURL: vault, vaultFiles: [])
      for path in NoteCardEmbedSupport.imagePaths(from: markdown, vaultURL: vault) {
        let loaded = await CanvasImageCache.shared.prepareDisplayImageIfNeeded(
          forCardID: "note-embed|\(path)",
          content: path,
          vaultURL: vault
        )
        if loaded { loadedAnyImage = true }
      }
    }

    if loadedAnyImage {
      await MainActor.run { store.imageCacheRevision += 1 }
    }
  }

  private func cardUsesInteractiveChrome(_ card: CanvasCard) -> Bool {
    store.selectedCardID == card.id
      || store.focusCardID == card.id
      || interaction.cardResizeOverrides[card.id] != nil
  }

  private func handleCardDragBegan(cardID: String) {
    interaction.beginDraggingCard(cardID, frozenTransform: displayTransform)
  }

  private func handleCardMove(cardID: String, preview: CGPoint) {
    if var frame = interaction.cardResizeOverrides[cardID] {
      frame.origin = preview
      interaction.cardResizeOverrides[cardID] = frame
    } else {
      interaction.cardDragOverrides[cardID] = preview
    }
  }

  private func handleCardMoveEnd(cardID: String) {
    if let frame = interaction.cardResizeOverrides[cardID] {
      store.resizeCard(cardID, frame: frame)
      interaction.cardResizeOverrides.removeValue(forKey: cardID)
    } else if let origin = interaction.cardDragOverrides[cardID] {
      store.moveCard(cardID, to: origin)
      interaction.cardDragOverrides.removeValue(forKey: cardID)
    }
    interaction.suppressCanvasTapUntil = Date().addingTimeInterval(0.35)
    interaction.endCardDragOrResize()
    endCardInteractionFreeze()
    settleMountedContent()
  }

  @ViewBuilder
  private func canvasCardView(
    card: CanvasCard,
    displayFrame: CGRect,
    canvasSize: CGSize,
    vaultFiles: [VaultFile]
  ) -> some View {
    if cardUsesInteractiveChrome(card) {
      interactiveCanvasCardView(
        card: card,
        displayFrame: displayFrame,
        canvasSize: canvasSize,
        vaultFiles: vaultFiles
      )
    } else {
      compactCanvasCardView(
        card: card,
        displayFrame: displayFrame,
        canvasSize: canvasSize,
        vaultFiles: vaultFiles
      )
    }
  }

  private func zoomCardToSelection(_ card: CanvasCard, canvasSize: CGSize) {
    store.selectedCardID = card.id
    store.zoomToSelection(canvasSize: canvasSize)
    displayTransform = store.transform
  }

  private func renameCardTitle(_ card: CanvasCard) {
    store.selectedCardID = card.id
    imageTitleRenameTokens[card.id, default: 0] += 1
  }

  private func removeCard(_ card: CanvasCard) {
    guard entitlements.requireWriteAccess(context: documentTitle) else { return }
    store.deleteCard(card.id)
  }

  private func beginImageSwap(for card: CanvasCard) {
    guard entitlements.requireWriteAccess(context: documentTitle) else { return }
    swapImageCardID = card.id
    #if os(macOS)
    openMacImageSwapPanel(for: card.id)
    #else
    showImageSwapPicker = true
    #endif
  }

  @ViewBuilder
  private func compactCanvasCardView(
    card: CanvasCard,
    displayFrame: CGRect,
    canvasSize: CGSize,
    vaultFiles: [VaultFile]
  ) -> some View {
    let cardView = CanvasCardCompactView(
      card: card,
      displayFrame: displayFrame,
      zoom: cardRenderTransform.zoom,
      vaultURL: effectiveVaultURL,
      vaultFiles: vaultFiles,
      isLinkTarget: store.hoverCardID == card.id,
      isConnectingLine: store.isConnectingLine,
      imageCacheRevision: store.imageCacheRevision,
      onImageLoaded: {
        store.imageCacheRevision += 1
        if card.kind != .image {
          store.fitNoteCardToContent(for: card.id)
        }
      },
      onUpdateContent: { store.updateContent(for: card.id, content: $0) },
      onSelect: { store.selectCard(card.id) },
      onRequestEdit: {
        beginCardEdit(for: card)
      },
      onDragBegan: { handleCardDragBegan(cardID: card.id) },
      onMove: { handleCardMove(cardID: card.id, preview: $0) },
      onMoveEnd: { handleCardMoveEnd(cardID: card.id) }
    )

    CanvasCardContextMenuAttachment.apply(
      to: cardView,
      card: card,
      workspace: workspace,
      store: store,
      entitlements: entitlements,
      sidebarVisible: $sidebarVisible,
      sidebarPanel: $sidebarPanel,
      onZoom: { zoomCardToSelection(card, canvasSize: canvasSize) },
      onRemove: { removeCard(card) },
      onRename: { renameCardTitle(card) },
      onSwap: card.kind == .image ? { beginImageSwap(for: card) } : nil
    )
  }

  @ViewBuilder
  private func interactiveCanvasCardView(
    card: CanvasCard,
    displayFrame: CGRect,
    canvasSize: CGSize,
    vaultFiles: [VaultFile]
  ) -> some View {
    let cardView = CanvasCardView(
      card: card,
      displayFrame: displayFrame,
      isSelected: store.selectedCardID == card.id,
      isLinkTarget: store.hoverCardID == card.id,
      isConnectingLine: store.isConnectingLine,
      zoom: cardRenderTransform.zoom,
      vaultURL: effectiveVaultURL,
      vaultFiles: vaultFiles,
      onSelect: {
        store.selectCard(card.id)
      },
      onDragBegan: { handleCardDragBegan(cardID: card.id) },
      onMove: { handleCardMove(cardID: card.id, preview: $0) },
      onMoveEnd: { handleCardMoveEnd(cardID: card.id) },
      onResize: { interaction.cardResizeOverrides[card.id] = $0 },
      onResizeBegan: {
        interaction.beginResizingCard(card.id, frozenTransform: displayTransform)
      },
      onResizeEnd: {
        if let frame = interaction.cardResizeOverrides[card.id] {
          store.resizeCard(card.id, frame: frame)
          interaction.cardResizeOverrides.removeValue(forKey: card.id)
        }
        interaction.endCardDragOrResize()
        endCardInteractionFreeze()
        settleMountedContent()
      },
      onDelete: {
        guard entitlements.requireWriteAccess(context: documentTitle) else { return }
        store.deleteCard(card.id)
      },
      onZoomToCard: {
        clearCardInteractionState()
        interaction.endCanvasNavigation()
        store.zoomToSelection(canvasSize: canvasSize)
        displayTransform = store.transform
      },
      onBeginConnect: { side in
        guard entitlements.requireWriteAccess(context: documentTitle) else { return }
        store.beginConnecting(
          fromID: card.id,
          side: side,
          positionOverrides: interaction.cardDragOverrides,
          resizeOverrides: interaction.cardResizeOverrides
        )
      },
      onUpdateConnect: { screen in
        store.updateConnecting(
          to: store.screenToWorld(screen, in: canvasSize, transform: displayTransform),
          positionOverrides: interaction.cardDragOverrides,
          resizeOverrides: interaction.cardResizeOverrides
        )
      },
      onEndConnect: { screen, moved in
        store.finishConnecting(
          at: store.screenToWorld(screen, in: canvasSize, transform: displayTransform),
          moved: moved,
          screenPoint: screen,
          positionOverrides: interaction.cardDragOverrides,
          resizeOverrides: interaction.cardResizeOverrides
        )
      },
      onUpdateContent: { store.updateContent(for: card.id, content: $0) },
      onUpdateTitle: { store.updateTitle(for: card.id, title: $0) },
      shouldAutoFocus: store.focusCardID == card.id,
      onDidFocus: {},
      onBeginContentEdit: {
        guard entitlements.canWrite else {
          entitlements.presentPaywall(.editBlocked, context: documentTitle)
          return
        }
        store.beginContentEdit(for: card.id)
      },
      onEndContentEdit: { store.endContentEdit() },
      beginTitleRenameToken: imageTitleRenameTokens[card.id] ?? 0,
      isEditing: store.focusCardID == card.id,
      isColorPickerOpen: store.selectedCardID == card.id && cardToolbarColorRowOpen,
      imageCacheRevision: store.imageCacheRevision,
      onImageLoaded: {
        store.imageCacheRevision += 1
        if card.kind != .image {
          store.fitNoteCardToContent(for: card.id)
        }
      },
      onRequestEdit: {
        beginCardEdit(for: card)
      }
    )

    CanvasCardContextMenuAttachment.apply(
      to: cardView,
      card: card,
      workspace: workspace,
      store: store,
      entitlements: entitlements,
      sidebarVisible: $sidebarVisible,
      sidebarPanel: $sidebarPanel,
      onZoom: { zoomCardToSelection(card, canvasSize: canvasSize) },
      onRemove: { removeCard(card) },
      onRename: { renameCardTitle(card) },
      onSwap: card.kind == .image ? { beginImageSwap(for: card) } : nil
    )
  }

  @ViewBuilder
  private func canvasNoteEditOverlay(canvasSize: CGSize, vaultFiles: [VaultFile]) -> some View {
    if entitlements.canWrite,
       let focusID = store.focusCardID,
       let card = cardIndex[focusID],
       card.kind != .image {
      noteEditOverlay(for: card, focusID: focusID, vaultFiles: vaultFiles, canvasSize: canvasSize)
    }
  }

  @ViewBuilder
  private func noteEditOverlay(
    for card: CanvasCard,
    focusID: String,
    vaultFiles: [VaultFile],
    canvasSize: CGSize
  ) -> some View {
    let worldFrame = cardDisplayFrame(card)
    let zoom = displayTransform.zoom
    let screenOrigin = cardScreenOrigin(for: worldFrame, transform: displayTransform)
    let screenW = worldFrame.width * zoom
    let screenH = worldFrame.height * zoom
    let screenCenter = CGPoint(x: screenOrigin.x + screenW / 2, y: screenOrigin.y + screenH / 2)
    let editFontSize = noteEditFontSize ?? (CanvasConstants.noteCardFontSize * zoom)
    let markdownBody = CanvasCardContent.markdownBody(
      for: card,
      vaultURL: effectiveVaultURL,
      vaultFiles: vaultFiles
    )
    let cardSize = CGSize(width: screenW, height: screenH)
    let onTextEdited: (String, Bool) -> Void = { content, fromUndo in
      store.updateContent(for: focusID, content: content, fromTextUndo: fromUndo)
    }
    let onDismiss: () -> Void = {
      store.endContentEdit()
      store.focusCardID = nil
    }

    noteEditOverlayView(
      markdownBody: markdownBody,
      cardSize: cardSize,
      colorHex: card.colorHex,
      fontSize: editFontSize,
      vaultURL: effectiveVaultURL,
      onTextEdited: onTextEdited,
      onDismiss: onDismiss
    )
    .frame(width: screenW, height: screenH)
    .position(screenCenter)
    .zIndex(250)
    .onAppear {
      noteEditFontSize = CanvasConstants.noteCardFontSize * zoom
    }
    .onChange(of: displayTransform.zoom) { _, newZoom in
      if store.focusCardID != nil {
        noteEditFontSize = CanvasConstants.noteCardFontSize * newZoom
      }
    }
    .onChange(of: store.focusCardID) { _, newID in
      if newID == nil {
        noteEditFontSize = nil
      } else if noteEditFontSize == nil {
        noteEditFontSize = CanvasConstants.noteCardFontSize * displayTransform.zoom
      }
    }
  }

  @ViewBuilder
  private func noteEditOverlayView(
    markdownBody: String,
    cardSize: CGSize,
    colorHex: String?,
    fontSize: CGFloat,
    vaultURL: URL?,
    onTextEdited: @escaping (String, Bool) -> Void,
    onDismiss: @escaping () -> Void
  ) -> some View {
    CanvasNoteEditOverlay(
      initialText: markdownBody,
      cardSize: cardSize,
      colorHex: colorHex,
      files: workspace.files,
      vaultURL: vaultURL,
      fontSize: fontSize,
      imageCacheRevision: store.imageCacheRevision,
      onTextEdited: onTextEdited,
      onDismiss: onDismiss,
      toolbarBridge: canvasNoteToolbarBridge,
      onImageEmbedSaved: { path in
        Task {
          _ = await CanvasImageCache.shared.prepareDisplayImageIfNeeded(
            forCardID: "note-embed|\(path)",
            content: path,
            vaultURL: vaultURL
          )
          await MainActor.run {
            store.imageCacheRevision += 1
            if let focusID = store.focusCardID {
              store.fitNoteCardToContent(for: focusID)
            }
            store.flushPendingContentEdit()
          }
        }
      },
      onRegisterImageInserter: { inserter in
        noteEditImageInserter = inserter
      }
    )
  }

  private func cardDisplayFrame(_ card: CanvasCard) -> CGRect {
    if let frame = interaction.cardResizeOverrides[card.id] { return frame }
    let origin = interaction.cardDragOverrides[card.id] ?? CGPoint(x: card.x, y: card.y)
    return CGRect(x: origin.x, y: origin.y, width: card.width, height: card.height)
  }

  /// Persisted card frame for the drag target — origin stays fixed while `interaction.cardDragOverrides` moves the view.
  private func cardLayoutFrame(_ card: CanvasCard) -> CGRect {
    if let frame = interaction.cardResizeOverrides[card.id] { return frame }
    return CGRect(x: card.x, y: card.y, width: card.width, height: card.height)
  }

  /// Stable layout origin while dragging — avoids re-positioning the gesture target mid-drag.
  private func cardPositionOrigin(_ card: CanvasCard) -> CGPoint {
    if let frame = interaction.cardResizeOverrides[card.id] { return frame.origin }
    return CGPoint(x: card.x, y: card.y)
  }

  @ViewBuilder
  private func canvasCardToolbarLayer(canvasSize: CGSize) -> some View {
    if let selectedID = store.selectedCardID,
       let card = cardIndex[selectedID],
       !interaction.isCardResizing {
      let worldFrame = cardDisplayFrame(card)
      let transform = cardRenderTransform
      let zoom = transform.zoom
      let screenOrigin = cardScreenOrigin(for: worldFrame, transform: transform)
      let screenW = worldFrame.width * zoom
      let slotScreen = CanvasFloatingToolbarChrome.toolbarSlotHeight(showColorRow: cardToolbarColorRowOpen)
      let toolbarPosition = CGPoint(
        x: screenOrigin.x + screenW / 2,
        y: screenOrigin.y - slotScreen / 2
      )

      CanvasCardFloatingToolbarLayer(
        card: card,
        frameWidth: screenW,
        frameHeight: slotScreen,
        zoom: zoom,
        cardColors: store.cardColors,
        showColorRow: $cardToolbarColorRowOpen,
        showCustomColorPicker: $cardToolbarCustomColorOpen,
        onDelete: {
          if store.focusCardID == card.id {
            store.endContentEdit()
            store.focusCardID = nil
          }
          guard entitlements.requireWriteAccess(context: documentTitle) else { return }
          store.deleteCard(card.id)
        },
        onZoomToCard: {
          clearCardInteractionState()
          interaction.endCanvasNavigation()
          store.zoomToSelection(canvasSize: canvasSize)
          displayTransform = store.transform
        },
        onSetColor: { hex in
          guard entitlements.requireWriteAccess(context: documentTitle) else { return }
          store.setCardColor(card.id, hex: hex)
        },
        onBeginEditingNote: {
          beginCardEdit(for: card)
        },
        onRenameImage: {
          imageTitleRenameTokens[card.id, default: 0] += 1
        }
      )
      .position(toolbarPosition)
      .allowsHitTesting(true)
      .transaction { transaction in
        transaction.disablesAnimations = true
      }
    }

    if let edgeID = store.selectedEdgeID,
       store.selectedCardID == nil,
       let edge = store.edges.first(where: { $0.id == edgeID }),
       !interaction.isCardDragging,
       !interaction.isCardResizing {
      edgeFloatingToolbar(for: edge, canvasSize: canvasSize)
    }
  }

  @ViewBuilder
  private func edgeFloatingToolbar(for edge: CanvasEdge, canvasSize: CGSize) -> some View {
    if let from = cardIndex[edge.fromID],
       let endpoint = store.edgeEndpoint(
        for: edge,
        positionOverrides: interaction.cardDragOverrides,
        resizeOverrides: interaction.cardResizeOverrides
       ) {
      let p1 = CanvasGeometry.anchor(
        for: from,
        side: edge.fromSide,
        overrides: interaction.cardDragOverrides,
        resizeOverrides: interaction.cardResizeOverrides
      )
      let mid = CanvasGeometry.pointOnCurve(
        from: p1,
        fromSide: edge.fromSide,
        to: endpoint.point,
        toSide: endpoint.toSide,
        t: 0.5
      )
      let screen = store.worldToScreen(mid, transform: displayTransform)

      VStack(spacing: 6) {
        CanvasEdgeFloatingToolbar(
          direction: edge.direction,
          hasActiveColor: edge.colorHex != nil && !(edge.colorHex?.isEmpty ?? true),
          showColorRow: $edgeToolbarColorRowOpen,
          onDelete: {
            commitEdgeLabelEditIfNeeded()
            guard entitlements.requireWriteAccess(context: documentTitle) else { return }
            store.deleteEdge(edge.id)
          },
          onZoomToLine: {
            store.zoomToEdge(edge.id, canvasSize: canvasSize)
            displayTransform = store.transform
          },
          onSetDirection: { direction in
            guard entitlements.requireWriteAccess(context: documentTitle) else { return }
            store.setEdgeDirection(edge.id, direction: direction)
          },
          onEditLabel: {
            beginEdgeLabelEdit(edgeID: edge.id)
            edgeLabelDraft = edge.label ?? ""
          }
        )

        if edgeToolbarColorRowOpen {
          CanvasCardColorSwatchRow(
            activeColorHex: edge.colorHex,
            frameWidth: 184,
            zoom: displayTransform.zoom,
            cardColors: store.cardColors,
            showCustomColorPicker: $edgeToolbarCustomColorOpen,
            onSetColor: { hex in
              guard entitlements.requireWriteAccess(context: documentTitle) else { return }
              store.setEdgeColor(edge.id, hex: hex)
            }
          )
          .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        }
      }
      .animation(.spring(response: 0.28, dampingFraction: 0.85), value: edgeToolbarColorRowOpen)
      // Hover above the line so the toolbar never covers it (and drags on the
      // toolbar can't grab the edge underneath).
      .position(x: screen.x, y: max(28, screen.y - 46))
    }
  }

  // MARK: - Gestures

  private var canvasPanGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .named("canvasScreen"))
      .onChanged { value in
        if !interaction.panActive {
          interaction.beginCanvasNavigation(
            anchor: CGSize(width: displayTransform.x, height: displayTransform.y)
          )
          cancelPendingEdgeInteraction()
        }
        displayTransform.x = interaction.panAnchor.width + value.translation.width
        displayTransform.y = interaction.panAnchor.height + value.translation.height
      }
      .onEnded { _ in
        interaction.endCanvasNavigation()
        finishCanvasInteraction()
      }
  }

  private func cancelPendingEdgeInteraction() {
    pendingEdgeInteractionID = nil
    edgeInteractionStartLocation = nil
  }

  private func lineHitRadius(for zoom: CGFloat) -> CGFloat {
    max(8, min(28, 18 / max(zoom, 0.25)))
  }

  private func connectHandleHitRadiusPixels() -> CGFloat {
    #if os(iOS)
    CanvasPencilInteraction.connectHitPixels / 2
    #else
    15
    #endif
  }

  private func connectHandleScreenCenter(for card: CanvasCard, side: CanvasSide) -> CGPoint {
    let liveFrame = cardDisplayFrame(card)
    let transform = cardRenderTransform
    let origin = cardScreenOrigin(for: liveFrame, transform: transform)
    let zoom = transform.zoom
    let width = liveFrame.width * zoom
    let height = liveFrame.height * zoom
    switch side {
    case .top:
      return CGPoint(x: origin.x + width / 2, y: origin.y)
    case .bottom:
      return CGPoint(x: origin.x + width / 2, y: origin.y + height)
    case .left:
      return CGPoint(x: origin.x, y: origin.y + height / 2)
    case .right:
      return CGPoint(x: origin.x + width, y: origin.y + height / 2)
    }
  }

  private func isPointOnSelectedCardConnectHandle(_ screenPoint: CGPoint) -> Bool {
    guard let selectedID = store.selectedCardID,
          let card = cardIndex[selectedID],
          cardUsesInteractiveChrome(card) else { return false }

    let hitRadius = connectHandleHitRadiusPixels()
    for side in CanvasSide.allCases {
      let center = connectHandleScreenCenter(for: card, side: side)
      if hypot(screenPoint.x - center.x, screenPoint.y - center.y) <= hitRadius {
        return true
      }
    }
    return false
  }

  private func shouldDeferEdgeHitTest(at screenPoint: CGPoint, for edge: CanvasEdge) -> Bool {
    guard let selectedID = store.selectedCardID,
          let card = cardIndex[selectedID],
          cardUsesInteractiveChrome(card) else { return false }

    if edge.fromID == selectedID,
       isNearConnectHandle(screenPoint, cardID: selectedID, side: edge.fromSide) {
      return true
    }
    if edge.toID == selectedID,
       let toSide = edge.toSide,
       isNearConnectHandle(screenPoint, cardID: selectedID, side: toSide) {
      return true
    }
    return false
  }

  private func isNearConnectHandle(_ screenPoint: CGPoint, cardID: String, side: CanvasSide) -> Bool {
    guard let card = cardIndex[cardID] else { return false }
    let center = connectHandleScreenCenter(for: card, side: side)
    return hypot(screenPoint.x - center.x, screenPoint.y - center.y) <= connectHandleHitRadiusPixels()
  }

  private func pinchGesture(in size: CGSize) -> some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if interaction.pinchStartZoom == nil {
          if interaction.mode == .idle {
            interaction.mode = .canvasNavigation
          }
          interaction.pinchStartZoom = displayTransform.zoom
        }
        let anchor = CGPoint(x: size.width / 2, y: size.height / 2)
        let startZoom = interaction.pinchStartZoom ?? displayTransform.zoom
        let newZoom = min(CanvasViewTransform.maxZoom, max(CanvasViewTransform.minZoom, startZoom * value))
        applyZoom(at: anchor, targetZoom: newZoom)
      }
      .onEnded { _ in
        interaction.pinchStartZoom = nil
        finishCanvasInteraction()
      }
  }

  private func applyZoom(at anchor: CGPoint, factor: CGFloat) {
    let t = displayTransform
    let newZoom = min(CanvasViewTransform.maxZoom, max(CanvasViewTransform.minZoom, t.zoom * factor))
    applyZoom(at: anchor, targetZoom: newZoom)
  }

  private func applyZoom(at anchor: CGPoint, targetZoom: CGFloat) {
    guard !interaction.isCardDragging, !interaction.isCardResizing else { return }
    var t = displayTransform
    let newZoom = min(CanvasViewTransform.maxZoom, max(CanvasViewTransform.minZoom, targetZoom))
    let ratio = newZoom / t.zoom
    t.x = anchor.x - (anchor.x - t.x) * ratio
    t.y = anchor.y - (anchor.y - t.y) * ratio
    t.zoom = newZoom
    displayTransform = t
  }

  private func settleMountedContent() {
    let size = store.viewportSize
    guard size.width > 0, size.height > 0 else { return }
    replaceMountedContent(for: size)
  }

  private func finishCanvasInteraction() {
    // Only the designated owner persists camera into the shared document snapshot.
    if persistsCamera {
      var transform = displayTransform
      #if os(iOS)
      transform.y += canvasPanYOffsetForKeyboard
      #endif
      store.setTransform(transform)
    }
    interaction.endCanvasNavigation()
    settleMountedContent()
  }

  #if os(iOS)
  private func requestCanvasKeyboardAvoidanceUpdate(canvasSize: CGSize) {
    guard store.focusCardID != nil else { return }
    keyboardAvoidanceTask?.cancel()
    keyboardAvoidanceTask = Task { @MainActor in
      // Coalesce rapid keyboard frame updates into one pass per frame.
      try? await Task.sleep(nanoseconds: 32_000_000)
      guard !Task.isCancelled else { return }
      updateCanvasKeyboardAvoidance(canvasSize: canvasSize, allowEstimatedKeyboard: true)
    }
  }

  private func updateCanvasKeyboardAvoidance(
    canvasSize: CGSize,
    allowEstimatedKeyboard: Bool = false
  ) {
    _ = allowEstimatedKeyboard
    guard store.focusCardID != nil,
          let focusID = store.focusCardID,
          let card = cardIndex[focusID],
          card.kind != .image else {
      clearCanvasKeyboardPanTracking()
      return
    }

    guard noteEditKeyboardObserver.isVisible, noteEditKeyboardObserver.height > 0 else {
      return
    }

    let keyboardOverlap = noteEditKeyboardObserver.height
    let bottomObstruction = keyboardOverlap
      + NoteFormattingToolbarAccessoryContainer.preferredHeight
      + canvasSafeAreaBottom
    let cardRect = noteCardScreenRectBeforeKeyboardPan(for: card)
    let zoom = displayTransform.zoom
    let cardToolbarHeight = (38 + 12) * zoom

    var caretScreenY: CGFloat?
    if let textView = canvasNoteToolbarBridge.textView {
      let editFontSize = noteEditFontSize ?? (CanvasConstants.noteCardFontSize * zoom)
      let caretInCard = NoteEditingChromeSupport.documentCaretRect(in: textView, fontSize: editFontSize)
      caretScreenY = cardRect.minY + 8 + caretInCard.maxY
    }

    let requiredPan = CanvasNoteEditKeyboardAvoidance.requiredPanDeltaY(
      cardScreenRect: cardRect,
      caretScreenY: caretScreenY,
      canvasHeight: canvasSize.height,
      bottomObstructionHeight: bottomObstruction,
      cardToolbarScreenHeight: cardToolbarHeight
    )
    let isInitialPanUp = canvasPanYOffsetForKeyboard < 0.5 && requiredPan > 0.5
    applyCanvasKeyboardPan(requiredPan, animated: isInitialPanUp)
  }

  /// Clears pan bookkeeping without moving the canvas — iPad users prefer the view to stay put after editing.
  private func clearCanvasKeyboardPanTracking() {
    canvasPanYOffsetForKeyboard = 0
  }

  private func applyCanvasKeyboardPan(_ requiredPan: CGFloat, animated: Bool = false) {
    let delta = requiredPan - canvasPanYOffsetForKeyboard
    guard abs(delta) > 0.5 else { return }
    if animated {
      withAnimation(.easeOut(duration: 0.28)) {
        displayTransform.y -= delta
      }
    } else {
      displayTransform.y -= delta
    }
    canvasPanYOffsetForKeyboard = requiredPan
  }
  #endif

  // MARK: - Image import

  private func importDroppedImages(_ providers: [NSItemProvider], at location: CGPoint, canvasSize: CGSize) -> Bool {
    if store.focusCardID != nil {
      return importDroppedImagesIntoFocusedNote(providers)
    }

    guard entitlements.requireWriteAccess(context: documentTitle) else { return false }

    let topLeft = store.screenToWorld(location, in: canvasSize, transform: displayTransform)
    var offset: CGFloat = 0
    var handled = false

    for provider in providers {
      guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
      handled = true
      let place = CGPoint(x: topLeft.x + offset, y: topLeft.y + offset)
      offset += 32

      provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
        guard let data else { return }
        DispatchQueue.main.async {
          store.addImageCard(data: data, title: nil, topLeft: place)
        }
      }
    }
    return handled
  }

  private func importDroppedImagesIntoFocusedNote(_ providers: [NSItemProvider]) -> Bool {
    var handled = false
    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
          || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        handled = true
        NoteImageDropSupport.loadData(from: provider) { data, name in
          insertNoteAttachment(data: data, suggestedName: name)
        }
      }
    }
    return handled
  }

  #if canImport(PhotosUI)
  private func importPickedPhotos(_ items: [PhotosPickerItem], canvasSize: CGSize) async {
    let center = store.screenToWorld(CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), in: canvasSize, transform: displayTransform)
    var offset: CGFloat = 0
    for item in items {
      guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
      let size = ImagePixelSize.from(data: data) ?? .zero
      let displaySize = CanvasLayout.displaySize(for: size)
      let topLeft = CGPoint(
        x: center.x - displaySize.width / 2 + offset,
        y: center.y - displaySize.height / 2 + offset
      )
      await MainActor.run {
        store.addImageCard(data: data, title: nil, topLeft: topLeft)
        offset += 32
      }
    }
    await MainActor.run { photoItems = [] }
  }

  #if os(iOS)
  private func canvasAttachmentMenuAnchor(canvasSize: CGSize) -> NoteInsertAttachmentMenuAnchor? {
    guard showNoteAttachmentMenu,
          let focusID = store.focusCardID,
          let card = cardIndex[focusID],
          card.kind != .image else {
      return nil
    }

    let cardRect = noteCardScreenRect(for: card)
    let menuHeight: CGFloat = 152
    var topLeading = CGPoint(x: cardRect.minX, y: cardRect.maxY + 8)

    if noteEditKeyboardObserver.isVisible, noteEditKeyboardObserver.height > 0 {
      let keyboardTop = canvasSize.height
        - noteEditKeyboardObserver.height
        - NoteFormattingToolbarAccessoryContainer.preferredHeight
        - canvasSafeAreaBottom
      if topLeading.y + menuHeight > keyboardTop - 8 {
        topLeading.y = max(12, cardRect.minY - menuHeight - 8)
      }
    }

    return .noteEditor(topLeading: topLeading)
  }

  private func importNoteAttachmentFile(from result: Result<[URL], Error>) {
    guard case .success(let urls) = result, let url = urls.first else { return }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return }
    insertNoteAttachment(data: data, suggestedName: url.lastPathComponent)
  }
  #endif
  #endif

  private func insertNoteAttachment(data: Data, suggestedName: String?) {
    guard let focusID = store.focusCardID else { return }
    if let noteEditImageInserter, noteEditImageInserter(data, suggestedName) {
      return
    }
    guard let vault = effectiveVaultURL,
          let card = store.cards.first(where: { $0.id == focusID }) else { return }

    let innerWidth = max(1, card.width - NoteCardContentLayout.contentHorizontalPadding)
    guard let path = NoteAttachmentInsertSupport.saveImage(
      data: data,
      suggestedName: suggestedName,
      vaultURL: vault,
      maxWidth: innerWidth
    ) else { return }

    let markdown = CanvasCardContent.markdownBody(
      for: card,
      vaultURL: vault,
      vaultFiles: VaultFile.openableFiles(from: workspace.files)
    )
    let selectedRange = canvasNoteToolbarBridge.textView?.selectedRange
      ?? NSRange(location: (markdown as NSString).length, length: 0)
    let prepared = NoteAttachmentInsertSupport.prepareEmbedInsert(
      path: path,
      in: markdown,
      selectedRange: selectedRange,
      vaultURL: vault
    )
    store.updateContent(for: focusID, content: prepared.text)
    if let textView = canvasNoteToolbarBridge.textView {
      textView.selectedRange = prepared.selectedRange
    }
    Task {
      _ = await CanvasImageCache.shared.prepareDisplayImageIfNeeded(
        forCardID: "note-embed|\(path)",
        content: path,
        vaultURL: vault
      )
      await MainActor.run {
        store.imageCacheRevision += 1
        store.fitNoteCardToContent(for: focusID)
        store.flushPendingContentEdit()
      }
    }
  }

  #if os(macOS)
  private func openMacNoteAttachmentPanel() {
    guard store.focusCardID != nil else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let data = try? Data(contentsOf: url) else { return }
    insertNoteAttachment(data: data, suggestedName: url.lastPathComponent)
  }
  private func openMacImagePanel(canvasSize: CGSize) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }

    let center = store.screenToWorld(CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), in: canvasSize, transform: displayTransform)
    var offset: CGFloat = 0
    for url in panel.urls {
      guard let image = NSImage(contentsOf: url) else { continue }
      let pixelSize = ImagePixelSize.from(image: image)
      let displaySize = CanvasLayout.displaySize(for: pixelSize)
      let topLeft = CGPoint(
        x: center.x - displaySize.width / 2 + offset,
        y: center.y - displaySize.height / 2 + offset
      )
      store.addImageCard(image: image, title: url.lastPathComponent, topLeft: topLeft)
      offset += 32
    }
  }

  private func openMacImageSwapPanel(for cardID: String) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else {
      swapImageCardID = nil
      return
    }
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
      swapImageCardID = nil
      return
    }
    store.swapImageCard(cardID, data: data, suggestedTitle: url.lastPathComponent)
    swapImageCardID = nil
  }
  #endif

  private func importSwappedImage(from result: Result<[URL], Error>) {
    defer {
      swapImageCardID = nil
      showImageSwapPicker = false
    }
    guard let cardID = swapImageCardID else { return }
    guard case .success(let urls) = result, let url = urls.first else { return }
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }
    guard let data = try? Data(contentsOf: url) else { return }
    store.swapImageCard(cardID, data: data, suggestedTitle: url.lastPathComponent)
  }

  // MARK: - Timelapse

  private func canvasTimelapseChrome(canvasSize: CGSize) -> some View {
    TimelapseWandButton(
      isPlaying: timelapsePlaying,
      isDisabled: store.cards.isEmpty && !timelapsePlaying,
      onToggle: {
        if timelapsePlaying {
          stopCanvasTimelapse(showAll: true, canvasSize: canvasSize)
        } else {
          startCanvasTimelapse(canvasSize: canvasSize)
        }
      },
      tooltipAnchor: .leading(caretCenterX: 18)
    )
    .padding(14)
  }

  private var activeCanvasFile: WorkspaceFileEntry? {
    if let path = store.documentRelativePath {
      return workspace.files.first { $0.relativePath == path && $0.kind == .canvas }
    }
    if let fileID = workspace.activeTab?.fileID {
      return workspace.files.first { $0.id == fileID && $0.kind == .canvas }
    }
    return nil
  }

  private func scheduleOnboardingTimelapseIfNeeded(canvasSize: CGSize) {
    guard OnboardingPersistence.consumeAutoPlayTimelapse() else { return }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 900_000_000)
      guard !timelapsePlaying else { return }
      startCanvasTimelapse(canvasSize: canvasSize)
    }
  }

  private func startCanvasTimelapse(canvasSize: CGSize) {
    stopCanvasTimelapse(showAll: false)
    let timeline = CanvasTimelapseTimeline.build(
      cards: store.cards,
      edges: store.edges,
      files: workspace.files,
      vaultURL: effectiveVaultURL,
      canvasRelativePath: store.documentRelativePath,
      canvasCreatedAt: activeCanvasFile?.createdAt
    )
    guard !timeline.isEmpty else { return }

    store.selectedCardID = nil
    store.selectedEdgeID = nil
    store.focusCardID = nil
    store.endContentEdit()
    commitEdgeLabelEditIfNeeded()

    timelapsePlaying = true
    timelapseVisibleCardIDs = []
    timelapseVisibleEdgeIDs = []
    timelapseCurrentDate = timeline.start
    timelapseRevision &+= 1

    let delayMs = timeline.stepDelayMs
    timelapseTask = Task { @MainActor in
      for event in timeline.events {
        guard !Task.isCancelled else { return }
        switch event {
        case .card(let id, let at):
          revealTimelapseCard(id: id, at: at)
        case .edge(let id, let at):
          revealTimelapseEdge(id: id, at: at)
        }
        try? await Task.sleep(for: .milliseconds(delayMs))
      }
      guard !Task.isCancelled else { return }
      stopCanvasTimelapse(showAll: true, canvasSize: canvasSize)
    }
  }

  private func revealTimelapseCard(id: String, at: Date) {
    var visible = timelapseVisibleCardIDs ?? []
    visible.insert(id)
    timelapseVisibleCardIDs = visible
    timelapseCurrentDate = at
    timelapseRevision &+= 1
  }

  private func revealTimelapseEdge(id: String, at: Date) {
    var visible = timelapseVisibleEdgeIDs ?? []
    visible.insert(id)
    timelapseVisibleEdgeIDs = visible
    timelapseCurrentDate = at
    timelapseRevision &+= 1
  }

  private func stopCanvasTimelapse(showAll: Bool, canvasSize: CGSize? = nil) {
    timelapseTask?.cancel()
    timelapseTask = nil
    timelapsePlaying = false
    if showAll {
      timelapseVisibleCardIDs = nil
      timelapseVisibleEdgeIDs = nil
      timelapseCurrentDate = nil
      timelapseRevision &+= 1
      if let canvasSize {
        replaceMountedContent(for: canvasSize)
      }
    }
  }

  // MARK: - Chrome

  private func zoomToFitAll(canvasSize: CGSize) {
    clearCardInteractionState()
    interaction.endCanvasNavigation()
    store.zoomToFit(canvasSize: canvasSize)
    displayTransform = store.transform
  }

  private func zoomToSelection(canvasSize: CGSize) {
    clearCardInteractionState()
    interaction.endCanvasNavigation()
    store.zoomToSelection(canvasSize: canvasSize)
    displayTransform = store.transform
  }

  // MARK: - Toolbars

  private var dropOverlay: some View {
    ZStack {
      Color.blue.opacity(0.08)
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
        .foregroundStyle(Color.blue.opacity(0.6))
        .padding(40)
      Text("Drop images at cursor position")
        .foregroundStyle(Color.blue.opacity(0.85))
    }
    .allowsHitTesting(false)
  }

  private func canvasBottomToolbar(canvasSize: CGSize, safeAreaBottom: CGFloat = 0) -> some View {
    #if os(iOS)
    obsidianBottomToolbar(canvasSize: canvasSize, safeAreaBottom: safeAreaBottom)
    #else
    macBottomToolbar(canvasSize: canvasSize, safeAreaBottom: safeAreaBottom)
    #endif
  }

  private func macBottomToolbar(canvasSize: CGSize, safeAreaBottom: CGFloat = 0) -> some View {
    CanvasIPadBottomToolbar(
      imageSystemName: "photo.on.rectangle.angled",
      safeAreaBottom: safeAreaBottom,
      isWriteEnabled: entitlements.canWrite,
      onWriteBlocked: { entitlements.presentPaywall(.editBlocked, context: documentTitle) },
      onAddCard: {
        guard entitlements.canWrite else {
          entitlements.presentPaywall(.editBlocked, context: documentTitle)
          return
        }
        store.addCompactNoteAtCenter(canvasSize: canvasSize, transform: displayTransform)
        store.focusCardID = store.selectedCardID
      },
      onVaultNote: {
        store.setVaultFiles(workspace.files)
        store.isVaultOpen = true
        store.vaultSearchQuery = ""
        store.vaultSelectedIndex = 0
      },
      onAddImage: {
        #if canImport(PhotosUI)
        showImagePicker = true
        #else
        openMacImagePanel(canvasSize: canvasSize)
        #endif
      }
    )
  }

  #if os(iOS)
  private func obsidianBottomToolbar(canvasSize: CGSize, safeAreaBottom: CGFloat = 0) -> some View {
    CanvasIPadBottomToolbar(
      imageSystemName: "photo.on.rectangle.angled",
      safeAreaBottom: safeAreaBottom,
      isWriteEnabled: entitlements.canWrite,
      onWriteBlocked: { entitlements.presentPaywall(.editBlocked, context: documentTitle) },
      onAddCard: {
        guard entitlements.canWrite else {
          entitlements.presentPaywall(.editBlocked, context: documentTitle)
          return
        }
        store.addCompactNoteAtCenter(canvasSize: canvasSize, transform: displayTransform)
        store.focusCardID = store.selectedCardID
      },
      onVaultNote: {
        store.setVaultFiles(workspace.files)
        store.isVaultOpen = true
        store.vaultSearchQuery = ""
        store.vaultSelectedIndex = 0
      },
      onAddImage: {
        #if canImport(PhotosUI)
        showImagePicker = true
        #endif
      }
    )
  }
  #endif

  private func canvasRightToolbar(canvasSize: CGSize) -> some View {
    #if os(iOS)
    obsidianRightToolbar(canvasSize: canvasSize)
    #else
    macRightToolbar(canvasSize: canvasSize)
    #endif
  }

  private func macRightToolbar(canvasSize: CGSize) -> some View {
    let _ = store.historyRevision
    return VStack(alignment: .trailing, spacing: 10) {
      floatingChromePill {
        canvasToolButton("gearshape", tip: "Canvas settings") {
          showCanvasSettings.toggle()
        }
      }
      .popover(isPresented: $showCanvasSettings, arrowEdge: .trailing) {
        canvasSettingsPanel(canvasSize: canvasSize)
      }

      floatingChromePill {
        VStack(spacing: 0) {
          canvasToolButton(
            "plus",
            tip: "Zoom in",
            enabled: displayTransform.zoom < CanvasViewTransform.maxZoom
          ) {
            stepZoom(factor: 1.15, canvasSize: canvasSize)
          }
          canvasToolButton("arrow.clockwise", tip: "Reset zoom") {
            resetCanvasView()
          }
          canvasToolButton("viewfinder", tip: "Zoom to fit") {
            zoomToFitAll(canvasSize: canvasSize)
          }
          canvasToolButton(
            "minus",
            tip: "Zoom out",
            enabled: displayTransform.zoom > CanvasViewTransform.minZoom
          ) {
            stepZoom(factor: 0.85, canvasSize: canvasSize)
          }
        }
      }

      Spacer(minLength: 0)

      floatingChromePill {
        VStack(spacing: 0) {
          canvasToolButton("arrow.uturn.backward", tip: "Undo", enabled: store.canUndo) {
            store.undo()
          }
          canvasToolButton("arrow.uturn.forward", tip: "Redo", enabled: store.canRedo) {
            store.redo()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .padding(.top, 22)
    .padding(.bottom, 72)
    .padding(.trailing, 12)
  }

  #if os(iOS)
  private func obsidianRightToolbar(canvasSize: CGSize) -> some View {
    let _ = store.historyRevision
    return CanvasIPadRightToolbar(
      canvasSize: canvasSize,
      sidebarVisible: sidebarVisible,
      canUndo: store.canUndo,
      canRedo: store.canRedo,
      canZoomIn: displayTransform.zoom < CanvasViewTransform.maxZoom,
      canZoomOut: displayTransform.zoom > CanvasViewTransform.minZoom,
      onSettings: { showCanvasSettings = true },
      onZoomIn: { stepZoom(factor: 1.15, canvasSize: canvasSize) },
      onResetZoom: { resetCanvasView() },
      onZoomToFit: { zoomToFitAll(canvasSize: canvasSize) },
      onZoomOut: { stepZoom(factor: 0.85, canvasSize: canvasSize) },
      onUndo: { store.undo() },
      onRedo: { store.redo() }
    )
    .sheet(isPresented: $showCanvasSettings) {
      NavigationStack {
        canvasSettingsPanel(canvasSize: canvasSize)
          .navigationTitle("Canvas settings")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { showCanvasSettings = false }
            }
          }
      }
      .presentationDetents([.medium, .large])
    }
  }
  #endif

  private func canvasSettingsPanel(canvasSize: CGSize) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        AppearanceSettingsSection()

        Toggle("Show dot grid", isOn: $showCanvasGrid)
          .toggleStyle(.switch)

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Zoom")
            Spacer()
            Text("\(Int(displayTransform.zoom * 100))%")
              .foregroundStyle(AppColors.textSecondary)
          }
          Slider(
            value: Binding(
              get: { displayTransform.zoom },
              set: { newZoom in
                if interaction.mode == .idle {
                  interaction.mode = .canvasNavigation
                }
                applyZoom(
                  at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
                  targetZoom: newZoom
                )
                finishCanvasInteraction()
              }
            ),
            in: CanvasViewTransform.minZoom...CanvasViewTransform.maxZoom
          )
        }

        HStack {
          Button("Reset view") {
            resetCanvasView()
          }
          Button("Zoom to fit") {
            zoomToFitAll(canvasSize: canvasSize)
          }
        }
      }
      .font(.system(size: 12.5))
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    #if os(macOS)
    .frame(width: 260)
    #endif
  }

  private func stepZoom(factor: CGFloat, canvasSize: CGSize) {
    if interaction.mode == .idle {
      interaction.mode = .canvasNavigation
    }
    applyZoom(
      at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
      factor: factor
    )
    finishCanvasInteraction()
  }

  private func resetCanvasView() {
    displayTransform = CanvasViewTransform()
    if persistsCamera {
      store.setTransform(displayTransform)
    }
  }

  private func floatingChromePill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(.vertical, 6)
      .padding(.horizontal, 6)
      .background(AppColors.floatingChrome)
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.floatingChromeBorder, lineWidth: 1))
      .shadow(color: AppColors.floatingChromeShadow, radius: 16, y: 4)
  }

  private func canvasToolButton(
    _ name: String,
    tip: String,
    enabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: name)
        #if os(iOS)
        .font(.system(size: CanvasFloatingToolbarChrome.iconSize, weight: .regular))
        .symbolRenderingMode(.monochrome)
        #else
        .font(.system(size: CanvasFloatingToolbarChrome.iconSize, weight: .regular))
        #endif
        .foregroundStyle(AppColors.textPrimary.opacity(enabled ? 0.92 : 0.35))
        .frame(
          width: CanvasFloatingToolbarChrome.buttonSize,
          height: CanvasFloatingToolbarChrome.buttonSize
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(CanvasToolButtonStyle())
    .disabled(!enabled)
    .help(tip)
  }

  private func zoomIndicator(safeAreaBottom: CGFloat = 0) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let timelapseCurrentDate {
        Text(timelapseCurrentDate.formatted(date: .abbreviated, time: .shortened))
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(AppColors.textPrimary)
      }
      if timelapsePlaying {
        Text("Timelapse · \(timelapseVisibleCardIDs?.count ?? 0)/\(store.cards.count) cards")
          .font(.system(size: 11))
          .foregroundStyle(AppColors.textSecondary)
      } else {
        Text("\(Int(displayTransform.zoom * 100))%")
          .font(.system(size: 11))
          .foregroundStyle(AppColors.textSecondary)
      }
    }
    .padding(.leading, 14)
    .padding(.bottom, max(10, safeAreaBottom + 4))
    .allowsHitTesting(false)
  }

  private func backlinkBadge(safeAreaBottom: CGFloat = 0) -> some View {
    HStack(spacing: 6) {
      Text("\(store.backlinkCount) backlink\(store.backlinkCount == 1 ? "" : "s")")
        .font(.system(size: 12))
      Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
        .foregroundStyle(store.backlinkCount > 0 ? Color.red.opacity(0.7) : AppColors.textSecondary.opacity(0.45))
        .font(.system(size: 11))
    }
    .foregroundStyle(AppColors.textSecondary)
    .padding(.trailing, 14)
    .padding(.bottom, max(10, safeAreaBottom + 4))
    .allowsHitTesting(false)
  }

  private enum ContextMenuLayout {
    static let textSize = CGSize(width: 148, height: 52)
    static let compactSize = CGSize(width: 148, height: 28)
    static let edgeGap: CGFloat = 4
    static let lineHitRadius: CGFloat = 18
    /// Screen points the pointer must move before an edge endpoint detaches for reconnecting.
    static let edgeDragThreshold: CGFloat = 6
  }

  /// Live screen position of the line tip — recomputed from world coords so zoom/pan keep menu attached.
  private func contextMenuTipScreen(_ menu: (screenPoint: CGPoint, kind: CanvasStore.ContextMenuKind)) -> CGPoint {
    switch menu.kind {
    case .endpoint(_, let worldX, let worldY), .canvas(let worldX, let worldY):
      return store.worldToScreen(CGPoint(x: worldX, y: worldY), transform: displayTransform)
    case .handle, .edge:
      return menu.screenPoint
    }
  }

  /// Places menu so the arrow tip meets the menu edge center (Obsidian-style).
  private func contextMenuCenter(for menu: (screenPoint: CGPoint, kind: CanvasStore.ContextMenuKind)) -> CGPoint {
    let tip = contextMenuTipScreen(menu)
    let size = menuSize(for: menu.kind)
    let gap = ContextMenuLayout.edgeGap

    switch menu.kind {
    case .endpoint(let edgeID, _, _):
      guard let edge = store.edges.first(where: { $0.id == edgeID }),
            let from = store.cards.first(where: { $0.id == edge.fromID })
      else {
        return CGPoint(x: tip.x + size.width / 2 + gap, y: tip.y)
      }

      let p1 = CanvasGeometry.anchor(
        for: from,
        side: edge.fromSide,
        overrides: interaction.cardDragOverrides,
        resizeOverrides: interaction.cardResizeOverrides
      )
      let p1Screen = store.worldToScreen(p1, transform: displayTransform)
      let dx = tip.x - p1Screen.x
      let dy = tip.y - p1Screen.y
      let length = max(hypot(dx, dy), 1)
      return menuCenter(
        anchoredAt: tip,
        ux: dx / length,
        uy: dy / length,
        size: size,
        gap: gap
      )

    case .handle, .canvas, .edge:
      return CGPoint(x: tip.x + size.width / 2 + gap, y: tip.y)
    }
  }

  private func menuSize(for kind: CanvasStore.ContextMenuKind) -> CGSize {
    ContextMenuLayout.textSize
  }

  private func menuCenter(anchoredAt tip: CGPoint, ux: CGFloat, uy: CGFloat, size: CGSize, gap: CGFloat) -> CGPoint {
    let w = size.width
    let h = size.height

    if abs(ux) >= abs(uy) {
      return CGPoint(
        x: tip.x + (ux >= 0 ? w / 2 + gap : -w / 2 - gap),
        y: tip.y
      )
    }

    return CGPoint(
      x: tip.x,
      y: tip.y + (uy >= 0 ? h / 2 + gap : -h / 2 - gap)
    )
  }

  private func contextMenuOverlay(
    _ menu: (screenPoint: CGPoint, kind: CanvasStore.ContextMenuKind),
    canvasSize: CGSize
  ) -> some View {
    textContextMenu(menu, canvasSize: canvasSize)
      .position(contextMenuCenter(for: menu))
      .zIndex(100)
  }

  private func endpointMenuCenterWorld(
    _ menu: (screenPoint: CGPoint, kind: CanvasStore.ContextMenuKind),
    canvasSize: CGSize
  ) -> CGPoint {
    store.screenToWorld(
      contextMenuCenter(for: menu),
      in: canvasSize,
      transform: displayTransform
    )
  }

  private func textContextMenu(
    _ menu: (screenPoint: CGPoint, kind: CanvasStore.ContextMenuKind),
    canvasSize: CGSize
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Button {
        guard entitlements.requireWriteAccess() else {
          store.contextMenu = nil
          return
        }
        switch menu.kind {
        case .canvas(let wx, let wy):
          store.addCard(kind: .note, at: CGPoint(x: wx, y: wy))
        case .handle(let id, let side):
          store.addConnectedCard(fromID: id, fromSide: side)
        case .endpoint(let edgeID, _, _):
          store.addCardAtEndpoint(
            edgeID: edgeID,
            atMenuCenter: endpointMenuCenterWorld(menu, canvasSize: canvasSize)
          )
        case .edge(let edgeID):
          store.addCardAtEndpoint(
            edgeID: edgeID,
            atMenuCenter: endpointMenuCenterWorld(menu, canvasSize: canvasSize)
          )
        }
        store.contextMenu = nil
      } label: {
        Text("Add card")
          .font(.system(size: 13))
          .foregroundStyle(Color(hex: 0x1C1C1C))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      switch menu.kind {
      case .canvas, .endpoint, .edge:
        vaultNoteButton(menu, canvasSize: canvasSize)
      default:
        EmptyView()
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(width: menuSize(for: menu.kind).width)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color(hex: 0xC8C8C8))
    )
    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
  }

  private func vaultNoteButton(
    _ menu: (screenPoint: CGPoint, kind: CanvasStore.ContextMenuKind),
    canvasSize: CGSize
  ) -> some View {
    Button {
      switch menu.kind {
      case .canvas(let wx, let wy):
        store.pendingVaultInsertCenter = CGPoint(x: wx, y: wy)
      case .endpoint(let id, _, _), .edge(let id):
        store.pendingEndpointEdgeID = id
        store.pendingEndpointMenuCenter = endpointMenuCenterWorld(menu, canvasSize: canvasSize)
      default:
        break
      }
      store.setVaultFiles(workspace.files)
      store.isVaultOpen = true
      store.vaultSearchQuery = ""
      store.vaultSelectedIndex = 0
      store.contextMenu = nil
    } label: {
      Text("Add note from vault")
        .font(.system(size: 13))
        .foregroundStyle(Color(hex: 0x1C1C1C))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func isPointOnSelectedCardToolbar(_ screenPoint: CGPoint, ignoringDragState: Bool = false) -> Bool {
    guard let selectedID = store.selectedCardID,
          let card = cardIndex[selectedID] else { return false }
    if !ignoringDragState, interaction.isCardDragging || interaction.isCardResizing { return false }

    let worldFrame = cardDisplayFrame(card)
    let rect = CanvasCardFloatingToolbarLayer.screenHitRect(
      worldFrame: worldFrame,
      zoom: displayTransform.zoom,
      showColorRow: cardToolbarColorRowOpen,
      worldToScreen: { store.worldToScreen($0, transform: displayTransform) }
    )
    return rect.insetBy(dx: -6, dy: -6).contains(screenPoint)
  }

  private func isPointOnCanvasToolbar(_ screenPoint: CGPoint, canvasSize: CGSize) -> Bool {
    #if os(iOS)
    let toolbarWidth: CGFloat = 72
    let topControlsHeight: CGFloat = 250
    let historyHeight: CGFloat = 150
    let bottomBarHeight: CGFloat = 64
    let trailing: CGFloat = 18
    let top: CGFloat = 12
    let bottom: CGFloat = 96
    #else
    let toolbarWidth: CGFloat = 44
    let topControlsHeight: CGFloat = 198
    let historyHeight: CGFloat = 76
    let bottomBarHeight: CGFloat = 0
    let trailing: CGFloat = 12
    let top: CGFloat = 22
    let bottom: CGFloat = 72
    #endif

    let topRect = CGRect(
      x: canvasSize.width - trailing - toolbarWidth,
      y: top,
      width: toolbarWidth,
      height: topControlsHeight
    )
    let historyRect = CGRect(
      x: canvasSize.width - trailing - toolbarWidth,
      y: canvasSize.height - bottom - historyHeight,
      width: toolbarWidth,
      height: historyHeight
    )
    let bottomRect = CGRect(
      x: (canvasSize.width - 220) / 2,
      y: canvasSize.height - 20 - bottomBarHeight,
      width: 220,
      height: bottomBarHeight
    )
    return topRect.insetBy(dx: -8, dy: -8).contains(screenPoint)
      || historyRect.insetBy(dx: -8, dy: -8).contains(screenPoint)
      || bottomRect.insetBy(dx: -8, dy: -8).contains(screenPoint)
  }

  private func edgeInteractionGesture(canvasSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasScreen"))
      .onChanged { value in
        guard !timelapsePlaying else { return }
        guard store.contextMenu == nil, !interaction.isCardDragging, !interaction.isCardResizing else { return }
        guard !store.isConnectingLine else { return }
        guard !interaction.isCanvasInteracting, !interaction.panActive else {
          cancelPendingEdgeInteraction()
          return
        }
        guard !isPointOnSelectedCardToolbar(value.startLocation) else { return }
        guard !isPointOnCanvasToolbar(value.startLocation, canvasSize: canvasSize) else { return }
        guard !isPointOnSelectedCardConnectHandle(value.startLocation) else { return }

        if pendingEdgeInteractionID == nil, !edgeInteractionActive, store.editingEdgeID == nil {
          guard let edgeID = hitTestEdge(at: value.startLocation, canvasSize: canvasSize) else { return }
          pendingEdgeInteractionID = edgeID
          edgeInteractionStartLocation = value.startLocation
        }

        if !edgeInteractionActive, store.editingEdgeID == nil,
           let pendingID = pendingEdgeInteractionID,
           let start = edgeInteractionStartLocation {
          let dx = value.location.x - start.x
          let dy = value.location.y - start.y
          let moved = hypot(dx, dy)
          if moved >= ContextMenuLayout.edgeDragThreshold {
            edgeInteractionActive = true
            pendingEdgeInteractionID = nil
            guard entitlements.requireWriteAccess(context: documentTitle) else {
              edgeInteractionActive = false
              return
            }
            store.beginEditingEdgeEndpoint(
              pendingID,
              positionOverrides: interaction.cardDragOverrides,
              resizeOverrides: interaction.cardResizeOverrides
            )
          } else if moved >= 4 {
            cancelPendingEdgeInteraction()
            return
          }
        }

        guard edgeInteractionActive || store.editingEdgeID != nil else { return }
        let world = store.screenToWorld(value.location, in: canvasSize, transform: displayTransform)
        store.updateConnecting(
          to: world,
          positionOverrides: interaction.cardDragOverrides,
          resizeOverrides: interaction.cardResizeOverrides
        )
      }
      .onEnded { value in
        defer {
          edgeInteractionActive = false
          pendingEdgeInteractionID = nil
          edgeInteractionStartLocation = nil
        }

        guard store.contextMenu == nil, !interaction.isCardDragging, !interaction.isCardResizing else { return }
        guard !store.isConnectingLine else { return }
        guard !interaction.isCanvasInteracting, !interaction.panActive else { return }
        guard !isPointOnSelectedCardToolbar(value.startLocation) else { return }
        guard !isPointOnCanvasToolbar(value.startLocation, canvasSize: canvasSize) else { return }
        guard !isPointOnSelectedCardConnectHandle(value.startLocation) else { return }

        if let edgeID = pendingEdgeInteractionID {
          store.selectEdge(edgeID)
          return
        }

        guard edgeInteractionActive || store.editingEdgeID != nil else { return }

        let start = edgeInteractionStartLocation ?? value.startLocation
        let moved = hypot(value.location.x - start.x, value.location.y - start.y) >= ContextMenuLayout.edgeDragThreshold
        let world = store.screenToWorld(value.location, in: canvasSize, transform: displayTransform)
        store.finishConnecting(
          at: world,
          moved: moved,
          screenPoint: value.location,
          positionOverrides: interaction.cardDragOverrides,
          resizeOverrides: interaction.cardResizeOverrides
        )
      }
  }

  /// Hit-test any connection line — grab anywhere on the curve to drag the endpoint.
  private func hitTestEdge(at screenPoint: CGPoint, canvasSize: CGSize) -> String? {
    if isPointOnSelectedCardConnectHandle(screenPoint) { return nil }

    let toScreen = { store.worldToScreen($0, transform: displayTransform) }
    var best: (id: String, distance: CGFloat)?

    for edge in visibleEdges(for: canvasSize) {
      if shouldDeferEdgeHitTest(at: screenPoint, for: edge) { continue }
      guard let from = store.cards.first(where: { $0.id == edge.fromID }),
            let endpoint = store.edgeEndpoint(
              for: edge,
              positionOverrides: interaction.cardDragOverrides,
              resizeOverrides: interaction.cardResizeOverrides
            ) else { continue }

      let p1 = CanvasGeometry.anchor(
        for: from,
        side: edge.fromSide,
        overrides: interaction.cardDragOverrides,
        resizeOverrides: interaction.cardResizeOverrides
      )
      let distance = CanvasGeometry.screenDistanceToEdge(
        screenPoint: screenPoint,
        from: p1,
        fromSide: edge.fromSide,
        to: endpoint.point,
        toSide: endpoint.toSide,
        toScreen: toScreen
      )
      if distance < lineHitRadius(for: displayTransform.zoom),
         best == nil || distance < best!.distance {
        best = (edge.id, distance)
      }
    }
    return best?.id
  }
}

private struct CanvasToolButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(configuration.isPressed ? AppColors.textPrimary : AppColors.textSecondary)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(configuration.isPressed ? AppColors.toolbarButtonPressed : Color.clear)
      )
  }
}

extension Notification.Name {
  static let openImagePanel = Notification.Name("openImagePanel")
}

#if os(macOS)
import AppKit

struct CanvasScrollModifier: ViewModifier {
  var shouldPassScrollToContent: (CGPoint) -> Bool
  var onScroll: (CGSize, CGPoint, Bool, Bool) -> Void

  func body(content: Content) -> some View {
    content.overlay {
      CanvasScrollCaptureView(
        shouldPassScrollToContent: shouldPassScrollToContent,
        onScroll: onScroll
      )
    }
  }
}

private struct CanvasScrollCaptureView: NSViewRepresentable {
  var shouldPassScrollToContent: (CGPoint) -> Bool
  var onScroll: (CGSize, CGPoint, Bool, Bool) -> Void

  func makeNSView(context: Context) -> CanvasScrollNSView {
    let view = CanvasScrollNSView()
    view.shouldPassScrollToContent = shouldPassScrollToContent
    view.onScroll = onScroll
    return view
  }

  func updateNSView(_ nsView: CanvasScrollNSView, context: Context) {
    nsView.shouldPassScrollToContent = shouldPassScrollToContent
    nsView.onScroll = onScroll
  }
}

private final class CanvasScrollNSView: NSView {
  var shouldPassScrollToContent: ((CGPoint) -> Bool)?
  var onScroll: ((CGSize, CGPoint, Bool, Bool) -> Void)?
  private var scrollMonitor: Any?

  override var isFlipped: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    installScrollMonitor()
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { removeScrollMonitor() }
    super.viewWillMove(toWindow: newWindow)
  }

  deinit { removeScrollMonitor() }

  /// Pass clicks through to SwiftUI — scroll is captured via the local monitor.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private var isPointerInsideView: Bool {
    guard let window else { return false }
    let mouse = window.mouseLocationOutsideOfEventStream
    let point = convert(mouse, from: nil)
    return bounds.contains(point)
  }

  private func scrollDelta(from event: NSEvent) -> CGSize {
    if event.hasPreciseScrollingDeltas {
      return CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
    }
    return CGSize(width: event.deltaX * 10, height: event.deltaY * 10)
  }

  private func installScrollMonitor() {
    removeScrollMonitor()
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, self.window != nil, self.isPointerInsideView else { return event }
      let location = self.convert(event.locationInWindow, from: nil)
      if self.shouldPassScrollToContent?(location) == true {
        if CanvasNoteCardScrollBridge.applyScrollDelta != nil {
          let delta = self.scrollDelta(from: event)
          let result = CanvasNoteCardScrollBridge.apply(delta)
          if result.consumed {
            return nil
          }
        } else {
          return event
        }
      }
      self.processScrollEvent(event)
      return nil
    }
  }

  private func removeScrollMonitor() {
    if let scrollMonitor {
      NSEvent.removeMonitor(scrollMonitor)
      self.scrollMonitor = nil
    }
  }

  private func processScrollEvent(_ event: NSEvent, deltaOverride: CGSize? = nil) {
    let location = convert(event.locationInWindow, from: nil)
    let zoomRequested = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
    let delta = deltaOverride ?? scrollDelta(from: event)

    let isLegacyScroll = event.phase == [] && event.momentumPhase == []
    let phaseEnded = isLegacyScroll
      || event.phase == .ended
      || event.phase == .cancelled
      || event.momentumPhase == .ended
      || event.momentumPhase == .cancelled

    onScroll?(delta, location, zoomRequested, phaseEnded)
  }
}

extension View {
  func onCanvasScroll(
    shouldPassToContent: @escaping (CGPoint) -> Bool = { _ in false },
    _ handler: @escaping (CGSize, CGPoint, Bool, Bool) -> Void
  ) -> some View {
    modifier(CanvasScrollModifier(shouldPassScrollToContent: shouldPassToContent, onScroll: handler))
  }

  func canvasEdgeHandCursor(isActive: Bool, isGrabbing: Bool) -> some View {
    modifier(CanvasEdgeHandCursorModifier(isActive: isActive, isGrabbing: isGrabbing))
  }
}

private final class MacCursorStackGate {
    var hasPushed = false

    func push(_ cursor: NSCursor) {
        guard !hasPushed else { return }
        cursor.push()
        hasPushed = true
    }

    func pop() {
        guard hasPushed else { return }
        NSCursor.pop()
        hasPushed = false
    }
}

private struct CanvasEdgeHandCursorModifier: ViewModifier {
  let isActive: Bool
  let isGrabbing: Bool
  @State private var gate = MacCursorStackGate()

  func body(content: Content) -> some View {
    content
      .onChange(of: isActive) { _, active in
        if active {
          gate.push(isGrabbing ? .closedHand : .openHand)
        } else {
          gate.pop()
        }
      }
      .onChange(of: isGrabbing) { _, _ in
        guard isActive else { return }
        gate.pop()
        gate.push(isGrabbing ? .closedHand : .openHand)
      }
      .onDisappear {
        gate.pop()
      }
  }
}
#endif

#if os(iOS)
import UIKit

/// iPad one-finger pan (empty canvas) and pinch zoom. Use `passesThroughHits` when single-finger
/// content (e.g. graph nodes) must stay draggable above this layer.
struct CanvasTouchCaptureView: UIViewRepresentable {
  var passesThroughHits = false
  var isEnabled: Bool
  var blocksNavigationAt: ((CGPoint) -> Bool)? = nil
  var onPan: (CGSize) -> Void
  var onPanBegan: (() -> Void)? = nil
  var onPanEnded: () -> Void
  var onPinchBegan: (CGPoint) -> Void
  var onPinchChanged: (CGFloat, CGPoint) -> Void
  var onPinchEnded: () -> Void
  var onLongPress: ((CGPoint) -> Void)? = nil

  func makeUIView(context: Context) -> CanvasTouchUIView {
    let view = CanvasTouchUIView()
    view.backgroundColor = .clear
    view.isMultipleTouchEnabled = true
    view.passesThroughHits = passesThroughHits
    return view
  }

  func updateUIView(_ uiView: CanvasTouchUIView, context: Context) {
    uiView.passesThroughHits = passesThroughHits
    uiView.navigationEnabled = isEnabled
    uiView.blocksNavigationAt = blocksNavigationAt
    uiView.onPan = onPan
    uiView.onPanBegan = onPanBegan
    uiView.onPanEnded = onPanEnded
    uiView.onPinchBegan = onPinchBegan
    uiView.onPinchChanged = onPinchChanged
    uiView.onPinchEnded = onPinchEnded
    uiView.onLongPress = onLongPress
    uiView.syncLongPressRecognizer()
  }
}

final class CanvasTouchUIView: UIView, UIGestureRecognizerDelegate {
  var passesThroughHits = false
  var navigationEnabled = true {
    didSet {
      panRecognizer?.isEnabled = navigationEnabled
      pinchRecognizer?.isEnabled = navigationEnabled
      longPressRecognizer?.isEnabled = navigationEnabled
    }
  }
  var onPan: ((CGSize) -> Void)?
  var onPanBegan: (() -> Void)?
  var onPanEnded: (() -> Void)?
  var onPinchBegan: ((CGPoint) -> Void)?
  var onPinchChanged: ((CGFloat, CGPoint) -> Void)?
  var onPinchEnded: (() -> Void)?
  var onLongPress: ((CGPoint) -> Void)?
  var blocksNavigationAt: ((CGPoint) -> Bool)?

  private func installLongPressRecognizerIfNeeded() {
    guard onLongPress != nil, longPressRecognizer == nil else { return }
    guard let hostView = passesThroughHits ? window : self else { return }

    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    longPress.minimumPressDuration = 0.45
    longPress.allowableMovement = 14
    longPress.cancelsTouchesInView = false
    longPress.delaysTouchesBegan = false
    longPress.allowedTouchTypes = [
      NSNumber(value: UITouch.TouchType.direct.rawValue),
      NSNumber(value: UITouch.TouchType.pencil.rawValue),
    ]
    longPress.delegate = self
    hostView.addGestureRecognizer(longPress)
    longPressRecognizer = longPress
  }

  func syncLongPressRecognizer() {
    if onLongPress != nil {
      installLongPressRecognizerIfNeeded()
    } else if let longPress = longPressRecognizer {
      (passesThroughHits ? window : self)?.removeGestureRecognizer(longPress)
      longPressRecognizer = nil
    }
  }

  private var panRecognizer: UIPanGestureRecognizer?
  private var pinchRecognizer: UIPinchGestureRecognizer?
  private var longPressRecognizer: UILongPressGestureRecognizer?
  private weak var gestureHost: UIView?
  private var didInstallGestures = false

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      uninstallGestures()
      return
    }
    installGesturesIfNeeded()
  }

  private func installGesturesIfNeeded() {
    guard !didInstallGestures else { return }
    didInstallGestures = true

    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    pan.minimumNumberOfTouches = 1
    pan.maximumNumberOfTouches = 1
    pan.cancelsTouchesInView = false
    pan.delaysTouchesBegan = false
    pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    pan.delegate = self

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    pinch.cancelsTouchesInView = false
    pinch.delaysTouchesBegan = false
    pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    pinch.delegate = self

    if passesThroughHits, let window {
      window.addGestureRecognizer(pan)
      window.addGestureRecognizer(pinch)
      gestureHost = window
    } else {
      addGestureRecognizer(pan)
      addGestureRecognizer(pinch)
      gestureHost = self
    }

    panRecognizer = pan
    pinchRecognizer = pinch
    installLongPressRecognizerIfNeeded()
  }

  private func uninstallGestures() {
    guard didInstallGestures else { return }
    if let pan = panRecognizer {
      gestureHost?.removeGestureRecognizer(pan)
    }
    if let pinch = pinchRecognizer {
      gestureHost?.removeGestureRecognizer(pinch)
    }
    if let longPress = longPressRecognizer {
      gestureHost?.removeGestureRecognizer(longPress)
    }
    panRecognizer = nil
    pinchRecognizer = nil
    longPressRecognizer = nil
    gestureHost = nil
    didInstallGestures = false
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !passesThroughHits else { return nil }
    guard navigationEnabled, bounds.contains(point) else { return nil }
    return self
  }

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard navigationEnabled else { return false }
    let point = gestureRecognizer.location(in: self)
    guard bounds.contains(point) else { return false }
    if gestureRecognizer !== longPressRecognizer, blocksNavigationAt?(point) == true {
      return false
    }
    return true
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    if gestureRecognizer === longPressRecognizer {
      return navigationEnabled
    }
    guard navigationEnabled else { return false }
    let point = touch.location(in: self)
    if blocksNavigationAt?(point) == true { return false }
    // Finger navigates the canvas; Apple Pencil selects, connects, and edits.
    return touch.type == .direct
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    true
  }

  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      onPanBegan?()
    case .changed:
      let delta = gesture.translation(in: self)
      gesture.setTranslation(.zero, in: self)
      onPan?(CGSize(width: delta.x, height: delta.y))
    case .ended, .cancelled, .failed:
      onPanEnded?()
    default:
      break
    }
  }

  @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    let anchor = gesture.location(in: self)
    switch gesture.state {
    case .began:
      onPinchBegan?(anchor)
    case .changed:
      onPinchChanged?(gesture.scale, anchor)
    case .ended, .cancelled, .failed:
      gesture.scale = 1
      onPinchEnded?()
    default:
      break
    }
  }

  @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began else { return }
    onLongPress?(gesture.location(in: self))
  }
}
#endif
