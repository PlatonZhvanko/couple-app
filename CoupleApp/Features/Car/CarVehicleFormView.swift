import SwiftData
import SwiftUI

/// Добавление и правка машины.
struct CarVehicleFormView: View {
    /// `nil` — новая машина.
    let car: CarVehicle?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @AppStorage("car.selectedCarID") private var selectedCarID: String = ""

    @State private var name: String
    @State private var plate: String
    @State private var vin: String
    @State private var yearText: String
    @State private var odometerText: String
    @State private var confirmDelete = false

    init(car: CarVehicle?) {
        self.car = car
        _name = State(initialValue: car?.name ?? "")
        _plate = State(initialValue: car?.plate ?? "")
        _vin = State(initialValue: car?.vin ?? "")
        _yearText = State(initialValue: CarNumber.text(car?.year ?? 0))
        _odometerText = State(initialValue: CarNumber.text(car?.startOdometer ?? 0))
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Марка и модель, например Kia Rio", text: $name)
                    TextField("Госномер", text: $plate)
                        .textInputAutocapitalization(.characters)
                    TextField("VIN", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    LabeledContent("Год выпуска") {
                        TextField("Год", text: $yearText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    LabeledContent("Пробег сейчас, км") {
                        TextField("0", text: $odometerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Дальше пробег обновляется сам по записям о заправках и ТО.")
                }

                if car != nil {
                    Section {
                        Button("Удалить машину", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Вместе с машиной удалятся её журнал и напоминания на обоих телефонах.")
                    }
                }
            }
            .navigationTitle(car == nil ? "Новая машина" : "Машина")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Удалить машину и все её записи?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
            }
        }
    }

    private func save() {
        let item = car ?? {
            let new = CarVehicle(name: "")
            context.insert(new)
            return new
        }()
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.plate = plate.trimmingCharacters(in: .whitespaces)
        item.vin = vin.trimmingCharacters(in: .whitespaces)
        item.year = CarNumber.int(yearText) ?? 0
        item.startOdometer = CarNumber.int(odometerText) ?? 0
        item.markChanged()
        try? context.save()
        if car == nil { selectedCarID = item.syncID.uuidString }
        sync.requestSync()
        dismiss()
    }

    private func delete() {
        guard let car else { return }
        let carID = car.syncID
        let entries = (try? context.fetch(FetchDescriptor<CarEntry>(predicate: #Predicate { $0.carID == carID }))) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<CarReminder>(predicate: #Predicate { $0.carID == carID }))) ?? []
        entries.filter { $0.deletedAt == nil }.forEach { $0.markDeleted() }
        reminders.filter { $0.deletedAt == nil }.forEach { $0.markDeleted() }
        car.markDeleted()
        try? context.save()
        selectedCarID = ""
        sync.requestSync()
        dismiss()
    }
}
