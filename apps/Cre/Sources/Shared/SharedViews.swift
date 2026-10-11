import CreCore
import SwiftUI

extension Color {
    /// The raised surface colour of the platform (selected segment, cards).
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

struct Ring: View {
    let color: Color
    let filled: Bool
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 2)
            if filled {
                Circle().fill(color)
                Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

struct PriorityChip: View {
    let priority: Priority

    var body: some View {
        Text(priority.label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.color(for: priority).opacity(priority == .p0 ? 1 : 0.2), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(priority == .p0 ? Color.white : Theme.color(for: priority))
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(color.opacity(0.13), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Same-size icon for every control in the day header.
struct ToolbarIcon: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13.5))
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
    }
}

/// Light grey switch; the chosen side is a white chip rather than a blue block.
struct SoftSegments<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let on = value == selection
                Button { selection = value } label: {
                    Text(label)
                        .font(.callout.weight(on ? .medium : .regular))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 5).fill(Color.cardBackground)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}
