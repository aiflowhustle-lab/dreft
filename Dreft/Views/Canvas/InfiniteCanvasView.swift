import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif

struct InfiniteCanvasView: View {
  @Bindable var store: CanvasStore
  @Bindable var workspace: WorkspaceStore
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
  @State private var isCanvasInteracting = false
  @State private var isCardDragging = false
  @State private var isCardResizing = false
  /// Camera locked while moving/resizing a card so pinch drift can't flash card scale.
  @State private var cardInteractionFrozenTransform: CanvasViewTransform?
  @State private var cardDragOverrides: [String: CGPoint] = [:]
  @State private var cardResizeOverrides: [String: CGRect] = [:]
  @State private var panActive = false
  @State private var panAnchor = CGSize.zero
  @State private var pinchStartZoom: CGFloat?
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
  @State private var suppressCanvasTapUntil: Date?
  @State private var imageTitleRenameTokens: [String: Int] = [:]
  @State private var hoverEdgeID: String?
  @State private var editingEdgeLabelID: String?
  @State private var edgeLabelDraft = ""
  #if canImport(PhotosUI)
  @State private var photoItems: [PhotosPickerItem] = []
  #endif
  @State private var timelapsePlaying = false
  @State private var timelapseVisibleCardIDs: Set<String>?
  @State private var timelapseVisibleEdgeIDs: Set<String>?
  @State private var timelapseCurrentDate: Date?
  @State private var timelapseTask: Task<Void, Never>?
  @State private var timelapseRevision = 0

