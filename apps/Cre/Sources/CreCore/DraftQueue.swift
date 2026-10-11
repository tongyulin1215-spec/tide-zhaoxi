import Foundation

/// Screenshots waiting for their confirmation forms, one at a time; "2/3" while several came in together.
public struct DraftQueue<T> {
    private var items: [T]
    private var index = 0

    public init(_ items: [T]) { self.items = items }

    public var current: T? { index < items.count ? items[index] : nil }

    /// "2/3"; nil for a single item or when done.
    public var position: String? {
        guard items.count > 1, index < items.count else { return nil }
        return "\(index + 1)/\(items.count)"
    }

    /// Saved or cancelled: on to the next.
    public mutating func advance() { index += 1 }

    /// More came in while a form is open; they join the same count.
    public mutating func append(contentsOf more: [T]) {
        if current == nil { items = []; index = 0 }
        items += more
    }
}
