import XCTest
@testable import Dreft

final class DataSafetyUpgradeTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DreftUpgradeTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Fix 1: empty canvas + orphan prune

    @MainActor
    func testEmptyKnownCanvasIsIncludedInSnapshotAll() {
        let registry = CanvasDocumentRegistry()
        let canvasID = "Characters/test.canvas"
        _ = registry.store(for: canvasID)
        let snapshots = registry.snapshotAll(validIDs: [canvasID])
        XCTAssertEqual(snapshots[canvasID]?.cards.count, 0)
    }

    @MainActor
    func testUntouchedLazyCanvasIsSkippedInSnapshotAll() {
        let registry = CanvasDocumentRegistry()
        let snapshots = registry.snapshotAll(validIDs: ["NeverOpened.canvas"])
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testOrphanPruneKeepsPendingInMemoryAsset() throws {
        let vaultURL = tempRoot.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let assetsDir = vaultURL.appendingPathComponent(".dreft/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let assetPath = ".dreft/assets/photo.png"
        let assetURL = vaultURL.appendingPathComponent(assetPath)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetURL)

        let card = CanvasCard(
            id: "img-1",
            kind: .image,
            x: 0, y: 0, width: 200, height: 150,
            content: assetPath
        )
        let pending = CanvasDocumentSnapshot(
            cards: [card],
            edges: [],
            transform: CanvasViewTransform()
        )
        let snapshots = ["New.canvas": pending]

        _ = VaultFilesystem.writeCanvases(snapshots, vaultURL: vaultURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path))
    }

    func testOrphanPruneSkippedWhenCanvasWriteFails() throws {
        let vaultURL = tempRoot.appendingPathComponent("VaultFail", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let assetsDir = vaultURL.appendingPathComponent(".dreft/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let assetURL = assetsDir.appendingPathComponent("orphan.png")
        try Data([0xFF, 0xD8, 0xFF]).write(to: assetURL)

        let invalidPath = String(repeating: "x", count: 300) + ".canvas"
        let snapshots = [
            invalidPath: CanvasDocumentSnapshot(cards: [], edges: [], transform: CanvasViewTransform())
        ]

        let result = VaultFilesystem.writeCanvases(snapshots, vaultURL: vaultURL)
        XCTAssertTrue(result.hasFailures)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path))
    }

    func testOrphanPruneSkippedWhenUnreadableCanvasExistsOnDisk() throws {
        let vaultURL = tempRoot.appendingPathComponent("VaultUnreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let corruptCanvas = vaultURL.appendingPathComponent("broken.canvas")
        try Data("{ broken".utf8).write(to: corruptCanvas)

        let assetsDir = vaultURL.appendingPathComponent(".dreft/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let assetURL = assetsDir.appendingPathComponent("protected.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetURL)

        let snapshots = [
            "other.canvas": CanvasDocumentSnapshot(cards: [], edges: [], transform: CanvasViewTransform())
        ]
        _ = VaultFilesystem.writeCanvases(snapshots, vaultURL: vaultURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path))
    }

    // MARK: - Fix 3: workspace.json backup

    func testWorkspaceRestoresFromBackupWhenPrimaryIsCorrupt() throws {
        let dreftDir = tempRoot.appendingPathComponent("DreftSettings", isDirectory: true)
        let state = samplePersistedState(vaultName: "Upgrade Vault")

        try WorkspacePersistence.save(state, to: dreftDir)
        try WorkspacePersistence.save(state, to: dreftDir)

        let workspaceURL = WorkspacePersistence.workspaceFileURL(in: dreftDir)
        try Data("{ not valid json".utf8).write(to: workspaceURL)

        let loaded = WorkspacePersistence.load(from: dreftDir)
        XCTAssertTrue(loaded.restoredFromBackup)
        XCTAssertEqual(loaded.state?.vaults.first?.name, "Upgrade Vault")
    }

    func testCorruptPrimaryDoesNotOverwriteGoodBackup() throws {
        let dreftDir = tempRoot.appendingPathComponent("DreftBackupGuard", isDirectory: true)
        let state = samplePersistedState(vaultName: "Protected")

        try WorkspacePersistence.save(state, to: dreftDir)
        try WorkspacePersistence.save(state, to: dreftDir)

        let workspaceURL = WorkspacePersistence.workspaceFileURL(in: dreftDir)
        try Data("broken".utf8).write(to: workspaceURL)

        let brokenSave = PersistedAppState(
            vaults: [WorkspaceVault(name: "Broken", path: "/tmp/broken")],
            activeVaultID: nil,
            vaultSnapshots: [:],
            currentWorkspace: VaultWorkspaceSnapshot(
                tabs: [], activeTabID: "", selectedFileID: nil, expandedFolderIDs: []
            ),
            sortOrder: .nameAscending
        )
        try WorkspacePersistence.save(brokenSave, to: dreftDir)

        let backupURL = WorkspacePersistence.backupFileURL(in: dreftDir)
        let backupData = try Data(contentsOf: backupURL)
        XCTAssertTrue(backupData.contains(Data("Protected".utf8)))
    }

    // MARK: - Fix 4: canvas version + migration

    func testObsidianJSONCanvasLoads() throws {
        let obsidian = """
        {
          "nodes": [
            {
              "id": "node-a",
              "type": "text",
              "x": 10,
              "y": 20,
              "width": 200,
              "height": 80,
              "text": "Hello"
            },
            {
              "id": "node-b",
              "type": "file",
              "x": 300,
              "y": 20,
              "width": 260,
              "height": 180,
              "file": "Characters/hero.md"
            }
          ],
          "edges": [
            {
              "id": "edge-1",
              "fromNode": "node-a",
              "fromSide": "right",
              "toNode": "node-b",
              "toSide": "left"
            }
          ]
        }
        """
        let outcome = CanvasDocumentFormat.read(from: Data(obsidian.utf8))
        guard case .success(let snapshot) = outcome else {
            return XCTFail("Expected Obsidian canvas to load")
        }
        XCTAssertEqual(snapshot.cards.count, 2)
        XCTAssertEqual(snapshot.edges.count, 1)
        XCTAssertEqual(snapshot.cards.first?.content, "Hello")
        XCTAssertEqual(snapshot.cards.last?.content, "Characters/hero.md")
    }

    func testGraphLayoutGroupsPersistPerVault() throws {
        let vaultURL = tempRoot.appendingPathComponent("GraphVault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let groupID = UUID()
        let state = GraphLayoutState(
            positions: ["note.md": CGPoint(x: 120, y: 80)],
            groups: [
                GraphLayoutGroup(id: groupID, query: "file:characters", colorHex: "#E05252")
            ]
        )
        GraphLayoutPersistence.save(state, vaultURL: vaultURL)

        let loaded = GraphLayoutPersistence.load(vaultURL: vaultURL)
        XCTAssertEqual(loaded.positions["note.md"], CGPoint(x: 120, y: 80))
        XCTAssertEqual(loaded.groups.count, 1)
        XCTAssertEqual(loaded.groups.first?.id, groupID)
        XCTAssertEqual(loaded.groups.first?.query, "file:characters")
        XCTAssertEqual(loaded.groups.first?.colorHex, "#E05252")
    }

    func testLegacyCanvasWithoutVersionLoads() throws {
        let legacy = """
        {
          "cards": [],
          "edges": [],
          "transform": { "x": 0, "y": 0, "zoom": 1 }
        }
        """
        let outcome = CanvasDocumentFormat.read(from: Data(legacy.utf8))
        guard case .success(let snapshot) = outcome else {
            return XCTFail("Expected legacy canvas to load")
        }
        XCTAssertEqual(snapshot.transform.zoom, 1)
    }

    func testCanvasRoundTripWritesVersion() throws {
        let snapshot = CanvasDocumentSnapshot(
            cards: [CanvasCard.make(kind: .text, at: .zero)],
            edges: [],
            transform: CanvasViewTransform()
        )
        let data = try CanvasDocumentFormat.encode(snapshot)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, CanvasDocumentFormat.currentVersion)

        guard case .success(let decoded) = CanvasDocumentFormat.read(from: data) else {
            return XCTFail("Expected encoded canvas to decode")
        }
        XCTAssertEqual(decoded.cards.count, 1)
    }

    func testCorruptCanvasIsNotOverwrittenByEmptySnapshot() throws {
        let canvasURL = tempRoot.appendingPathComponent("broken.canvas")
        try Data("{ broken".utf8).write(to: canvasURL)

        let empty = CanvasDocumentSnapshot(cards: [], edges: [], transform: CanvasViewTransform())
        XCTAssertFalse(CanvasDocumentFormat.shouldOverwriteExistingFile(at: canvasURL, with: empty))

        let panned = CanvasDocumentSnapshot(
            cards: [],
            edges: [],
            transform: CanvasViewTransform(x: 40, y: 20, zoom: 1.2)
        )
        XCTAssertFalse(CanvasDocumentFormat.shouldOverwriteExistingFile(at: canvasURL, with: panned))
    }

    func testCorruptCanvasCanBeReplacedWhenUserAddsContent() throws {
        let canvasURL = tempRoot.appendingPathComponent("recover.canvas")
        try Data("{ broken".utf8).write(to: canvasURL)

        let withCard = CanvasDocumentSnapshot(
            cards: [CanvasCard.make(kind: .text, at: .zero)],
            edges: [],
            transform: CanvasViewTransform()
        )
        XCTAssertTrue(CanvasDocumentFormat.shouldOverwriteExistingFile(at: canvasURL, with: withCard))
    }

    func testClearedCanvasCanOverwriteValidCanvas() throws {
        let vaultURL = tempRoot.appendingPathComponent("VaultClear", isDirectory: true)
        let snapshot = CanvasDocumentSnapshot(
            cards: [CanvasCard.make(kind: .note, at: CGPoint(x: 100, y: 100))],
            edges: [],
            transform: CanvasViewTransform()
        )
        try VaultFilesystem.writeCanvas(snapshot, relativePath: "test.canvas", vaultURL: vaultURL)

        let empty = CanvasDocumentSnapshot(cards: [], edges: [], transform: CanvasViewTransform())
        try VaultFilesystem.writeCanvas(empty, relativePath: "test.canvas", vaultURL: vaultURL)

        let readBack = VaultFilesystem.readCanvas(at: vaultURL.appendingPathComponent("test.canvas"))
        XCTAssertEqual(readBack?.cards.count, 0)
    }

    // MARK: - Tier 2 trust

    func testShippedSidebarPanelsExcludeStubPanels() {
        XCTAssertTrue(SidebarPanel.shippedPanels.contains(.files))
        XCTAssertTrue(SidebarPanel.shippedPanels.contains(.search))
        XCTAssertTrue(SidebarPanel.shippedPanels.contains(.tags))
        XCTAssertTrue(SidebarPanel.shippedPanels.contains(.bookmarks))
        XCTAssertFalse(SidebarPanel.shippedPanels.contains(.allProperties))
        XCTAssertEqual(SidebarPanel.normalized(.allProperties), .files)
    }

    func testNoteTagParserFindsInlineAndFrontmatterTags() {
        let content = """
        ---
        tags: project, area/work
        ---

        # Welcome

        This note is #launch ready.
        """
        let tags = NoteTagParser.tags(in: content)
        XCTAssertTrue(tags.contains("project"))
        XCTAssertTrue(tags.contains("area/work"))
        XCTAssertTrue(tags.contains("launch"))
    }

    func testVaultTagIndexGroupsFilesByTag() {
        let files = [
            WorkspaceFileEntry(
                name: "A",
                kind: .note,
                noteContent: "#alpha #shared",
                relativePath: "A.md"
            ),
            WorkspaceFileEntry(
                name: "B",
                kind: .note,
                noteContent: "#beta #shared",
                relativePath: "B.md"
            ),
        ]
        let records = VaultTagIndex.records(from: files)
        XCTAssertEqual(records.first(where: { $0.tag == "shared" })?.count, 2)
        XCTAssertEqual(VaultTagIndex.files(withTag: "alpha", in: files).count, 1)
    }

    func testWelcomeNoteDoesNotMentionImporter() {
        XCTAssertFalse(VaultFilesystem.welcomeNoteContent.localizedCaseInsensitiveContains("importer"))
        XCTAssertTrue(VaultFilesystem.welcomeNoteContent.localizedCaseInsensitiveContains("wikilinks"))
    }

    func testVaultAccessibilityIssueForMissingExternalVault() {
        let vault = WorkspaceVault(
            name: "Missing",
            path: tempRoot.appendingPathComponent("DoesNotExist", isDirectory: true).path,
            securityScopedBookmark: nil
        )
        XCTAssertNotNil(VaultSecurityAccess.accessibilityIssue(for: vault))
    }

    // MARK: - Helpers

    private func samplePersistedState(vaultName: String) -> PersistedAppState {
        let vault = WorkspaceVault(name: vaultName, path: tempRoot.appendingPathComponent(vaultName).path)
        let workspace = VaultWorkspaceSnapshot(
            tabs: [WorkspaceTab(id: "tab-1", title: "Home", kind: .canvas, fileID: nil)],
            activeTabID: "tab-1",
            selectedFileID: nil,
            expandedFolderIDs: []
        )
        return PersistedAppState(
            vaults: [vault],
            activeVaultID: vault.id,
            vaultSnapshots: [vault.id: workspace],
            currentWorkspace: workspace,
            sortOrder: .nameAscending
        )
    }
}
