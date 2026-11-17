import SwiftData
import SwiftUI

/// Главный экран раздела «Авто»: выбранная машина, сроки, последние траты.
struct CarRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<CarVehicle> { $0.deletedAt == nil }, sort: \CarVehicle.createdAt)
    private var cars: [CarVehicle]
    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil }, sort: \CarEntry.date, order: .reverse)
    private var allEntries: [CarEntry]
    @Query(filter: #Predicate<CarReminder> { $0.deletedAt == nil }, sort: \CarReminder.createdAt)
    private var allReminders: [CarReminder]

    @AppStorage("car.selectedCarID") private var selectedCarID: String = ""
    @State private var sheet: CarSheet?

    private var selectedCar: CarVehicle? {
        cars.first { $0.syncID.uuidString == selectedCarID } ?? cars.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let car = selectedCar {
                    dashboard(for: car)
                } else {
                    emptyState
                }
            }
            .navigationTitle(selectedCar?.displayName ?? "Авто")
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in
                CarSheetView(sheet: sheet, currentOdometer: currentOdometer)
            }
            .refreshable { await sync.syncNow() }
        }
        .onAppear(perform: rescheduleNotifications)
        .onChange(of: notificationSignature) { rescheduleNotifications() }
    }

    private var currentOdometer: Int {
        guard let car = selectedCar else { return 0 }
        return CarMath.currentOdometer(car: car, entries: allEntries.of(car))
    }

    // MARK: - Экран машины

    @ViewBuilder
    private func dashboard(for car: CarVehicle) -> some View {
        let entries = allEntries.of(car)
        let reminders = allReminders.of(car).filter { !$0.isDone }
        let odometer = CarMath.currentOdometer(car: car, entries: entries)
        let fuel = CarMath.fuelStats(entries)
        let upcoming = reminders.sortedByUrgency(currentOdometer: odometer)

        List {
            Section {
                HStack(alignment: .top) {
                    CarStatTile(title: "Пробег", value: odometer > 0 ? CarFormat.km(odometer) : "—")
                    CarStatTile(title: "За месяц", value: CarFormat.money(CarMath.total(entries, in: CarMath.currentMonth())))
                    CarStatTile(title: "Расход", value: fuel.averageLitersPer100.map { CarFormat.consumption($0) } ?? "—")
                }
                .padding(.vertical, 4)

                HStack(spacing: 8) {
                    quickButton("Заправка", systemImage: "fuelpump.fill") {
                        sheet = .entry(car: car, entry: nil, category: .fuel)
                    }
                    quickButton("Трата", systemImage: "rublesign.circle.fill") {
                        sheet = .entry(car: car, entry: nil, category: .service)
                    }
                    quickButton("Срок", systemImage: "bell.fill") {
                        sheet = .reminder(car: car, reminder: nil)
                    }
                }
            } footer: {
                if !car.plate.isEmpty {
                    Text(car.plate.uppercased())
                }
            }

            Section {
                if upcoming.isEmpty {
                    Text("Добавьте ОСАГО, техосмотр или замену масла, и приложение напомнит заранее.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(upcoming.prefix(5)) { reminder in
                        Button {
                            sheet = .reminder(car: car, reminder: reminder)
                        } label: {
                            CarReminderRow(reminder: reminder, currentOdometer: odometer)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .leading) {
                            Button("Сделано", systemImage: "checkmark") {
                                reminder.complete(currentOdometer: odometer)
                                save()
                            }
                            .tint(.green)
                        }
                    }
                }
                NavigationLink("Все напоминания") {
                    CarRemindersView(car: car)
                }
            } header: {
                Text("Сроки")
            }

            Section {
                if entries.isEmpty {
                    Text("Здесь появятся заправки и траты.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries.prefix(5)) { entry in
                        Button {
                            sheet = .entry(car: car, entry: entry, category: entry.category)
                        } label: {
                            CarEntryRow(entry: entry)
                        }
                        .tint(.primary)
                    }
                }
                NavigationLink("Весь журнал") {
                    CarHistoryView(car: car)
                }
                NavigationLink("Итоги и расход") {
                    CarStatsView(car: car)
                }
            } header: {
                Text("Последние записи")
            }
        }
    }

    private func quickButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Пока нет машины", systemImage: "car.fill")
        } description: {
            Text("Добавьте машину, чтобы вести заправки, ТО, траты и сроки документов. Данные увидите вы оба.")
        } actions: {
            Button("Добавить машину") { sheet = .car(nil) }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Меню машин

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if cars.count > 1 {
                    Picker("Машина", selection: carSelection) {
                        ForEach(cars) { car in
                            Text(car.displayName).tag(car.syncID.uuidString)
                        }
                    }
                }
                if let car = selectedCar {
                    Button("Изменить машину", systemImage: "pencil") { sheet = .car(car) }
                }
                Button("Добавить машину", systemImage: "plus") { sheet = .car(nil) }
            } label: {
                Image(systemName: "car.2.fill")
            }
        }
    }

    private var carSelection: Binding<String> {
        Binding(
            get: { selectedCar?.syncID.uuidString ?? "" },
            set: { selectedCarID = $0 }
        )
    }

    // MARK: - Сохранение и уведомления

    private func save() {
        try? context.save()
        sync.requestSync()
    }

    /// Меняется, когда меняются сроки или названия: тогда уведомления пересоздаются.
    private var notificationSignature: String {
        let reminders = allReminders.map { "\($0.syncID)\($0.updatedAt.timeIntervalSince1970)\($0.isDone)" }
        let names = cars.map { "\($0.syncID)\($0.name)" }
        return (reminders + names).joined(separator: "|")
    }

    private func rescheduleNotifications() {
        CarNotifications.reschedule(reminders: allReminders, cars: cars)
    }
}
