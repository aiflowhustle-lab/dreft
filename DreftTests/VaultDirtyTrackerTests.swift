import XCTest
@testable import Dreft

final class VaultDirtyTrackerTests: XCTestCase {
    func testRekeyNoteMovesDirtyFlag() {
        var tracker = VaultDirtyTracker()
        tracker.markNote("Notes/old.md")
        tracker.rekeyNote(from: "Notes/old.md", to: "Notes/new.md")
        XCTAssertFalse(tracker.isNoteDirty("Notes/old.md"))
        XCTAssertTrue(tracker.isNoteDirty("Notes/new.md"))
    }

    func testRekeyCanvasMovesDirtyFlag() {
        var tracker = VaultDirtyTracker()
        tracker.markCanvas("Boards/old.canvas")
        tracker.rekeyCanvas(from: "Boards/old.canvas", to: "Boards/new.canvas")
        let consumed = tracker.consumeCanvases()
        XCTAssertEqual(consumed, ["Boards/new.canvas"])
    }

    func testClearNoteRemovesDirtyFlag() {
        var tracker = VaultDirtyTracker()
        tracker.markNote("a.md")
        tracker.clearNote("a.md")
        XCTAssertTrue(tracker.consumeNotes().isEmpty)
    }
}
