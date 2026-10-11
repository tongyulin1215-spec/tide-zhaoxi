import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Action button: 记一条.
@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TideQuickAdd") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("记一条", systemImage: "plus.circle")
            }
        }
        .displayName("记一条")
        .description("打开朝夕，记一条待办。")
    }
}
