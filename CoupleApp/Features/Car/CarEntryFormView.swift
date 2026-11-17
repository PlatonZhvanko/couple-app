import SwiftData
import SwiftUI

/// Добавление и правка записи журнала: заправка или любая трата.
struct CarEntryFormView: View {
    let car: CarVehicle
    /// `nil` — новая запись.
    let entry: CarEntry?
    let currentOdometer: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var category: CarEntryCategory
    @State private var date: Date
    @State private var amountText: String
    @State private var odometerText: String
    @State private var litersText: String
    @State private var priceText: String
    @State private var isFullTank: Bool
    @State private var note: String
    @State private var confirmDelete = false

    init(car: CarVehicle, entry: CarEntry?, initialCategory: CarEntryCategory, currentOdometer: Int) {
        self.car = car
        self.entry = entry
        self.currentOdometer = currentOdometer
        _category = State(initialValue: entry?.category ?? initialCategory)
        _date = State(initialValue: entry?.date ?? .now)
        _amountText = State(initialValue: CarNumber.text(entry?.amount ?? 0))
        _odometerText = State(initialValue: CarNumber.text(entry?.odometer ?? 0))
        _litersText = State(initialValue: CarNumber.text(entry?.liters ?? 0))
        let price: Double = {
            guard let entry, entry.liters > 0 else { return 0 }
            return (entry.amount / entry.liters * 100).rounded() / 100
        }()
        _priceText = State(initialValue: CarNumber.text(price))
        _isFullTank = State(initialValue: entry?.isFullTank ?? true)
        _note = State(initialValue: entry?.note ?? "")
    }

    private var amount: Double? { CarNumber.double(amountText) }
    private var canSave: Bool { (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Что", selection: $category) {
                        ForEach(CarEntryCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(category)
                        }
                    }
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                }

                if category == .fuel {
                    Section {
                        numberField("Литры", text: $litersText, decimal: true)
                        numberField("Цена за литр, ₽", text: $priceText, decimal: true)
                        Toggle("Полный бак", isOn: $isFullTank)
                    } footer: {
                        Text("Расход считается между двумя полными баками, поэтому отмечайте полный бак и пробег.")
                    }
                }

                Section {
                    numberField("Сумма, ₽", text: $amountText, decimal: true)
                    numberField("Пробег, км", text: $odometerText, decimal: false,
                                prompt: currentOdometer > 0 ? "сейчас \(currentOdometer)" : "необязательно")
                } footer: {
                    if let odometer = CarNumber.int(odometerText), odometer > 0, odometer < currentOdometer, entry == nil {
                        Text("Пробег меньше текущего (\(CarFormat.km(currentOdometer))). Проверьте цифры.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField(category == .fuel ? "АЗС, марка топлива" : "Что сделали", text: $note, axis: .vertical)
                }

                if let entry {
                    Section {
                        LabeledContent("Добавил(а)", value: account.name(of: entry.memberValue))
                        Button("Удалить запись", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Новая запись" : "Запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(!canSave)
                }
            }
            .onChange(of: litersText) { recalculateAmount() }
            .onChange(of: priceText) { recalculateAmount() }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>, decimal: Bool, prompt: String? = nil) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: prompt.map { Text($0) })
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Литры × цена = сумма.
    private func recalculateAmount() {
        guard category == .fuel,
              let liters = CarNumber.double(litersText), liters > 0,
              let price = CarNumber.double(priceText), price > 0 else { return }
        amountText = CarNumber.text((liters * price * 100).rounded() / 100)
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        let item = entry ?? {
            let new = CarEntry(carID: car.syncID, category: category, member: account.current)
            context.insert(new)
            return new
        }()
        item.category = category
        item.date = date
        item.amount = amount
        item.odometer = CarNumber.int(odometerText) ?? 0
        item.liters = category == .fuel ? (CarNumber.double(litersText) ?? 0) : 0
        item.isFullTank = category == .fuel ? isFullTank : false
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }

    private func delete() {
        entry?.markDeleted()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
