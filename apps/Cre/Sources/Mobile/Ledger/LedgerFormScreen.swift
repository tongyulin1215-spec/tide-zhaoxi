import CreCore
import SwiftUI

/// One entry: new (entry == nil, optionally prefilled from a screenshot or a typed line) or edit an existing one.
struct LedgerFormScreen: View {
    @ObservedObject var state: MobileState
    let entry: LedgerEntry?
    var prefill: LedgerEntry? = nil
    /// "2/3" when several screenshots came in together.
    var position: String? = nil
    /// The screenshot the entry was read from.
    var image: UIImage? = nil
    let onClose: () -> Void

    @State private var isIncome = false
    @State private var amountText = ""
    @State private var category = "其他"
    @State private var day = DayKey.from(Date())
    @State private var note = ""
    @FocusState private var amountFocused: Bool

    private var cents: Int? { parseAmount(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("截图")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                Section {
                    Picker("类型", selection: $isIncome) {
                        Text("支出").tag(false)
                        Text("收入").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .focused($amountFocused)
                }
                Section("分类") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                        ForEach(categoryOptions, id: \.self) { c in categoryCell(c) }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextField("备注", text: $note)
                    DayField(label: "日期", day: $day, latest: state.today)
                }
                if let entry {
                    Section {
                        Button("删除", role: .destructive) { state.ledger.delete(entry.id); onClose() }
                    }
                }
            }
            .navigationTitle(position.map { "记一笔 \($0)" } ?? (entry == nil ? "记一笔" : "编辑"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold).disabled(cents == nil) }
            }
            .onChange(of: isIncome) {
                // Back to the entry's own type: keep its category even if it was deleted from the list.
                if let e = entry, isIncome == e.isIncome { category = e.category; return }
                if !state.ledger.categories(income: isIncome).contains(category) { category = "其他" }
            }
        }
        .onAppear(perform: load)
    }

    private func categoryCell(_ c: String) -> some View {
        let on = c == category
        let tint = CategoryIcon.tint(c, isIncome: isIncome, data: state.ledger)
        return Button { category = c } label: {
            VStack(spacing: 4) {
                Image(systemName: CategoryIcon.symbol(c)).font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(on ? tint : tint.opacity(0.13), in: Circle())
                    .foregroundStyle(on ? Color.white : tint)
                Text(c).font(.caption).foregroundStyle(on ? Color.primary : Color.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var categoryOptions: [String] {
        var list = state.ledger.categories(income: isIncome)
        if !list.contains(category) { list.append(category) }
        return list
    }

    private func load() {
        day = state.today
        guard let e = entry ?? prefill else { amountFocused = true; return }
        isIncome = e.isIncome
        category = e.category
        day = e.day
        note = e.note
        if e.amount > 0 {
            amountText = String(format: e.amount % 100 == 0 ? "%.0f" : "%.2f", Double(e.amount) / 100)
        } else {
            amountFocused = true
        }
    }

    private func save() {
        guard let cents else { return }
        let n = note.trimmingCharacters(in: .whitespaces)
        if let entry {
            state.ledger.update(entry.id) {
                $0.amount = cents; $0.isIncome = isIncome; $0.category = category; $0.day = day; $0.note = n.isEmpty ? category : n
            }
        } else {
            state.ledger.add(LedgerEntry(amount: cents, isIncome: isIncome, category: category,
                                         note: n.isEmpty ? category : n, day: day), now: Date())
        }
        onClose()
    }
}

/// 起始余额: an amount on a day; later entries move it.
struct OpeningScreen: View {
    @ObservedObject var state: MobileState
    let onClose: () -> Void

    @State private var text = ""
    @State private var day = DayKey.from(Date())

    /// "1200", "-35.5", "0" → cents.
    private var cents: Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let negative = t.hasPrefix("-")
        let body = negative ? String(t.dropFirst()) : t
        if Double(body) == 0 { return 0 }
        return parseAmount(body).map { negative ? -$0 : $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("金额", text: $text).keyboardType(.numbersAndPunctuation)
                    DayField(label: "日期", day: $day, latest: state.today)
                }
                if state.ledger.opening != nil {
                    Section { Button("清除", role: .destructive) { state.ledger.opening = nil; onClose() } }
                }
            }
            .navigationTitle("起始余额").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let cents { state.ledger.opening = OpeningBalance(amount: cents, day: day) }
                        onClose()
                    }
                    .fontWeight(.semibold).disabled(cents == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            day = state.today
            if let o = state.ledger.opening {
                text = String(format: "%.2f", Double(o.amount) / 100).replacingOccurrences(of: ".00", with: "")
                day = o.day
            }
        }
    }
}

/// 分类: add, rename, remove (「其他」 stays).
struct CategoryScreen: View {
    @ObservedObject var state: MobileState
    let onClose: () -> Void
    @State private var income = false
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var conflict = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("类型", selection: $income) {
                        Text("支出").tag(false)
                        Text("收入").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(state.ledger.categories(income: income), id: \.self) { c in
                        HStack(spacing: 10) {
                            Image(systemName: CategoryIcon.symbol(c))
                                .foregroundStyle(CategoryIcon.tint(c, isIncome: income, data: state.ledger)).frame(width: 24)
                            Text(c)
                        }
                        .swipeActions {
                            if c != "其他" {
                                Button("删除", role: .destructive) { state.ledger.removeCategory(c, income: income) }
                                Button("改名") { renaming = c; renameText = c }.tint(.gray)
                            }
                        }
                    }
                    HStack {
                        TextField("新分类", text: $newName).onSubmit(add)
                        Button("添加", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("分类").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) } }
            .alert("改名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("名称", text: $renameText)
                Button("保存") {
                    let n = renameText.trimmingCharacters(in: .whitespaces)
                    if let c = renaming {
                        if n != c && state.ledger.categories(income: income).contains(n) { conflict = true }
                        else { state.ledger.renameCategory(c, to: n, income: income) }
                    }
                    renaming = nil
                }
                Button("取消", role: .cancel) { renaming = nil }
            }
            .alert("已有同名分类", isPresented: $conflict) { Button("好", role: .cancel) {} }
        }
    }

    private func add() {
        state.ledger.addCategory(newName, income: income)
        newName = ""
    }
}
