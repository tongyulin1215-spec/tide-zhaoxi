import Foundation

public struct ExtractedPayment: Equatable, Sendable {
    public var amount: Int?
    public var merchant: String?
    /// "+100.00" style amounts are money coming in.
    public var isIncome: Bool = false
}

/// One recognized piece of text with its position (Vision's normalized coordinates, y up).
public struct TextBox: Equatable, Sendable {
    public var text: String
    public var minX: Double
    public var midY: Double
    public var height: Double

    public init(text: String, minX: Double, midY: Double, height: Double) {
        self.text = text
        self.minX = minX
        self.midY = midY
        self.height = height
    }
}

/// Puts boxes on the same visual row together (left to right), rows top to bottom.
/// Bill pages show "实付款 … ¥45.00" as one row that OCR returns as two pieces.
public func groupRows(_ boxes: [TextBox]) -> [String] {
    var rows: [[TextBox]] = []
    for b in boxes.sorted(by: { $0.midY > $1.midY }) {
        if let i = rows.indices.last, let ref = rows[i].first, abs(ref.midY - b.midY) < max(ref.height, b.height) * 0.5 {
            rows[i].append(b)
        } else {
            rows.append([b])
        }
    }
    return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
}

private let numberRe = try! NSRegularExpression(pattern: #"[-−]?[¥￥]?\s*(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?"#)
private let paidLabels = ["实付款", "实付", "支付金额", "付款金额", "实际支付", "合计", "总计", "金额"]
private let merchantLabels = ["商户全称", "商户名称", "收款方", "商户", "商家", "店铺"]
private let noise = ["支付成功", "交易成功", "已完成", "订单详情", "账单详情", "交易详情", "当前状态", "付款成功"]

private func cents(in line: String) -> Int? {
    guard let m = numberRe.matches(in: line, range: NSRange(line.startIndex..., in: line)).last,
          let ip = Range(m.range(at: 1), in: line).map({ line[$0].replacingOccurrences(of: ",", with: "") }),
          let yuan = Int(ip), yuan <= maxYuan else { return nil }
    let f = Range(m.range(at: 2), in: line).map { String(line[$0]) } ?? ""
    let c = f.isEmpty ? 0 : Int(f.count == 1 ? f + "0" : f)!
    let v = yuan * 100 + c
    return v > 0 ? v : nil
}

/// Reads amount and merchant from a payment screenshot's text lines (top to bottom).
/// Amount: a labeled line (实付 / 支付金额 / 合计 …), else a line that is just a price (¥32, -23.50).
/// Merchant: a labeled line (商户全称 / 收款方 …), else the first line that is neither noise nor a number.
public func extractPayment(lines raw: [String]) -> ExtractedPayment {
    let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    var amount: Int?
    var amountLine: String?
    for label in paidLabels {
        guard let i = lines.firstIndex(where: { $0.hasPrefix(label) }) else { continue }
        if let c = cents(in: lines[i]) { amount = c; amountLine = lines[i]; break }
        // Label alone on its line: the value is on the next one.
        if i + 1 < lines.count, let c = cents(in: lines[i + 1]) { amount = c; amountLine = lines[i + 1]; break }
    }
    if amount == nil {
        let priceOnly = try! NSRegularExpression(pattern: #"^[-−+]?\s*[¥￥]?\s*(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?$"#)
        let prices = lines.filter { priceOnly.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        // Prefer what looks like money (¥, sign or decimals) over bare numbers like a battery level.
        let money = prices.first { $0.contains("¥") || $0.contains("￥") || $0.hasPrefix("-") || $0.hasPrefix("−") || $0.hasPrefix("+") || $0.contains(".") }
        amountLine = money ?? prices.first
        amount = amountLine.flatMap(cents)
    }

    var merchant: String?
    for label in merchantLabels {
        if let line = lines.first(where: { $0.hasPrefix(label) }) {
            let v = line.dropFirst(label.count).trimmingCharacters(in: CharacterSet(charactersIn: " ：:"))
            if !v.isEmpty { merchant = v; break }
        }
    }
    if merchant == nil {
        merchant = lines.first { line in
            !noise.contains { line.hasPrefix($0) } && cents(in: line) == nil && line.count <= 30
                && !paidLabels.contains { line.hasPrefix($0) }
        }
    }
    let isIncome = amountLine.map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("+") } ?? false
    return ExtractedPayment(amount: amount, merchant: merchant, isIncome: isIncome)
}
