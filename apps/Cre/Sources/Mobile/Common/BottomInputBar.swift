import SwiftUI

/// The one-line input at the bottom of 首页 / 规划 / 记账, with an optional button on its right.
struct BottomInputBar<Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .focused(focus)
                .submitLabel(.done)
                .onSubmit(onSubmit)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 16)
        .background(Color(uiColor: .systemBackground))  // rows don't show through
    }
}

extension BottomInputBar where Trailing == EmptyView {
    init(placeholder: String, text: Binding<String>, focus: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void) {
        self.init(placeholder: placeholder, text: text, focus: focus, onSubmit: onSubmit) { EmptyView() }
    }
}
