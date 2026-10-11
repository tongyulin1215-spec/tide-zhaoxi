import CreCore
import SwiftUI

/// 感想 on the phone: about a list item (finished, not yet ticked, or already written) or something outside any list (其他).
/// Same rules as the Mac editor; saving an unticked item ticks it.
struct ReflectionScreen: View {
    @ObservedObject var state: MobileState
    /// Opened from the item itself (规划 / 首页 long press).
    var fixedTodoID: UUID? = nil
    /// Opened from the 感想 list (总结).
    var reflectionID: UUID? = nil
    let onClose: () -> Void

    @State private var groupID: UUID?
    @State private var todoID: UUID?
    @State private var freeID: UUID?
    @State private var title = ""
    @State private var finishedOn = DayKey.from(Date())
    @State private var text = ""
    @State private var ready = false

    private var picking: Bool { fixedTodoID == nil && reflectionID == nil }
    private var isOther: Bool { todoID == nil }
    private var choices: [ReflectionChoice] { groupID.map { state.data.reflectionChoices(in: $0) } ?? [] }
    private var existing: Reflection? {
        if let id = todoID { return state.data.reflection(for: id) }
        return freeID.flatMap { id in state.data.reflections.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                if picking {
                    Section {
                        Picker("清单", selection: $groupID) {
                            ForEach(state.data.listGroups) { Text($0.name).tag(Optional($0.id)) }
                            Text("其他").tag(UUID?.none)
                        }
                        if groupID != nil {
                            Picker("哪一项", selection: $todoID) {
                                ForEach(choices, id: \.todo.id) { c in Text(label(c)).tag(Optional(c.todo.id)) }
                            }
                        }
                    }
                }
                Section {
                    if isOther {
                        TextField("名称", text: $title)
                    } else if !picking, let id = todoID {
                        Text(state.todo(id)?.text ?? "").font(.headline)
                    }
                    DayField(label: "完成时间", day: $finishedOn, latest: state.today)
                } footer: {
                    if let id = todoID, state.todo(id)?.isDone == false { Text("保存后标为完成") }
                }
                Section {
                    TextField("写点感想", text: $text, axis: .vertical)
                        .lineLimit(8...)
                        .accessibilityIdentifier("reflection-text")
                }
                if let r = existing {
                    Section {
                        Button("删除", role: .destructive) { state.data.deleteReflection(id: r.id); onClose() }
                    }
                }
            }
            .navigationTitle("感想").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold).disabled(!canSave) }
            }
        }
        .onAppear(perform: start)
        .onChange(of: groupID) { if ready { todoID = choices.first?.todo.id; freeID = nil; load() } }
        .onChange(of: todoID) { if ready { load() } }
    }

    private func label(_ c: ReflectionChoice) -> String {
        switch c.status {
        case .finished: c.todo.text
        case .unfinished: "\(c.todo.text) · 未完成"
        case .written: "\(c.todo.text) · 已写"
        }
    }

    private var canSave: Bool {
        isOther ? !title.trimmingCharacters(in: .whitespaces).isEmpty : todoID != nil
    }

    private func start() {
        if let id = reflectionID, let r = state.data.reflections.first(where: { $0.id == id }) {
            if let t = r.todoID { todoID = t } else { freeID = r.id; title = r.title ?? "" }
        } else if let id = fixedTodoID {
            todoID = id
        } else if let target = state.data.defaultReflectionTarget() {
            groupID = target.groupID
            todoID = target.todoID
        }
        load()
        ready = true
    }

    private func load() {
        if let id = todoID {
            if let r = state.data.reflection(for: id) {
                finishedOn = r.finishedOn
                text = r.text
            } else {
                finishedOn = state.todo(id)?.completedDay ?? state.today
                text = ""
            }
        } else if let r = existing {
            finishedOn = r.finishedOn
            text = r.text
        } else {
            finishedOn = state.today
            text = ""
        }
    }

    private func save() {
        if let id = todoID {
            state.data.saveReflection(todoID: id, finishedOn: finishedOn, text: text, now: Date())
        } else {
            state.data.saveFreeReflection(id: freeID, title: title.trimmingCharacters(in: .whitespaces),
                                          finishedOn: finishedOn, text: text, now: Date())
        }
        onClose()
    }
}
