import CreCore
import Foundation
import Vision

/// Text rows in an image, top to bottom, with pieces on the same row joined left to right.
func recognizeLines(in image: CGImage) async -> [String] {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                cont.resume(returning: [])
                return
            }
            // `perform` is synchronous; read results once here so the continuation resumes exactly once.
            let boxes = (request.results ?? []).compactMap { o -> TextBox? in
                guard let t = o.topCandidates(1).first?.string else { return nil }
                let b = o.boundingBox
                return TextBox(text: t, minX: Double(b.minX), midY: Double(b.midY), height: Double(b.height))
            }
            cont.resume(returning: groupRows(boxes))
        }
    }
}

/// A screenshot as a prefilled entry: amount and merchant read from it, category guessed from the merchant.
/// The Bool says whether an amount was found.
func draftEntry(from image: CGImage, ledger: LedgerData, today: DayKey) async -> (LedgerEntry, Bool) {
    let p = extractPayment(lines: await recognizeLines(in: image))
    let note = p.merchant ?? ""
    let category = guessCategory(note: note, isIncome: p.isIncome, data: ledger)
    return (LedgerEntry(amount: p.amount ?? 0, isIncome: p.isIncome, category: category, note: note, day: today), p.amount != nil)
}
