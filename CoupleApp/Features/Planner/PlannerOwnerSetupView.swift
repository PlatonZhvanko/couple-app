import SwiftData
import SwiftUI

/// Настройки дел Платони: смена, типы прибыли и трат, разовые операции, цвета.
struct PlannerOwnerSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @AppStorage("planner.shiftAmount") private var shiftAmount: Double = PlannerShift.defaultAmount
    @Query(filter: #Predicate<PlannerMoneyKind> { $0.deletedAt == nil }, sort: \PlannerMoneyKind.name)
    private var kinds: [PlannerMoneyKind]
    @Query(filter: #Predicate<PlannerMoneyOp> { $0.deletedAt == nil }, sort: \PlannerMoneyOp.date, order: .reverse)
    private var ops: [PlannerMoneyOp]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Доход за смену")
                        Spacer()
                        TextField("4000", value: $shiftAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("₽")
                    }
                } header: {
                    Text("🔴 Смена 9:00–21:00")
                } footer: {
                    Text("Смены ставятся в календаре кнопкой «Смены». Каждая идёт в статистику на указанную сумму.")
                }

                Section {
                    NavigationLink {
                        PlannerMoneyKindsView(profit: true)
                    } label: {
                        Label("📈 Типы прибыли/прихода", systemImage: "arrow.up.right.circle")
                    }
                    NavigationLink {
                        PlannerMoneyKindsView(profit: false)
                    } label: {
                        Label("📉 Типы трат", systemImage: "arrow.down.right.circle")
                    }
                    NavigationLink {
                        PlannerErrandKindsView()
                    } label: {
                        Label("🏷 Типы дел", systemImage: "tag")
                    }
                }

                Section {
                    NavigationLink {
                        PlannerColorSettingsView().navigationTitle("Цвета")
                    } label: {
                        Label("🎨 Цвета дел", systemImage: "paintpalette.fill")
                    }
                }

                Section("💲 Последние операции") {
                    if ops.isEmpty { Text("Пока ничего. Операции создаются кнопкой «доллар» в планере.").foregroundStyle(.secondary) }
                    ForEach(ops.prefix(30)) { op in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(op.typeName.isEmpty ? (op.isProfit ? "Приход" : "Трата") : op.typeName)
                                if !op.note.isEmpty { Text(op.note).font(.caption).foregroundStyle(.secondary) }
                                Text(StatisticsFormat.day(op.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((op.isProfit ? "+" : "−") + PlannerPricing.format(op.amount))
                                .foregroundStyle(op.isProfit ? Color.green : Color.red)
                        }
                    }
                    .onDelete { offsets in
                        let shown = Array(ops.prefix(30))
                        for index in offsets { shown[index].markDeleted() }
                        try? context.save()
                        sync.requestSync()
                    }
                }
            }
            .navigationTitle("Настройки дел")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.locale, PlannerCalendar.locale)
    }
}

enum PlannerOwnerSetupFeature {
    static let feature = Feature(
        id: "plannerOwnerSetup",
        title: "Настройки дел",
        systemImage: "slider.horizontal.3",
        availableFor: [.owner]
    ) {
        PlannerOwnerSetupView()
    }
}

/// Кнопка «доллар» у Платони: продажа, приход денег или трата с выбором типа.
struct PlannerMoneyOpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PlannerMoneyKind> { $0.deletedAt == nil }, sort: \PlannerMoneyKind.name)
    private var kinds: [PlannerMoneyKind]

    let day: Date
    @State private var isProfit = true
    @State private var typeName = ""
    @State private var amount: Double?
    @State private var note = ""
    @State private var date: Date
    @State private var newType = ""

    init(day: Date) {
        self.day = day
        _date = State(initialValue: day)
    }

    private var matching: [PlannerMoneyKind] { kinds.filter { $0.isProfit == isProfit } }
    private var isValid: Bool { (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Что", selection: $isProfit) {
                        Text("Прибыль/Приход").tag(true)
                        Text("Трата").tag(false)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Сумма")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("₽")
                    }
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                }
                Section("Тип") {
                    if !typeName.isEmpty {
                        Label("Выбрано: \(typeName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    HStack {
                        TextField("Поиск или новый тип", text: $newType)
                        if !newType.trimmingCharacters(in: .whitespaces).isEmpty
                            && !matching.contains(where: { $0.name.lowercased() == newType.trimmingCharacters(in: .whitespaces).lowercased() }) {
                            Button {
                                if let kind = PlannerMoneyKindStore.ensure(context, name: newType, isProfit: isProfit) {
                                    typeName = kind.name
                                }
                                newType = ""
                                sync.requestSync()
                            } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            .buttonStyle(.borderless)
                        }
                    }
                    if !newType.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(matching.filter { $0.name.localizedCaseInsensitiveContains(newType.trimmingCharacters(in: .whitespaces)) }.prefix(3)) { kind in
                            Button {
                                typeName = kind.name
                                newType = ""
                            } label: {
                                HStack {
                                    Text(kind.title)
                                    Spacer()
                                    if typeName == kind.name { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section("Заметка") {
                    TextField("Что именно", text: $note)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isProfit ? "Приход" : "Трата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(!isValid) }
            }
            .onChange(of: isProfit) { _, _ in typeName = "" }
        }
        .environment(\.locale, PlannerCalendar.locale)
    }

    private func save() {
        let op = PlannerMoneyOp(
            date: date, amount: amount ?? 0, isProfit: isProfit, typeName: typeName,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(op)
        op.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
