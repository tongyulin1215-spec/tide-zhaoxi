import CreCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 「分享 → 朝夕」: reads the shared screenshots and asks to confirm each as a ledger entry, saved into the app's ledger.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        let host = UIHostingController(rootView: ShareLedgerView(providers: providers) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// The app's ledger file in the shared container.
enum SharedLedger {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.lty.cre.mobile")?
            .appendingPathComponent("ledger.json")
    }

    static func load() -> LedgerData { url.map { LedgerStore(fileURL: $0).load() } ?? LedgerData() }

    static func add(_ entry: LedgerEntry) {
        guard let url else { return }
        let store = LedgerStore(fileURL: url)
        let before = store.load()
        var after = before
        after.add(entry, now: Date())
        try? store.save(after.stamped(since: before, now: Date()))
    }
}

struct ShareLedgerView: View {
    let providers: [NSItemProvider]
    let done: () -> Void

    @State private var queue = DraftQueue<CGImage>([])
    @State private var ledger = SharedLedger.load()
    @State private var loading = true
    @State private var isIncome = false
    @State private var amountText = ""
    @State private var category = "其他"
    @State private var note = ""
    @State private var day = DayKey.from(Date())

    private var today: DayKey { DayKey.from(Date()) }
    private var cents: Int? { parseAmount(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    Section {
                        Picker("类型", selection: $isIncome) { Text("支出").tag(false); Text("收入").tag(true) }
                            .pickerStyle(.segmented)
                        TextField("金额", text: $amountText).keyboardType(.decimalPad).font(.title2.weight(.semibold))
                    }
                    Section {
                        Picker("分类", selection: $category) {
                            ForEach(categoryOptions, id: \.self) { c in
                                Label(c, systemImage: CategoryIcon.symbol(c)).tag(c)
                            }
                        }
                        TextField("备注", text: $note)
                        DayField(label: "日期", day: $day, latest: today)
                    }
                }
            }
            .navigationTitle(queue.position.map { "记一笔 \($0)" } ?? "记一笔").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: next) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let cents {
                            let n = note.trimmingCharacters(in: .whitespaces)
                            SharedLedger.add(LedgerEntry(amount: cents, isIncome: isIncome, category: category,
                                                         note: n.isEmpty ? category : n, day: day))
                            ledger = SharedLedger.load()
                        }
                        next()
                    }
                    .fontWeight(.semibold).disabled(cents == nil || loading)
                }
            }
        }
        .task { await start() }
    }

    private var categoryOptions: [String] {
        var list = ledger.categories(income: isIncome)
        if !list.contains(category) { list.append(category) }
        return list
    }

    private func start() async {
        var images: [CGImage] = []
        for p in providers {
            if let data = try? await p.loadDataRepresentation(for: .image), let img = UIImage(data: data)?.cgImage { images.append(img) }
        }
        queue = DraftQueue(images)
        await recognize()
    }

    private func next() {
        queue.advance()
        if queue.current == nil { done(); return }
        Task { await recognize() }
    }

    private func recognize() async {
        guard let image = queue.current else { done(); return }
        loading = true
        let (entry, found) = await draftEntry(from: image, ledger: ledger, today: today)
        isIncome = entry.isIncome
        category = entry.category
        note = entry.note
        day = entry.day
        amountText = found ? String(format: entry.amount % 100 == 0 ? "%.0f" : "%.2f", Double(entry.amount) / 100) : ""
        loading = false
    }
}

private extension NSItemProvider {
    func loadDataRepresentation(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            _ = loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data { c.resume(returning: data) } else { c.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
}
