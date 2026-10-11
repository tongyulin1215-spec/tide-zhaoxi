import CreCore
import SwiftUI

/// 规划：模块组卡片单列，零散待办，已归档；底部输入条加零散待办（不落到某天）.
struct PlanningScreen: View {
    @ObservedObject var state: MobileState
    @State private var draft = ""
    @State private var creating = false
    @State private var showArchived = false
    @State private var archivedToDelete: TodoGroup?
    @FocusState private var inputFocused: Bool

    private var loose: [Todo] { state.data.todos.filter { $0.groupID == nil } }

    var body: some View {
        List {
            Section {
                PageTitleRow { Text("规划") } trailing: {
                    Button { creating = true } label: { Image(systemName: "plus").frame(width: 40, height: 40) }
                        .accessibilityLabel("新建模块组")
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))

            ForEach(state.data.visibleGroups) { GroupCardView(state: state, group: $0) }

            Section {
                Text("零散待办").font(.headline)
                ForEach(sortedForPlanning(loose)) { PlanItemRow(state: state, todo: $0) }
                if loose.isEmpty { Text("无").foregroundStyle(.tertiary) }
            }

            if !state.data.archivedGroups.isEmpty { archived }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            BottomInputBar(placeholder: "记一条零散待办", text: $draft, focus: $inputFocused) {
                if state.add(draft, defaultToViewingDay: false) { draft = "" }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { NewGroupScreen(state: state) { creating = false } }
        }
        .alert("删除「\(archivedToDelete?.name ?? "")」及其中 \(archivedToDelete.map { g in state.data.todos(in: g.id).filter { !$0.isGroupAnchor }.count } ?? 0) 条待办？",
               isPresented: Binding(get: { archivedToDelete != nil }, set: { if !$0 { archivedToDelete = nil } })) {
            Button("删除", role: .destructive) { if let g = archivedToDelete { state.data.deleteGroup(g.id) }; archivedToDelete = nil }
            Button("取消", role: .cancel) { archivedToDelete = nil }
        }
    }

    private var archived: some View {
        Section {
            Button { withAnimation { showArchived.toggle() } } label: {
                HStack {
                    Text("已归档 \(state.data.archivedGroups.count)")
                    Spacer()
                    Image(systemName: showArchived ? "chevron.down" : "chevron.right").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("已归档 \(state.data.archivedGroups.count)")
            if showArchived {
                ForEach(state.data.archivedGroups) { g in
                    HStack {
                        Text(g.name)
                        Text("\(state.data.todos(in: g.id).filter { !$0.isGroupAnchor }.count) 条").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复") { state.data.updateGroup(g.id) { $0.isArchived = false } }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("restore-\(g.name)")
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) { archivedToDelete = g }
                    }
                }
            }
        }
    }
}