  var body: some View {
    GeometryReader { geo in
      let size = geo.size
      let safeBottom = geo.safeAreaInsets.bottom
      ZStack {
        AppColors.canvasBackground

        if showCanvasGrid {
          DotGridBackground(
            panOffset: CGSize(width: displayTransform.x, height: displayTransform.y),
            dotColor: AppColors.gridDotColor
          )
        }

        canvasInteractionBackground(canvasSize: size)

        canvasCardsLayer(canvasSize: size)
          .zIndex(3)

        CanvasEdgeHitOverlay(
          transform: displayTransform,
          cardIndex: cardIndex,
          edges: activeCanvasEdges,
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides,
          edgeEndpoint: { edge in
            store.edgeEndpoint(
              for: edge,
              positionOverrides: cardDragOverrides,
              resizeOverrides: cardResizeOverrides
            )
          },
          onHoverEdge: { edgeID in
            Task { @MainActor in
              hoverEdgeID = edgeID
            }
          }
        )
        .zIndex(4)
        .allowsHitTesting(!timelapsePlaying)
        #if os(macOS)
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
        #endif

        CanvasEdgesScreenOverlay(
          transform: displayTransform,
          cardIndex: cardIndex,
          edges: activeCanvasEdges,
          connectingFrom: store.connectingFrom,
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides,
          selectedEdgeID: store.selectedEdgeID,
          editingEdgeID: editingEdgeLabelID,
          editingLabelDraft: edgeLabelDraft
        )
        .zIndex(5)

        CanvasEdgeLabelLayer(
          transform: displayTransform,
          cardIndex: cardIndex,
          edges: activeCanvasEdges,
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides,
          editingEdgeID: editingEdgeLabelID,
          labelDraft: $edgeLabelDraft,
          onCommit: { edgeID, label in
            store.setEdgeLabel(edgeID, label: label)
            editingEdgeLabelID = nil
          },
          onBeginEdit: { edgeID in
            editingEdgeLabelID = edgeID
          }
        )
        .zIndex(6)

        canvasCardToolbarLayer(canvasSize: size)
          .zIndex(110)

        if store.isDragOver { dropOverlay }

        if store.contextMenu != nil {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              store.dismissPendingEndpoint()
              store.selectedCardID = nil
              store.focusCardID = nil
            }
            .zIndex(99)
        }

        if let menu = store.contextMenu {
          contextMenuOverlay(menu, canvasSize: size)
        }
      }
      .frame(width: size.width, height: size.height)
      .clipped()
      .onChange(of: store.selectedCardID) { _, _ in
        cardToolbarColorRowOpen = false
        cardToolbarCustomColorOpen = false
        edgeToolbarColorRowOpen = false
        edgeToolbarCustomColorOpen = false
      }
      .onChange(of: store.selectedEdgeID) { _, newValue in
        if newValue != editingEdgeLabelID {
          editingEdgeLabelID = nil
        }
        if newValue == nil {
          edgeToolbarColorRowOpen = false
          edgeToolbarCustomColorOpen = false
        }
      }
      .onChange(of: store.historyRevision) { _, _ in
        cardDragOverrides.removeAll()
        cardResizeOverrides.removeAll()
      }
      #if os(iOS)
      .overlay {
        CanvasTouchCaptureView(
          passesThroughHits: true,
          isEnabled: canvasNavigationEnabled,
          blocksNavigationAt: { point in
            blocksCanvasNavigation(at: point, canvasSize: size)
          },
          onPan: { delta in
            isCanvasInteracting = true
            displayTransform.x += delta.width
            displayTransform.y += delta.height
          },
          onPanEnded: {
            finishCanvasInteraction()
          },
          onPinchBegan: { _ in
            guard !isCardDragging, !isCardResizing else { return }
            isCanvasInteracting = true
            pinchStartZoom = displayTransform.zoom
          },
          onPinchChanged: { scale, anchor in
            guard !isCardDragging, !isCardResizing else { return }
            let startZoom = pinchStartZoom ?? displayTransform.zoom
            let newZoom = min(
              CanvasViewTransform.maxZoom,
              max(CanvasViewTransform.minZoom, startZoom * scale)
            )
            applyZoom(at: anchor, targetZoom: newZoom)
          },
          onPinchEnded: {
            pinchStartZoom = nil
            finishCanvasInteraction()
          },
          onLongPress: { location in
            handleCanvasLongPress(at: location, canvasSize: size)
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
      }
      #endif
      .overlay(alignment: .topTrailing) {
        canvasRightToolbar(canvasSize: size)
          .zIndex(300)
          .opacity(timelapsePlaying ? 0.45 : 1)
          .allowsHitTesting(!timelapsePlaying)
      }
      .overlay(alignment: .bottom) {
        canvasBottomToolbar(canvasSize: size, safeAreaBottom: safeBottom)
          .zIndex(300)
          .opacity(timelapsePlaying ? 0.45 : 1)
          .allowsHitTesting(!timelapsePlaying)
      }
      .overlay(alignment: .bottomLeading) {
        zoomIndicator(safeAreaBottom: safeBottom)
      }
      .overlay(alignment: .bottomTrailing) {
        backlinkBadge(safeAreaBottom: safeBottom)
      }
      .overlay {
        canvasNoteEditOverlay(canvasSize: size)
          .zIndex(250)
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
      .background(AppColors.canvasBackground)
      #if os(macOS)
      .onCanvasScroll { delta, location, zoomRequested, phaseEnded in
        if timelapsePlaying || store.contextMenu != nil || store.isVaultOpen || store.focusCardID != nil { return }
        isCanvasInteracting = true
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
      #endif
      #if os(macOS)
      .simultaneousGesture(store.contextMenu == nil ? pinchGesture(in: size) : nil)
      #endif
      .simultaneousGesture(edgeInteractionGesture(canvasSize: size))
      .onAppear {
        displayTransform = store.transform
        store.vaultURL = vaultURL
        store.viewportSize = size
      }
      .onDisappear {
        stopCanvasTimelapse(showAll: true)
      }
      .onChange(of: size) { _, newSize in
        store.viewportSize = newSize
      }
      .onChange(of: vaultURL) { _, newURL in
        store.vaultURL = newURL
      }
      .onChange(of: store.transform) { _, newValue in
        // Split panes keep independent cameras; only the primary document owner syncs.
        guard !independentCamera, !isCanvasInteracting, !isCardDragging else { return }
        displayTransform = newValue
      }
      .onDrop(of: [.image, .fileURL], isTargeted: $store.isDragOver) { providers, location in
        importDroppedImages(providers, at: location, canvasSize: size)
      }
      #if canImport(PhotosUI)
      .photosPicker(isPresented: $showImagePicker, selection: $photoItems, maxSelectionCount: 10, matching: .images)
      .onChange(of: photoItems) { _, items in
        Task { await importPickedPhotos(items, canvasSize: size) }
      }
      #endif
      .fileImporter(
        isPresented: $showImageSwapPicker,
        allowedContentTypes: [.image],
        allowsMultipleSelection: false
      ) { result in
        importSwappedImage(from: result)
      }
      #if os(macOS)
      .onReceive(NotificationCenter.default.publisher(for: .openImagePanel)) { _ in
        openMacImagePanel(canvasSize: size)
      }
      .focusable()
      .focusEffectDisabled()
      .background {
        Group {
          Button("") { store.undo() }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!store.canUndo)
          Button("") { store.redo() }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!store.canRedo)
          Button("") { zoomToFitAll(canvasSize: size) }
            .keyboardShortcut("1", modifiers: .shift)
          Button("") { zoomToSelection(canvasSize: size) }
            .keyboardShortcut("2", modifiers: .shift)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
      }
      #endif
    }
  }

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

  private func visibleCards(for canvasSize: CGSize) -> [CanvasCard] {
    let sourceCards = timelapseActive ? timelapseFilteredCards : store.cards
    if timelapseActive {
      return sourceCards
    }
    let viewport = CanvasViewport.worldRect(
      canvasSize: canvasSize,
      transform: displayTransform,
      padding: isCanvasInteracting ? 4_000 : CanvasConstants.viewportPadding
    )
    let visibleIDs = CanvasViewport.visibleCardIDs(
      cards: sourceCards,
      viewport: viewport,
      positionOverrides: cardDragOverrides,
      resizeOverrides: cardResizeOverrides,
      selectedID: store.selectedCardID,
      hoverID: store.hoverCardID,
      spatialIndex: store.spatialIndexForCulling()
    )
    if isCanvasInteracting || isCardResizing {
      return sourceCards
    }
    return sourceCards.filter { visibleIDs.contains($0.id) }
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
        // Tapping a connection line selects it (floating toolbar); the edge drag
        // gesture also selects, but this tap fires later and must not clear it.
        if let edgeID = hitTestEdge(at: location, canvasSize: canvasSize) {
          store.selectEdge(edgeID)
          return
        }
        store.selectedCardID = nil
        store.selectedEdgeID = nil
        store.endContentEdit()
        store.focusCardID = nil
        editingEdgeLabelID = nil
      }
  }

  private var canvasNavigationEnabled: Bool {
    !timelapsePlaying
      && store.contextMenu == nil
      && !isCardDragging
      && !isCardResizing
      && !store.isConnectingLine
      && store.focusCardID == nil
  }

  private var canvasPanGestureEnabled: Bool {
    canvasNavigationEnabled && !store.isVaultOpen
  }

  /// Double-click empty canvas → place a new note card at the click location.
  private func handleCanvasTap(at screenPoint: CGPoint, canvasSize: CGSize) {
    guard canvasNavigationEnabled, !store.isVaultOpen else { return }
    if let until = suppressCanvasTapUntil, Date() < until { return }

    store.dismissPendingEndpoint()

    let worldPoint = store.screenToWorld(screenPoint, in: canvasSize, transform: displayTransform)
    if store.card(
      at: worldPoint,
      positionOverrides: cardDragOverrides,
      resizeOverrides: cardResizeOverrides
    ) != nil {
      return
    }

    store.addCompactNote(at: worldPoint)
    store.focusCardID = store.selectedCardID
  }

  #if os(iOS)
  /// Pencil/finger long-press on empty canvas → add-card menu (Apple Pencil creation flow).
  private func handleCanvasLongPress(at screenPoint: CGPoint, canvasSize: CGSize) {
    guard canvasNavigationEnabled, !store.isVaultOpen else { return }
    if let until = suppressCanvasTapUntil, Date() < until { return }

    let worldPoint = store.screenToWorld(screenPoint, in: canvasSize, transform: displayTransform)
    if store.card(
      at: worldPoint,
      positionOverrides: cardDragOverrides,
      resizeOverrides: cardResizeOverrides
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

  private var cardRenderTransform: CanvasViewTransform {
    if isCardDragging || isCardResizing, let frozen = cardInteractionFrozenTransform {
      return frozen
    }
    return displayTransform
  }

  private func beginCardInteractionFreeze() {
    cardInteractionFrozenTransform = displayTransform
  }

  private func endCardInteractionFreeze() {
    restoreCameraAfterCardDragIfNeeded()
    cardInteractionFrozenTransform = nil
  }

  #if os(iOS)
  /// Keep canvas pan/pinch off cards so dragging doesn't briefly scale the view.
  private func blocksCanvasNavigation(at screenPoint: CGPoint, canvasSize: CGSize) -> Bool {
    if isPointOnCanvasToolbar(screenPoint, canvasSize: canvasSize) { return true }
    if isPointOnSelectedCardToolbar(screenPoint, ignoringDragState: true) { return true }
    let world = store.screenToWorld(screenPoint, in: canvasSize, transform: displayTransform)
    return store.card(
      at: world,
      positionOverrides: cardDragOverrides,
      resizeOverrides: cardResizeOverrides
    ) != nil
  }
  #endif

  /// Cards render in screen space (like edges) — avoids transformEffect breaking drag on iOS.
  private func canvasCardsLayer(canvasSize: CGSize) -> some View {
    let transform = cardRenderTransform
    let zoom = transform.zoom
    let cards = visibleCards(for: canvasSize)
    let _ = store.imageCacheRevision
    let _ = store.historyRevision

    return ZStack(alignment: .topLeading) {
      ForEach(cards) { card in
        let layoutFrame = cardLayoutFrame(card)
        let liveFrame = cardDisplayFrame(card)
        let screenOrigin = cardScreenOrigin(for: liveFrame, transform: transform)

        canvasCardView(card: card, displayFrame: layoutFrame, canvasSize: canvasSize)
          .id(card.id)
          .frame(width: layoutFrame.width, height: layoutFrame.height)
          .scaleEffect(zoom, anchor: .topLeading)
          .offset(x: screenOrigin.x, y: screenOrigin.y)
          .transaction { transaction in
            transaction.disablesAnimations = true
          }
      }
    }
    .allowsHitTesting(!timelapsePlaying)
    .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
  }

  @ViewBuilder
  private func canvasCardView(card: CanvasCard, displayFrame: CGRect, canvasSize: CGSize) -> some View {
    let cardView = CanvasCardView(
      card: card,
      displayFrame: displayFrame,
      isSelected: store.selectedCardID == card.id,
      isLinkTarget: store.hoverCardID == card.id,
      isConnectingLine: store.isConnectingLine,
      zoom: cardRenderTransform.zoom,
      vaultURL: vaultURL,
      vaultFiles: VaultFile.openableFiles(from: workspace.files),
      onSelect: {
        store.selectCard(card.id)
      },
      onDragBegan: {
        isCardDragging = true
        beginCardInteractionFreeze()
      },
      onMove: { preview in
        if var frame = cardResizeOverrides[card.id] {
          frame.origin = preview
          cardResizeOverrides[card.id] = frame
        } else {
          cardDragOverrides[card.id] = preview
        }
      },
      onMoveEnd: {
        if let frame = cardResizeOverrides[card.id] {
          store.resizeCard(card.id, frame: frame)
          cardResizeOverrides.removeValue(forKey: card.id)
        } else if let origin = cardDragOverrides[card.id] {
          store.moveCard(card.id, to: origin)
          cardDragOverrides.removeValue(forKey: card.id)
        }
        suppressCanvasTapUntil = Date().addingTimeInterval(0.35)
        isCardDragging = false
        endCardInteractionFreeze()
      },
      onResize: { cardResizeOverrides[card.id] = $0 },
      onResizeBegan: {
        isCardResizing = true
        beginCardInteractionFreeze()
      },
      onResizeEnd: {
        if let frame = cardResizeOverrides[card.id] {
          store.resizeCard(card.id, frame: frame)
          cardResizeOverrides.removeValue(forKey: card.id)
        }
        isCardResizing = false
        endCardInteractionFreeze()
      },
      onDelete: { store.deleteCard(card.id) },
      onZoomToCard: {
        store.zoomToSelection(canvasSize: canvasSize)
        displayTransform = store.transform
      },
      onBeginConnect: {
        store.beginConnecting(
          fromID: card.id,
          side: $0,
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides
        )
      },
      onUpdateConnect: { screen in
        store.updateConnecting(
          to: store.screenToWorld(screen, in: canvasSize, transform: displayTransform),
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides
        )
      },
      onEndConnect: { screen, moved in
        store.finishConnecting(
          at: store.screenToWorld(screen, in: canvasSize, transform: displayTransform),
          moved: moved,
          screenPoint: screen,
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides
        )
      },
      onUpdateContent: { store.updateContent(for: card.id, content: $0) },
      onUpdateTitle: { store.updateTitle(for: card.id, title: $0) },
      shouldAutoFocus: store.focusCardID == card.id,
      onDidFocus: {},
      onBeginContentEdit: { store.beginContentEdit(for: card.id) },
      onEndContentEdit: { store.endContentEdit() },
      beginTitleRenameToken: imageTitleRenameTokens[card.id] ?? 0,
      isEditing: store.focusCardID == card.id,
      isColorPickerOpen: store.selectedCardID == card.id && cardToolbarColorRowOpen,
      onRequestEdit: {
        store.selectedCardID = card.id
        store.selectedEdgeID = nil
        store.focusCardID = card.id
        store.beginContentEdit(for: card.id)
      }
    )

    if card.kind == .image {
      cardView.contextMenu {
        CanvasImageCardContextMenu(
          workspace: workspace,
          store: store,
          card: card,
          sidebarVisible: $sidebarVisible,
          sidebarPanel: $sidebarPanel,
          onZoom: {
            store.selectedCardID = card.id
            store.zoomToSelection(canvasSize: canvasSize)
            displayTransform = store.transform
          },
          onSwap: {
            swapImageCardID = card.id
            #if os(macOS)
            openMacImageSwapPanel(for: card.id)
            #else
            showImageSwapPicker = true
            #endif
          },
          onRemove: { store.deleteCard(card.id) },
          onRename: {
            store.selectedCardID = card.id
            imageTitleRenameTokens[card.id, default: 0] += 1
          }
        )
      }
    } else {
      cardView
    }
  }

  @ViewBuilder
  private func canvasNoteEditOverlay(canvasSize: CGSize) -> some View {
    if let focusID = store.focusCardID,
       let card = cardIndex[focusID],
       card.kind != .image {
      let worldFrame = cardDisplayFrame(card)
      let zoom = displayTransform.zoom
      let screenOrigin = cardScreenOrigin(for: worldFrame, transform: displayTransform)
      let screenW = worldFrame.width * zoom
      let screenH = worldFrame.height * zoom
      let screenCenter = CGPoint(x: screenOrigin.x + screenW / 2, y: screenOrigin.y + screenH / 2)

      CanvasNoteEditOverlay(
        initialText: CanvasCardContent.markdownBody(
          for: card,
          vaultURL: vaultURL,
          vaultFiles: VaultFile.openableFiles(from: workspace.files)
        ),
        cardSize: CGSize(width: screenW, height: screenH),
        colorHex: card.colorHex,
        files: workspace.files,
        onTextEdited: { store.updateContent(for: focusID, content: $0, fromTextUndo: $1) },
        onDismiss: {
          store.endContentEdit()
          store.focusCardID = nil
        }
      )
      .frame(width: screenW, height: screenH)
      .position(screenCenter)
      .zIndex(250)
    }
  }

  private func cardDisplayFrame(_ card: CanvasCard) -> CGRect {
    if let frame = cardResizeOverrides[card.id] { return frame }
    let origin = cardDragOverrides[card.id] ?? CGPoint(x: card.x, y: card.y)
    return CGRect(x: origin.x, y: origin.y, width: card.width, height: card.height)
  }

  /// Persisted card frame for the drag target — origin stays fixed while `cardDragOverrides` moves the view.
  private func cardLayoutFrame(_ card: CanvasCard) -> CGRect {
    if let frame = cardResizeOverrides[card.id] { return frame }
    return CGRect(x: card.x, y: card.y, width: card.width, height: card.height)
  }

  /// Stable layout origin while dragging — avoids re-positioning the gesture target mid-drag.
  private func cardPositionOrigin(_ card: CanvasCard) -> CGPoint {
    if let frame = cardResizeOverrides[card.id] { return frame.origin }
    return CGPoint(x: card.x, y: card.y)
  }

  @ViewBuilder
  private func canvasCardToolbarLayer(canvasSize: CGSize) -> some View {
    if let selectedID = store.selectedCardID,
       let card = cardIndex[selectedID],
       !isCardResizing {
      let worldFrame = cardDisplayFrame(card)
      let transform = cardRenderTransform
      let zoom = transform.zoom
      let screenCenter = cardScreenCenter(for: worldFrame, transform: transform)

      CanvasCardFloatingToolbarLayer(
        card: card,
        frameWidth: worldFrame.width,
        frameHeight: worldFrame.height,
        zoom: zoom,
        cardColors: store.cardColors,
        showColorRow: $cardToolbarColorRowOpen,
        showCustomColorPicker: $cardToolbarCustomColorOpen,
        onDelete: { store.deleteCard(card.id) },
        onZoomToCard: {
          store.zoomToSelection(canvasSize: canvasSize)
          displayTransform = store.transform
        },
        onSetColor: { store.setCardColor(card.id, hex: $0) },
        onBeginEditingNote: {
          store.beginContentEdit(for: card.id)
          store.focusCardID = card.id
        },
        onRenameImage: {
          imageTitleRenameTokens[card.id, default: 0] += 1
        }
      )
      .scaleEffect(zoom, anchor: .center)
      .position(screenCenter)
      .allowsHitTesting(true)
      .transaction { transaction in
        transaction.disablesAnimations = true
      }
    }

    if let edgeID = store.selectedEdgeID,
       store.selectedCardID == nil,
       let edge = store.edges.first(where: { $0.id == edgeID }),
       !isCardDragging,
       !isCardResizing {
      edgeFloatingToolbar(for: edge, canvasSize: canvasSize)
    }
  }

  @ViewBuilder
  private func edgeFloatingToolbar(for edge: CanvasEdge, canvasSize: CGSize) -> some View {
    if let from = cardIndex[edge.fromID],
       let endpoint = store.edgeEndpoint(
        for: edge,
        positionOverrides: cardDragOverrides,
        resizeOverrides: cardResizeOverrides
       ) {
      let p1 = CanvasGeometry.anchor(
        for: from,
        side: edge.fromSide,
        overrides: cardDragOverrides,
        resizeOverrides: cardResizeOverrides
      )
      let mid = CanvasGeometry.pointOnCurve(
        from: p1,
        fromSide: edge.fromSide,
        to: endpoint.point,
        toSide: endpoint.toSide,
        t: 0.5
      )
      let screen = store.worldToScreen(mid, transform: displayTransform)
      let zoom = displayTransform.zoom
      let toolbarWorldScale = 1 / min(max(zoom, 0.45), 1.35)

      VStack(spacing: 6) {
        CanvasEdgeFloatingToolbar(
          direction: edge.direction,
          hasActiveColor: edge.colorHex != nil && !(edge.colorHex?.isEmpty ?? true),
          showColorRow: $edgeToolbarColorRowOpen,
          onDelete: {
            editingEdgeLabelID = nil
            store.deleteEdge(edge.id)
          },
          onZoomToLine: {
            store.zoomToEdge(edge.id, canvasSize: canvasSize)
            displayTransform = store.transform
          },
          onSetDirection: { store.setEdgeDirection(edge.id, direction: $0) },
          onEditLabel: {
            editingEdgeLabelID = edge.id
            edgeLabelDraft = edge.label ?? ""
          }
        )

        if edgeToolbarColorRowOpen {
          CanvasCardColorSwatchRow(
            activeColorHex: edge.colorHex,
            frameWidth: 280,
            zoom: zoom,
            cardColors: store.cardColors,
            showCustomColorPicker: $edgeToolbarCustomColorOpen,
            onSetColor: { store.setEdgeColor(edge.id, hex: $0) }
          )
          .scaleEffect(toolbarWorldScale, anchor: .top)
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
        if !panActive {
          panActive = true
          isCanvasInteracting = true
          panAnchor = CGSize(width: displayTransform.x, height: displayTransform.y)
        }
        displayTransform.x = panAnchor.width + value.translation.width
        displayTransform.y = panAnchor.height + value.translation.height
      }
      .onEnded { _ in
        panActive = false
        finishCanvasInteraction()
      }
  }

  private func pinchGesture(in size: CGSize) -> some Gesture {
    MagnificationGesture()
      .onChanged { value in
        if pinchStartZoom == nil {
          isCanvasInteracting = true
          pinchStartZoom = displayTransform.zoom
        }
        let anchor = CGPoint(x: size.width / 2, y: size.height / 2)
        let startZoom = pinchStartZoom ?? displayTransform.zoom
        let newZoom = min(CanvasViewTransform.maxZoom, max(CanvasViewTransform.minZoom, startZoom * value))
        applyZoom(at: anchor, targetZoom: newZoom)
      }
      .onEnded { _ in
        pinchStartZoom = nil
        finishCanvasInteraction()
      }
  }

  private func applyZoom(at anchor: CGPoint, factor: CGFloat) {
    let t = displayTransform
    let newZoom = min(CanvasViewTransform.maxZoom, max(CanvasViewTransform.minZoom, t.zoom * factor))
    applyZoom(at: anchor, targetZoom: newZoom)
  }

  private func restoreCameraAfterCardDragIfNeeded() {
    guard displayTransform != store.transform else { return }
    displayTransform = store.transform
  }

  private func applyZoom(at anchor: CGPoint, targetZoom: CGFloat) {
    guard !isCardDragging, !isCardResizing else { return }
    var t = displayTransform
    let newZoom = min(CanvasViewTransform.maxZoom, max(CanvasViewTransform.minZoom, targetZoom))
    let ratio = newZoom / t.zoom
    t.x = anchor.x - (anchor.x - t.x) * ratio
    t.y = anchor.y - (anchor.y - t.y) * ratio
    t.zoom = newZoom
    displayTransform = t
  }

  private func finishCanvasInteraction() {
    // Only the designated owner persists camera into the shared document snapshot.
    if persistsCamera {
      store.setTransform(displayTransform)
    }
    isCanvasInteracting = false
  }

  // MARK: - Image import

  private func importDroppedImages(_ providers: [NSItemProvider], at location: CGPoint, canvasSize: CGSize) -> Bool {
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
  #endif

  #if os(macOS)
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
      tooltipAnchor: .leading(caretCenterX: 15)
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

  private func startCanvasTimelapse(canvasSize: CGSize) {
    stopCanvasTimelapse(showAll: false)
    let timeline = CanvasTimelapseTimeline.build(
      cards: store.cards,
      edges: store.edges,
      files: workspace.files,
      vaultURL: vaultURL,
      canvasRelativePath: store.documentRelativePath,
      canvasCreatedAt: activeCanvasFile?.createdAt
    )
    guard !timeline.isEmpty else { return }

    store.selectedCardID = nil
    store.selectedEdgeID = nil
    store.focusCardID = nil
    store.endContentEdit()
    editingEdgeLabelID = nil

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
        zoomToFitAll(canvasSize: canvasSize)
      }
    }
  }

  // MARK: - Chrome

  private func zoomToFitAll(canvasSize: CGSize) {
    store.zoomToFit(canvasSize: canvasSize)
    displayTransform = store.transform
  }

  private func zoomToSelection(canvasSize: CGSize) {
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
      onAddCard: {
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
      safeAreaBottom: safeAreaBottom,
      onAddCard: {
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
                isCanvasInteracting = true
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
    isCanvasInteracting = true
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
        overrides: cardDragOverrides,
        resizeOverrides: cardResizeOverrides
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
      case .endpoint, .edge:
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
      let edgeID: String? = switch menu.kind {
      case .endpoint(let id, _, _), .edge(let id): id
      default: nil
      }
      if let edgeID {
        store.pendingEndpointEdgeID = edgeID
        store.pendingEndpointMenuCenter = endpointMenuCenterWorld(menu, canvasSize: canvasSize)
        store.setVaultFiles(workspace.files)
        store.isVaultOpen = true
        store.vaultSearchQuery = ""
        store.vaultSelectedIndex = 0
      }
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
    if !ignoringDragState, isCardDragging || isCardResizing { return false }

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
        guard store.contextMenu == nil, !isCardDragging, !isCardResizing else { return }
        guard !isPointOnSelectedCardToolbar(value.startLocation) else { return }
        guard !isPointOnCanvasToolbar(value.startLocation, canvasSize: canvasSize) else { return }

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
          if hypot(dx, dy) >= ContextMenuLayout.edgeDragThreshold {
            edgeInteractionActive = true
            pendingEdgeInteractionID = nil
            store.beginEditingEdgeEndpoint(
              pendingID,
              positionOverrides: cardDragOverrides,
              resizeOverrides: cardResizeOverrides
            )
          }
        }

        guard edgeInteractionActive || store.editingEdgeID != nil else { return }
        let world = store.screenToWorld(value.location, in: canvasSize, transform: displayTransform)
        store.updateConnecting(
          to: world,
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides
        )
      }
      .onEnded { value in
        defer {
          edgeInteractionActive = false
          pendingEdgeInteractionID = nil
          edgeInteractionStartLocation = nil
        }

        guard store.contextMenu == nil, !isCardDragging, !isCardResizing else { return }
        guard !isPointOnSelectedCardToolbar(value.startLocation) else { return }
        guard !isPointOnCanvasToolbar(value.startLocation, canvasSize: canvasSize) else { return }

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
          positionOverrides: cardDragOverrides,
          resizeOverrides: cardResizeOverrides
        )
      }
  }

  /// Hit-test any connection line — grab anywhere on the curve to drag the endpoint.
  private func hitTestEdge(at screenPoint: CGPoint, canvasSize: CGSize) -> String? {
    let toScreen = { store.worldToScreen($0, transform: displayTransform) }
    var best: (id: String, distance: CGFloat)?

    for edge in store.edges {
      guard let from = store.cards.first(where: { $0.id == edge.fromID }),
            let endpoint = store.edgeEndpoint(
              for: edge,
              positionOverrides: cardDragOverrides,
              resizeOverrides: cardResizeOverrides
            ) else { continue }

      let p1 = CanvasGeometry.anchor(
        for: from,
        side: edge.fromSide,
        overrides: cardDragOverrides,
        resizeOverrides: cardResizeOverrides
      )
      let distance = CanvasGeometry.screenDistanceToEdge(
        screenPoint: screenPoint,
        from: p1,
        fromSide: edge.fromSide,
        to: endpoint.point,
        toSide: endpoint.toSide,
        toScreen: toScreen
      )
      if distance < ContextMenuLayout.lineHitRadius,
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
  var onScroll: (CGSize, CGPoint, Bool, Bool) -> Void

  func body(content: Content) -> some View {
    content.overlay {
      CanvasScrollCaptureView(onScroll: onScroll)
    }
  }
}

private struct CanvasScrollCaptureView: NSViewRepresentable {
  var onScroll: (CGSize, CGPoint, Bool, Bool) -> Void

  func makeNSView(context: Context) -> CanvasScrollNSView {
    let view = CanvasScrollNSView()
    view.onScroll = onScroll
    return view
  }

  func updateNSView(_ nsView: CanvasScrollNSView, context: Context) {
    nsView.onScroll = onScroll
  }
}

private final class CanvasScrollNSView: NSView {
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

  private func installScrollMonitor() {
    removeScrollMonitor()
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, self.window != nil, self.isPointerInsideView else { return event }
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

  private func processScrollEvent(_ event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    let zoomRequested = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)

    let delta: CGSize
    if event.hasPreciseScrollingDeltas {
      delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
    } else {
      delta = CGSize(width: event.deltaX * 10, height: event.deltaY * 10)
    }

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
  func onCanvasScroll(_ handler: @escaping (CGSize, CGPoint, Bool, Bool) -> Void) -> some View {
    modifier(CanvasScrollModifier(onScroll: handler))
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

/// iPad two-finger pan and pinch zoom. Use `passesThroughHits` when single-finger
/// content (e.g. graph nodes) must stay draggable above this layer.
struct CanvasTouchCaptureView: UIViewRepresentable {
  var passesThroughHits = false
  var isEnabled: Bool
  var blocksNavigationAt: ((CGPoint) -> Bool)? = nil
  var onPan: (CGSize) -> Void
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
    pan.minimumNumberOfTouches = 2
    pan.maximumNumberOfTouches = 2
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
