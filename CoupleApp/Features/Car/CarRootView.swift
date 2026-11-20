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
    /// Выбранная на входе машина. Каждый раз при входе в раздел сначала выбор.
    @State private var chosenID: UUID?

    private var chosenCar: CarVehicle? { cars.first { $0.syncID == chosenID } }

    private var selectedCar: CarVehicle? {
        cars.first { $0.syncID.uuidString == selectedCarID } ?? cars.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let car = chosenCar {
                    dashboard(for: car)
                        .carCatVisit(hint: catHint(for: car))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if cars.isEmpty {
                    emptyState
                } else {
                    picker
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: chosenID)
            .navigationTitle(chosenCar?.displayName ?? "Авто")
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in
                CarSheetView(sheet: sheet, currentOdometer: currentOdometer)
            }
            .refreshable { await sync.syncNow() }
        }
        .onAppear {
            CarSeed.seedIfNeeded(context: context)
            sync.requestSync()
            rescheduleNotifications()
        }
        .onChange(of: notificationSignature) { rescheduleNotifications() }
    }

    /// О чём напомнить котам-механикам: давно не было пробега, есть сроки или просто привет.
    private func catHint(for car: CarVehicle) -> CarCatLines.Hint {
        let entries = allEntries.of(car)
        let month = Date.now.addingTimeInterval(-30 * 86400)
        if !entries.contains(where: { $0.odometer > 0 && $0.date > month }) { return .odometer }
        if allReminders.of(car).contains(where: { !$0.isDone }) { return .service }
        return .general
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
                CarModel3DView(name: car.displayName)
                    .id(car.syncID)
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

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

    // MARK: - Выбор машины

    private var picker: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Какая машина?")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(cars) { car in
                    Button {
                        selectedCarID = car.syncID.uuidString
                        chosenID = car.syncID
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(CarModelKind.guess(from: car.displayName) == .audiQ3 ? Color.gray : Color(white: 0.15))
                                .frame(width: 70)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(car.displayName).font(.headline)
                                if car.year > 0 { Text("\(car.year) год").font(.subheadline).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
                Button("Добавить машину", systemImage: "plus") { sheet = .car(nil) }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
            }
            .padding()
        }
        .carCatVisit(hint: .general)
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
        ToolbarItem(placement: .topBarLeading) {
            if chosenCar != nil {
                Button("Выбор", systemImage: "chevron.left") { chosenID = nil }
            }
        }
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
            set: { selectedCarID = $0; chosenID = UUID(uuidString: $0) }
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
