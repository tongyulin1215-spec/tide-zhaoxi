import SwiftUI

/// "今天清空了" banner, shown for two seconds whenever `token` changes.
struct Celebration: ViewModifier {
    let token: Int
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if visible {
                    Label("今天清空了", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .onChange(of: token) {
                withAnimation(.spring) { visible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { visible = false } }
            }
    }
}

extension View {
    func celebration(_ token: Int) -> some View { modifier(Celebration(token: token)) }
}
