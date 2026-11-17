import SwiftData
import SwiftUI

/// Добавление и правка напоминания о сроке.
struct CarReminderFormView: View {
    let car: CarVehicle
    /// `nil` — новое напоминание.
    let reminder: CarReminder?
    let currentOdometer: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @State private var title: String
    @State private var kind: CarReminderKind
    @State private var hasDate: Bool
    @State private var dueDate: Date
    @State private var hasOdometer: Bool
    @State private var dueOdometerText: String
    @State private var repeatMonthsText: String
    @State private var repeatKmText: String
    @State private var note: String
    @State private var confirmDelete = false

    init(car: CarVehicle, reminder: CarReminder?, currentOdometer: Int) {
        self.car = car
        self.reminder = reminder
        self.currentOdometer = currentOdometer
        _title = State(initialValue: reminder?.title ?? "")
        _kind = State(initialValue: reminder?.kind ?? .document)
        _hasDate = State(initialValue: reminder == nil || reminder?.dueDate != nil)
        _dueDate = State(initialValue: reminder?.dueDate ?? .now)
        _hasOdometer = State(initialValue: (reminder?.dueOdometer ?? 0) > 0)
        _dueOdometerText = State(initialValue: CarNumber.text(reminder?.dueOdometer ?? 0))
        _repeatMonthsText = State(initialValue: CarNumber.text(reminder?.repeatMonths ?? 0))
        _repeatKmText = State(initialValue: CarNumber.text(reminder?.repeatKm ?? 0))
        _note = State(initialValue: reminder?.note ?? "")
    }

    private var dueOdometer: Int { hasOdometer ? (CarNumber.int(dueOdometerText) ?? 0) : 0 }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (hasDate || dueOdometer > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if reminder == nil {
                    Section("Быстрый выбор") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CarReminderTemplate.all) { template in
                                    Button(template.title) { apply(template) }
                                        .buttonStyle(.bordered)
                                        .tint(title == template.title ? Color.accentColor : Color.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    TextField("Что напомнить", text: $title)
                    Picker("Тип", selection: $kind) {
                        ForEach(CarReminderKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("По дате", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker(kind == .document ? "Действует до" : "Когда", selection: $dueDate, displayedComponents: .date)
                    }
                    Toggle("По пробегу", isOn: $hasOdometer.animation())
                    if hasOdometer {
                        LabeledContent("На пробеге, км") {
                            TextField(currentOdometer > 0 ? "сейчас \(currentOdometer)" : "км", text: $dueOdometerText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Срок")
                } footer: {
                    Text("Если указать и дату, и пробег, сработает то, что наступит раньше. Уведомления по дате придут за 30, 7 и 1 день.")
                }

                Section {
                    LabeledContent("Каждые, мес.") {
                        TextField("не повторять", text: $repeatMonthsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Каждые, км") {
                        TextField("не повторять", text: $repeatKmText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Повтор")
                } footer: {
                    Text("Когда отметите «Сделано», срок сам перенесётся на следующий раз.")
                }

                Section {
                    TextField("Заметка: номер полиса, какое масло…", text: $note, axis: .vertical)
                }

                if let reminder {
                    Section {
                        if !reminder.isDone {
                            Button("Отметить сделанным", systemImage: "checkmark.circle") {
                                save()
                                reminder.complete(currentOdometer: currentOdometer)
                                finish()
                            }
                            .disabled(!canSave)
                        }
                        if let lastDone = reminder.lastDoneAt {
                            LabeledContent("Последний раз", value: lastDone.formatted(date: .abbreviated, time: .omitted))
                        }
                        Button("Удалить напоминание", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(reminder == nil ? "Новый срок" : "Напоминание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                        finish()
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Удалить напоминание?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    reminder?.markDeleted()
                    finish()
                }
            }
        }
    }

    private func apply(_ template: CarReminderTemplate) {
        title = template.title
        kind = template.kind
        repeatMonthsText = CarNumber.text(template.months)
        repeatKmText = CarNumber.text(template.km)
        hasDate = template.months > 0
        if template.kind == .service, template.months > 0 {
            dueDate = Calendar.current.date(byAdding: .month, value: template.months, to: .now) ?? .now
        }
        hasOdometer = template.km > 0
        if template.km > 0, currentOdometer > 0 {
            dueOdometerText = String(currentOdometer + template.km)
        }
    }

    private func save() {
        guard canSave else { return }
        let item = reminder ?? {
            let new = CarReminder(carID: car.syncID, kind: kind, member: account.current)
            context.insert(new)
            return new
        }()
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.kind = kind
        item.dueDate = hasDate ? dueDate : nil
        item.dueOdometer = dueOdometer
        item.repeatMonths = CarNumber.int(repeatMonthsText) ?? 0
        item.repeatKm = CarNumber.int(repeatKmText) ?? 0
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.markChanged()
    }

    private func finish() {
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}

/// Готовые варианты напоминаний.
struct CarReminderTemplate: Identifiable {
    let title: String
    let kind: CarReminderKind
    /// Повтор, месяцев. 0 — нет.
    let months: Int
    /// Повтор, км. 0 — нет.
    let km: Int

    var id: String { title }

    static let all: [CarReminderTemplate] = [
        .init(title: "ОСАГО", kind: .document, months: 12, km: 0),
        .init(title: "КАСКО", kind: .document, months: 12, km: 0),
        .init(title: "Техосмотр", kind: .document, months: 24, km: 0),
        .init(title: "Водительские права", kind: .document, months: 120, km: 0),
        .init(title: "Замена масла", kind: .service, months: 12, km: 10_000),
        .init(title: "Воздушный фильтр", kind: .service, months: 0, km: 15_000),
        .init(title: "Салонный фильтр", kind: .service, months: 12, km: 15_000),
        .init(title: "Тормозная жидкость", kind: .service, months: 24, km: 0),
        .init(title: "Смена шин", kind: .service, months: 6, km: 0),
    ]
}
