import SwiftData
import SwiftUI

/// Максимум литров в баке обеих машин.
let carTankLiters: Double = 60

// MARK: - Заправка

/// Компактная заправка: литры (бак до 60 л), всё остальное необязательно.
struct CarFuelFormView: View {
    let car: CarVehicle
    let currentOdometer: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var liters: Double = 30
    @State private var amountText = ""
    @State private var odometerText = ""
    @State private var station = ""
    @State private var fullTank = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Залито") {
                        Text(CarFormat.liters(liters)).font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    Slider(value: $liters, in: 1...carTankLiters, step: 1)
                    Toggle("Полный бак", isOn: $fullTank)
                } footer: {
                    Text("Бак до \(Int(carTankLiters)) л.")
                }
                Section("Необязательно") {
                    LabeledContent("Сумма, ₽") {
                        TextField("—", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Пробег, км") {
                        TextField(currentOdometer > 0 ? "сейчас \(currentOdometer)" : "—", text: $odometerText)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    TextField("АЗС", text: $station)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Заправка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Записать", action: save) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let entry = CarEntry(carID: car.syncID, category: .fuel, member: account.current)
        entry.liters = liters
        entry.isFullTank = fullTank
        entry.amount = CarNumber.double(amountText) ?? 0
        entry.odometer = CarNumber.int(odometerText) ?? 0
        entry.note = station.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(entry)
        entry.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}

// MARK: - ТО

/// Запись ТО: пробег, где делали, сколько стоило.
struct CarServiceFormView: View {
    let car: CarVehicle
    let currentOdometer: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var odometerText = ""
    @State private var date = Date.now
    @State private var place = ""
    @State private var costText = ""

    private var odometer: Int { CarNumber.int(odometerText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Пробег, км") {
                        TextField("0", text: $odometerText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Когда", selection: $date, displayedComponents: .date)
                    TextField("Где делали ТО", text: $place)
                    LabeledContent("Стоимость, ₽") {
                        TextField("0", text: $costText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Следующее ТО через \(CarFormat.km(car.serviceIntervalKm)), напомним заранее. Интервал меняется в настройках машины.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("ТО")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Записать", action: save).disabled(odometer <= 0)
                }
            }
            .onAppear { if odometerText.isEmpty, currentOdometer > 0 { odometerText = String(currentOdometer) } }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let entry = CarEntry(carID: car.syncID, category: .service, member: account.current)
        entry.date = date
        entry.odometer = odometer
        entry.amount = CarNumber.double(costText) ?? 0
        entry.note = place.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(entry)
        entry.markChanged()
        // ТО попадает и в список ремонтов (как оплаченное), и в аналитику через трату.
        let repair = CarRepair(carID: car.syncID, member: account.current)
        repair.title = "ТО на \(CarFormat.km(odometer))"
        repair.price = entry.amount
        repair.isPaid = true
        repair.paidAt = date
        repair.entryID = entry.syncID
        repair.note = entry.note.isEmpty ? "" : "Где: \(entry.note)"
        context.insert(repair)
        repair.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}

// MARK: - Пробег

enum CarOdometerAction {
    /// Записать текущий пробег отдельной записью (сумма 0): он учитывается везде.
    @MainActor
    static func record(km: Int, car: CarVehicle, member: CoupleMember, context: ModelContext, sync: SyncCoordinator) {
        guard km > 0 else { return }
        let entry = CarEntry(carID: car.syncID, category: .other, member: member)
        entry.odometer = km
        entry.note = "Запись пробега"
        context.insert(entry)
        entry.markChanged()
        try? context.save()
        sync.requestSync()
    }
}

// MARK: - Внимание: ТО и ремонты, которые пора сделать

struct CarAlert: Identifiable {
    let id: String
    let text: String
    let urgent: Bool
}

enum CarAttention {
    /// Предупреждения висят, пока ТО или ремонт не сделаны.
    static func alerts(car: CarVehicle, entries: [CarEntry], repairs: [CarRepair], reminders: [CarReminder]) -> [CarAlert] {
        var result: [CarAlert] = []
        let odometer = CarMath.currentOdometer(car: car, entries: entries)
        let soon = Date.now.addingTimeInterval(14 * 86400)

        // ТО по пробегу
        if let last = entries.filter({ $0.category == .service && $0.odometer > 0 }).map(\.odometer).max() {
            let next = last + max(1000, car.serviceIntervalKm)
            if odometer >= next {
                result.append(CarAlert(id: "service", text: "ТО пора: было на \(CarFormat.km(last)), следующее на \(CarFormat.km(next))", urgent: true))
            } else if odometer >= next - 500 {
                result.append(CarAlert(id: "service", text: "Скоро ТО: через \(CarFormat.km(next - odometer))", urgent: false))
            }
        }

        // Ремонты: по дате или по пробегу
        for repair in repairs where !repair.isPaid {
            let name = repair.title.isEmpty ? "Ремонт" : repair.title
            if let due = repair.desiredDate, due < soon {
                let overdue = due < .now
                result.append(CarAlert(id: "r.d.\(repair.syncID)",
                                       text: overdue ? "\(name): срок прошёл" : "\(name): до \(due.formatted(date: .abbreviated, time: .omitted))",
                                       urgent: overdue))
            }
            if repair.desiredOdometer > 0, odometer >= repair.desiredOdometer - 500 {
                let over = odometer >= repair.desiredOdometer
                result.append(CarAlert(id: "r.o.\(repair.syncID)",
                                       text: over ? "\(name): пробег \(CarFormat.km(repair.desiredOdometer)) достигнут" : "\(name): скоро \(CarFormat.km(repair.desiredOdometer))",
                                       urgent: over))
            }
        }

        // Сроки документов
        for reminder in reminders where !reminder.isDone {
            if let due = reminder.dueDate, due < soon {
                result.append(CarAlert(id: "rem.\(reminder.syncID)",
                                       text: "\(reminder.title): \(due < .now ? "срок прошёл" : "до \(due.formatted(date: .abbreviated, time: .omitted))")",
                                       urgent: due < .now))
            }
        }
        return result
    }
}
