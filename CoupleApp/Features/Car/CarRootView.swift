import SwiftData
import SwiftUI

struct SpendGroup: Identifiable {
    let title: String
    let sum: Double
    var id: String { title }
}

/// Главный экран раздела «Авто»: выбранная машина, сроки, последние траты.
struct CarRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<CarVehicle> { $0.deletedAt == nil }, sort: \CarVehicle.createdAt)
    private var cars: [CarVehicle]
    @Query(filter: #Predicate<CarEntry> { $0.deletedAt == nil }, sort: \CarEntry.date, order: .reverse)
    private var allEntries: [CarEntry]
    @Query(filter: #Predicate<CarReminder> { $0.deletedAt == nil }, sort: \CarReminder.createdAt)
    private var allReminders: [CarReminder]

    @Query(filter: #Predicate<CarRepair> { $0.deletedAt == nil }, sort: \CarRepair.createdAt)
    private var allRepairs: [CarRepair]

    @AppStorage("car.selectedCarID") private var selectedCarID: String = ""
    @State private var sheet: CarSheet?
    /// Выбранная на входе машина. Каждый раз при входе в раздел сначала выбор.
    @State private var chosenID: UUID?
    @State private var showOdometer = false
    @AppStorage("car.spendPeriod") private var spendPeriod: CarStatsView.Period = .all
    @State private var odometerText = ""

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
            .alert("Пробег сейчас, км", isPresented: $showOdometer) {
                TextField("Например 185000", text: $odometerText).keyboardType(.numberPad)
                Button("Записать") {
                    if let car = chosenCar, let km = CarNumber.int(odometerText) {
                        CarOdometerAction.record(km: km, car: car, member: account.current, context: context, sync: sync)
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            .navigationTitle(chosenCar?.displayName ?? "Авто")
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in
                CarSheetView(sheet: sheet, currentOdometer: currentOdometer)
            }
            .refreshable { await sync.syncNow() }
        }
        .onAppear {
            CarSeed.seedIfNeeded(context: context)
            CarAudiExpensesSeed.seedIfNeeded(context: context)
            sync.requestSync()
            rescheduleNotifications()
        }
        .onChange(of: notificationSignature) { rescheduleNotifications() }
    }

    /// О чём напомнить котам-механикам: давно не было пробега, есть сроки или просто привет.
    private func catHint(for car: CarVehicle) -> CarCatLines.Hint {
        let entries = allEntries.of(car)
        let odometer = CarMath.currentOdometer(car: car, entries: entries)
        // 1. ремонт, который пора делать или скоро срок
        let soon = Date.now.addingTimeInterval(7 * 86400)
        let urgent = allRepairs.of(car).filter {
            !$0.isPaid && (($0.desiredDate ?? .distantFuture) < soon || ($0.desiredOdometer > 0 && odometer >= $0.desiredOdometer - 500))
        }
            .sorted { ($0.desiredDate ?? .distantFuture) < ($1.desiredDate ?? .distantFuture) }
        if let repair = urgent.first { return .repair(title: repair.title, price: repair.price) }
        // 2. давно не было пробега
        let month = Date.now.addingTimeInterval(-30 * 86400)
        if !entries.contains(where: { $0.odometer > 0 && $0.date > month }) { return .odometer }
        // 3. ТО: сколько проехали с последнего
        let lastService = entries.filter { $0.category == .service && $0.odometer > 0 }.map(\.odometer).max()
        if let last = lastService, odometer - last > 8000 { return .service(lastKm: last, nowKm: odometer) }
        if lastService == nil { return .noService }
        if allRepairs.of(car).contains(where: { !$0.isPaid }) { return .service(lastKm: lastService ?? 0, nowKm: odometer) }
        return .general
    }

    /// Траты по категориям: ремонты, бензин, ТО и свои категории.
    private func spendGroups(_ entries: [CarEntry]) -> [SpendGroup] {
        var sums: [String: Double] = [:]
        for entry in entries { sums[entry.categoryTitle, default: 0] += entry.amount }
        return sums.map { SpendGroup(title: $0.key, sum: $0.value) }.sorted { $0.sum > $1.sum }
    }

    private func interval(for period: CarStatsView.Period) -> DateInterval {
        switch period {
        case .month: CarMath.currentMonth()
        case .year: CarMath.currentYear()
        case .all: DateInterval(start: .distantPast, end: .distantFuture)
        }
    }

    private func hasAlerts(_ car: CarVehicle) -> Bool {
        !CarAttention.alerts(car: car, entries: allEntries.of(car), repairs: allRepairs.of(car), reminders: allReminders.of(car)).isEmpty
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

            let alerts = CarAttention.alerts(car: car, entries: entries, repairs: allRepairs.of(car), reminders: allReminders.of(car))
            if !alerts.isEmpty {
                Section {
                    ForEach(alerts) { alert in
                        Label(alert.text, systemImage: alert.urgent ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(alert.urgent ? .red : .orange)
                            .font(.subheadline.weight(.medium))
                    }
                } header: {
                    Text("Внимание")
                } footer: {
                    Text("Висит, пока ТО или ремонт не сделаны.")
                }
            }

            Section {
                HStack(alignment: .top) {
                    CarStatTile(title: "Пробег", value: odometer > 0 ? CarFormat.km(odometer) : "—")
                    CarStatTile(title: "За месяц", value: CarFormat.money(CarMath.total(entries, in: CarMath.currentMonth())))
                    CarStatTile(title: "Расход", value: fuel.averageLitersPer100.map { CarFormat.consumption($0) } ?? "—")
                }
                .padding(.vertical, 4)

                HStack(spacing: 6) {
                    quickButton("Бензин", systemImage: "fuelpump.fill") {
                        sheet = .fuel(car)
                    }
                    quickButton("Трата", systemImage: "rublesign.circle.fill") {
                        sheet = .entry(car: car, entry: nil, category: .other)
                    }
                    quickButton("ТО", systemImage: "wrench.and.screwdriver.fill") {
                        sheet = .service(car)
                    }
                    quickButton("Пробег", systemImage: "gauge.with.needle") {
                        odometerText = ""
                        showOdometer = true
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
                NavigationLink {
                    CarRepairsView(car: car)
                } label: {
                    let open = allRepairs.of(car).filter { !$0.isPaid }
                    HStack {
                        Label("Ремонты и что сделать", systemImage: "wrench.and.screwdriver.fill")
                        Spacer()
                        if !open.isEmpty {
                            Text(CarFormat.money(open.reduce(0) { $0 + $1.price }))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Picker("Период", selection: $spendPeriod) {
                    ForEach(CarStatsView.Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                let spent = entries.filter { interval(for: spendPeriod).contains($0.date) && $0.amount > 0 }
                LabeledContent("Потрачено всего") {
                    Text(CarFormat.money(spent.reduce(0) { $0 + $1.amount }))
                        .font(.headline).monospacedDigit()
                }
                if spent.isEmpty {
                    Text("За этот период трат нет.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(spendGroups(spent)) { group in
                    LabeledContent(group.title) {
                        Text(CarFormat.money(group.sum)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Траты за период")
            } footer: {
                Text("Ремонты, бензин, ТО и всё остальное, что записано по машине.")
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
                NavigationLink("Аналитика трат") {
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
                                HStack(spacing: 6) {
                                    Text(car.displayName).font(.headline)
                                    if hasAlerts(car) {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                                    }
                                }
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
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.callout)
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
            + allRepairs.map { "\($0.syncID)\($0.updatedAt.timeIntervalSince1970)" }
        let names = cars.map { "\($0.syncID)\($0.name)" }
        return (reminders + names).joined(separator: "|")
    }

    private func rescheduleNotifications() {
        CarNotifications.reschedule(
            reminders: allReminders, cars: cars, repairs: allRepairs,
            lastMileage: allEntries.filter { $0.odometer > 0 }.map(\.date).max()
        )
    }
}
