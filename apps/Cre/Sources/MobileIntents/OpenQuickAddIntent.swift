import AppIntents
import Foundation

/// Opens 朝夕 straight into 记一条 (the Control Center button runs this).
@available(iOS 18.0, *)
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "打开记一条"
    static var openAppWhenRun = true
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "tide://quickadd")!))
    }
}
