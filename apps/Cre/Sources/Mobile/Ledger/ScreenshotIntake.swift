import CreCore
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Screenshots on their way to the ledger: recognized one at a time, each confirmed in the form ("1/3").
@MainActor
final class ScreenshotIntake: ObservableObject {
    struct Draft: Identifiable {
        let id = UUID()
        let entry: LedgerEntry
        let position: String?
        /// The screenshot it was read from, shown above the form so the numbers can be checked against it.
        let image: UIImage?
    }

    @Published private(set) var draft: Draft?
    @Published private(set) var recognizing = false
    /// The newest screenshot from the last few minutes that hasn't been offered yet (needs photo access).
    @Published private(set) var latest: PHAsset?

    private var queue = DraftQueue<UIImage>([])

    func take(_ images: [UIImage], state: MobileState) {
        guard !images.isEmpty else { return }
        let idle = queue.current == nil
        queue.append(contentsOf: images)
        if idle { next(state) }
    }

    /// The form was saved or cancelled.
    func finished(state: MobileState) {
        draft = nil
        queue.advance()
        next(state)
    }

    private func next(_ state: MobileState) {
        guard let shown = queue.current, let image = shown.cgImage ?? Self.cg(shown) else { return }
        let position = queue.position
        recognizing = true
        Task {
            let (entry, _) = await draftEntry(from: image, ledger: state.ledger, today: state.today)
            recognizing = false
            draft = Draft(entry: entry, position: position, image: shown)
        }
    }

    private static func cg(_ image: UIImage) -> CGImage? {
        UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }.cgImage
    }

    // MARK: Latest screenshot (「记录这张？」)

    private static let offeredKey = "offeredScreenshots"
    private static let askedKey = "askedPhotoAccess"

    /// Asks for photo access once (the first time 记账 opens); afterwards only looks if access was given.
    func checkLatest() {
        guard !DemoData.isOn else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined && !UserDefaults.standard.bool(forKey: Self.askedKey) {
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                if s == .authorized || s == .limited { Task { @MainActor in self.findLatest() } }
            }
            return
        }
        if status == .authorized || status == .limited { findLatest() }
    }

    private func findLatest() {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate > %@",
                                        PHAssetMediaSubtype.photoScreenshot.rawValue, Date().addingTimeInterval(-10 * 60) as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        let offered = Set(UserDefaults.standard.stringArray(forKey: Self.offeredKey) ?? [])
        let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject
        latest = asset.flatMap { offered.contains($0.localIdentifier) ? nil : $0 }
    }

    /// 「×」 or after taking it: don't offer this one again.
    func dismissLatest() {
        guard let a = latest else { return }
        var offered = UserDefaults.standard.stringArray(forKey: Self.offeredKey) ?? []
        offered = Array((offered + [a.localIdentifier]).suffix(50))
        UserDefaults.standard.set(offered, forKey: Self.offeredKey)
        latest = nil
    }

    func takeLatest(state: MobileState) {
        guard let a = latest else { return }
        dismissLatest()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: a, options: options) { data, _, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            Task { @MainActor in self.take([image], state: state) }
        }
    }

    // MARK: Share extension inbox

    static var inbox: URL { MobileFiles.directory.appendingPathComponent("inbox", isDirectory: true) }

    /// Images the share extension left; true when there were any.
    @discardableResult
    func collectInbox(state: MobileState) -> Bool {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.inbox, includingPropertiesForKeys: [.creationDateKey]),
              !files.isEmpty else { return false }
        let sorted = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let images = sorted.compactMap { (try? Data(contentsOf: $0)).flatMap(UIImage.init(data:)) }
        sorted.forEach { try? fm.removeItem(at: $0) }
        take(images, state: state)
        return !images.isEmpty
    }

    /// CRE_DEMO_SCREENSHOT=noAmount: a made-up screenshot with a merchant but no amount, for UI tests.
    /// CRE_DEMO_SCREENSHOT=pastePayment: a made-up payment screenshot left on the clipboard, for the demo video's 粘贴.
    func takeDemoScreenshot(state: MobileState) {
        if DemoData.isOn, ProcessInfo.processInfo.environment["CRE_DEMO_SCREENSHOT"] == "pastePayment" {
            // A real payment screenshot when one is given (CRE_DEMO_PASTE_FILE), else a drawn one.
            let file = ProcessInfo.processInfo.environment["CRE_DEMO_PASTE_FILE"].flatMap(UIImage.init(contentsOfFile:))
            UIPasteboard.general.image = file ?? Self.demoPayment()
            return
        }
        guard DemoData.isOn, ProcessInfo.processInfo.environment["CRE_DEMO_SCREENSHOT"] == "noAmount" else { return }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 300)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
            ("收款方 星巴克咖啡" as NSString).draw(at: CGPoint(x: 40, y: 120),
                                              withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black])
        }
        take([image], state: state)
    }
}

extension ScreenshotIntake {
    /// A payment-confirmation-style picture: 支付成功 / merchant / amount / time.
    static func demoPayment() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 750, height: 900)).image { ctx in
            UIColor(white: 0.96, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 750, height: 900))
            func line(_ s: String, _ y: CGFloat, _ size: CGFloat, _ weight: UIFont.Weight = .regular, _ color: UIColor = .black) {
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
                let w = (s as NSString).size(withAttributes: attrs).width
                (s as NSString).draw(at: CGPoint(x: (750 - w) / 2, y: y), withAttributes: attrs)
            }
            line("支付成功", 140, 40, .medium, UIColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1))
            line("瑞幸咖啡", 260, 36)
            line("-23.50", 340, 80, .semibold)
            line("商品  生椰拿铁", 520, 30, .regular, .darkGray)
            line("支付时间  2026年10月9日 08:31", 580, 30, .regular, .darkGray)
        }
    }
}

/// The camera, wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}

/// The camera button beside the ledger input: 拍照 / 从相册选（可多选）/ 粘贴.
struct ScreenshotMenu: View {
    @ObservedObject var state: MobileState
    @ObservedObject var intake: ScreenshotIntake
    @State private var picking = false
    @State private var shooting = false
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { shooting = true } label: { Label("拍照", systemImage: "camera") }
            }
            Button { picking = true } label: { Label("从相册选", systemImage: "photo.on.rectangle") }
            Button { intake.take(UIPasteboard.general.images ?? [], state: state) } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                .disabled(!UIPasteboard.general.hasImages)
        } label: {
            Image(systemName: intake.recognizing ? "hourglass" : "camera.viewfinder")
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("截图记账")
        .photosPicker(isPresented: $picking, selection: $items, maxSelectionCount: 20, matching: .images)
        .onChange(of: items) {
            let picked = items
            items = []
            Task {
                var images: [UIImage] = []
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
                }
                intake.take(images, state: state)
            }
        }
        .fullScreenCover(isPresented: $shooting) {
            CameraPicker { image in
                shooting = false
                if let image { intake.take([image], state: state) }
            }
            .ignoresSafeArea()
        }
    }
}
