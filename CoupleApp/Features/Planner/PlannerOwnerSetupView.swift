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

    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var newIsProfit = true

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

                kindsSection(title: "📈 Типы прибыли", profit: true)
                kindsSection(title: "📉 Типы трат", profit: false)

                Section("➕ Новый тип") {
                    Picker("Что это", selection: $newIsProfit) {
                        Text("Прибыль").tag(true)
                        Text("Трата").tag(false)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField("🙂", text: $newEmoji)
                            .frame(width: 36)
                        TextField("Название, например «Продажа»", text: $newName)
                            .onSubmit(addKind)
                        Button(action: addKind) {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func kindsSection(title: String, profit: Bool) -> some View {
        let items = kinds.filter { $0.isProfit == profit }
        return Section(title) {
            if items.isEmpty { Text("Пока нет").foregroundStyle(.secondary) }
            ForEach(items) { kind in Text(kind.title) }
                .onDelete { offsets in
                    for index in offsets { items[index].markDeleted() }
                    try? context.save()
                    sync.requestSync()
                }
        }
    }

    private func addKind() {
        PlannerMoneyKindStore.ensure(
            context, name: newName, isProfit: newIsProfit,
            emoji: newEmoji.trimmingCharacters(in: .whitespaces)
        )
        newName = ""
        newEmoji = ""
        sync.requestSync()
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
                        Text("Продажа / приход").tag(true)
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
                    if matching.isEmpty { Text("Типов пока нет. Создай ниже.").foregroundStyle(.secondary) }
                    ForEach(matching) { kind in
                        Button {
                            typeName = typeName == kind.name ? "" : kind.name
                        } label: {
                            HStack {
                                Text(kind.title)
                                Spacer()
                                if typeName == kind.name { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    HStack {
                        TextField("Новый тип", text: $newType)
                        Button("Создать") {
                            if let kind = PlannerMoneyKindStore.ensure(context, name: newType, isProfit: isProfit) {
                                typeName = kind.name
                            }
                            newType = ""
                            sync.requestSync()
                        }
                        .disabled(newType.trimmingCharacters(in: .whitespaces).isEmpty)
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
