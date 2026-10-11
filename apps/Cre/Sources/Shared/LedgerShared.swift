import CreCore
import SwiftUI

enum LedgerColors {
    static let income = Color(red: 0.122, green: 0.643, blue: 0.388)
    static let negative = Color(red: 0.831, green: 0.235, blue: 0.235)
}

/// System icon per category; custom ones get a plain tag.
enum CategoryIcon {
    static func symbol(_ name: String) -> String {
        switch name {
        case "餐饮": "fork.knife"
        case "交通": "tram.fill"
        case "购物": "bag.fill"
        case "居住": "house.fill"
        case "娱乐": "gamecontroller.fill"
        case "医疗": "cross.case.fill"
        case "工资": "banknote.fill"
        case "奖金": "gift.fill"
        case "其他": "ellipsis"
        default: "tag.fill"
        }
    }

    private static let tints: [Color] = [
        Color(red: 0.941, green: 0.541, blue: 0.141), Color(red: 0.184, green: 0.435, blue: 0.929),
        Color(red: 0.557, green: 0.357, blue: 0.847), Color(red: 0.898, green: 0.282, blue: 0.302),
        Color(red: 0.0, green: 0.62, blue: 0.67), Color(red: 0.75, green: 0.55, blue: 0.2),
    ]

    /// Same category, same colour: income is green, expenses follow their place in the category list.
    static func tint(_ name: String, isIncome: Bool, data: LedgerData) -> Color {
        if isIncome { return LedgerColors.income }
        if name == "其他" { return .gray }
        let i = data.expenseCategories.firstIndex(of: name) ?? abs(name.hashValue)
        return tints[i % tints.count]
    }
}
