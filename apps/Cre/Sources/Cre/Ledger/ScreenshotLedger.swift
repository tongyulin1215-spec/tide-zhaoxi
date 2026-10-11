import AppKit
import CreCore
import SwiftUI
import UniformTypeIdentifiers
import Vision

func cgImage(from data: Data) -> CGImage? {
    NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// Images on the clipboard (a screenshot, copied image files, or one from iPhone via Universal Clipboard).
@MainActor
func clipboardImages() -> [CGImage] {
    (NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? [])
        .compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
}

/// File picker; several images at once.
@MainActor
func pickScreenshots() -> [CGImage] {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return [] }
    return panel.urls.compactMap { (try? Data(contentsOf: $0)).flatMap(cgImage(from:)) }
}

/// Lets the user drag out a screen area, like ⇧⌘4. Nil when cancelled.
func captureScreenArea() async -> CGImage? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tide-capture-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-i", "-x", url.path]
    guard (try? p.run()) != nil else { return nil }
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        p.terminationHandler = { _ in c.resume() }
    }
    return (try? Data(contentsOf: url)).flatMap(cgImage(from:))
}

/// Turns a screenshot into a prefilled entry for the confirmation form.
@MainActor
func draftEntry(from image: CGImage, state: AppState) async -> (LedgerEntry, Bool) {
    await draftEntry(from: image, ledger: state.ledger, today: state.today)
}

/// Holds a screenshot draft waiting for confirmation.
struct ScreenshotDraft: Identifiable {
    let id = UUID()
    let entry: LedgerEntry
    let foundAmount: Bool
    /// The screenshot, shown above the form to check the numbers against.
    var image: CGImage? = nil
    /// "2/3" when several screenshots came in together.
    var position: String? = nil
}
