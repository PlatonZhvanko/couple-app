import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Планер

/// Дела питомцев по дате в календаре «Планера»: розовые, с лапкой, у обоих.
enum PetsCalendar {
    @MainActor
    static func items(context: ModelContext, interval: DateInterval) -> [CalendarItem] {
        let from = interval.start.addingTimeInterval(-86_400)
        let to = interval.end
        let descriptor = FetchDescriptor<PetsTask>(
            predicate: #Predicate { $0.deletedAt == nil && $0.desiredDate != nil }
        )
        guard let tasks = try? context.fetch(descriptor) else { return [] }
        let pets = (try? context.fetch(FetchDescriptor<PetsPet>())) ?? []
        let petsByID = Dictionary(pets.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })

        return tasks.compactMap { task in
            guard let start = task.desiredDate, start >= from, start < to else { return nil }
            let end = start.addingTimeInterval(Double(max(30, task.durationMinutes)) * 60)
            guard end > interval.start else { return nil }
            guard let pet = petsByID[task.petID], pet.deletedAt == nil else { return nil }
            var open: (@MainActor () -> AnyView)?
            open = { AnyView(PetsTaskFormView(pet: pet, task: task)) }
            return CalendarItem(
                id: "pets.task.\(task.syncID.uuidString)",
                title: "\(task.isDone ? "✓ " : "")\(task.title.isEmpty ? "Дело" : task.title) · \(pet.displayName)",
                start: start,
                end: end,
                member: .owner,
                color: task.isDone ? .green : .pink,
                systemImage: task.isDone ? "checkmark.circle.fill" : "pawprint.fill",
                sharedWith: [.partner],
                emoji: "🐾",
                detail: open,
                move: { newStart in
                    task.desiredDate = newStart
                    task.markChanged()
                    // Уже сделанное: трата переезжает на новый день.
                    if task.isDone, let id = task.entryID,
                       let entry = ((try? context.fetch(FetchDescriptor<PetsEntry>())) ?? []).first(where: { $0.syncID == id }) {
                        entry.date = newStart
                        entry.markChanged()
                        task.doneAt = newStart
                    }
                    try? context.save()
                }
            )
        }
    }
}

// MARK: - Внимание

struct PetsAlert: Identifiable {
    let id: String
    let text: String
    let urgent: Bool
}

enum PetsAlerts {
    /// Что показать сверху в карточке питомца: близкие сроки, возраст, день рождения.
    static func alerts(pet: PetsPet, tasks: [PetsTask]) -> [PetsAlert] {
        var result: [PetsAlert] = []
        let soon = Date.now.addingTimeInterval(2 * 86400)
        let months = PetsAge.months(pet)
        for task in tasks where !task.isDone {
            let name = task.title.isEmpty ? "Дело" : task.title
            if let due = task.desiredDate, due < soon {
                let overdue = due < .now
                result.append(PetsAlert(
                    id: "d.\(task.syncID)",
                    text: overdue ? "\(name): срок прошёл"
                        : "\(name): \(due.formatted(date: .abbreviated, time: .shortened))",
                    urgent: overdue))
            }
            if task.desiredAgeMonths > 0, let months, months >= task.desiredAgeMonths - 1 {
                let reached = months >= task.desiredAgeMonths
                result.append(PetsAlert(
                    id: "a.\(task.syncID)",
                    text: reached ? "\(name): возраст \(PetsAge.text(months: task.desiredAgeMonths)) достигнут"
                        : "\(name): скоро \(PetsAge.text(months: task.desiredAgeMonths))",
                    urgent: reached))
            }
        }
        if let birthday = PetsAge.nextBirthday(pet) {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: birthday).day ?? 99
            if days <= 7 {
                result.append(PetsAlert(
                    id: "bd", text: days == 0 ? "Сегодня день рождения! 🎂" : "День рождения через \(days) дн. 🎂",
                    urgent: false))
            }
        }
        return result
    }
}

// MARK: - Уведомления голосами котов

enum PetsNotifications {
    private static let prefix = "pets.reminder."
    private static let limit = 16

    private struct Plan: Sendable {
        let id: String
        let title: String
        let body: String
        let fireDate: Date
    }

    @MainActor
    static func reschedule(pets: [PetsPet], tasks: [PetsTask]) {
        let calendar = Calendar.current
        let now = Date.now
        var plans: [Plan] = []

        func add(_ id: String, cat: Cat, body: String, on day: Date, hour: Int) {
            guard let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now else { return }
            plans.append(Plan(id: "\(prefix)\(id)", title: cat.name, body: body, fireDate: fire))
        }

        for pet in pets where pet.deletedAt == nil {
            // Дни рождения: за неделю — Гоша, за два дня — Миса, в сам день — Мироня.
            if let birthday = PetsAge.nextBirthday(pet) {
                let base = calendar.startOfDay(for: birthday)
                let key = "bd.\(pet.syncID.uuidString)"
                if let week = calendar.date(byAdding: .day, value: -7, to: base) {
                    add("\(key).7", cat: .gosha, body: "Не забудь: через неделю день рождения у \(pet.displayName)!", on: week, hour: 11)
                }
                if let two = calendar.date(byAdding: .day, value: -2, to: base) {
                    add("\(key).2", cat: .misa, body: "Через два дня у \(pet.displayName) день рождения. Пора готовить вкусняшку!", on: two, hour: 11)
                }
                add("\(key).0", cat: .miron, body: "Сегодня день рождения у \(pet.displayName)! Мур-мур 🎂", on: base, hour: 10)
            }
        }

        let petsByID = Dictionary(pets.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })
        let voices: [Cat] = [.chloe, .misa, .gosha, .miron]
        for task in tasks where task.deletedAt == nil && !task.isDone {
            guard let pet = petsByID[task.petID], pet.deletedAt == nil else { continue }
            let name = task.title.isEmpty ? "дело" : task.title
            let price = task.price > 0 ? " Бюджет: \(CarFormat.money(task.price))." : ""
            if let due = task.desiredDate {
                let base = calendar.startOfDay(for: due)
                let cat = voices[abs(task.syncID.hashValue) % voices.count]
                if let week = calendar.date(byAdding: .day, value: -7, to: base) {
                    add("t.\(task.syncID).7", cat: cat, body: "\(pet.displayName): через неделю «\(name)».\(price)", on: week, hour: 11)
                }
                if let day = calendar.date(byAdding: .day, value: -1, to: base) {
                    add("t.\(task.syncID).1", cat: cat, body: "\(pet.displayName): завтра «\(name)».\(price)", on: day, hour: 11)
                }
                if due > now {
                    plans.append(Plan(id: "\(prefix)t.\(task.syncID).0", title: cat.name,
                                      body: "\(pet.displayName): сегодня «\(name)».\(price)", fireDate: due))
                }
            }
            if task.desiredAgeMonths > 0, let target = PetsAge.date(for: task.desiredAgeMonths, pet: pet) {
                let base = calendar.startOfDay(for: target)
                if let week = calendar.date(byAdding: .day, value: -7, to: base) {
                    add("t.\(task.syncID).a7", cat: .chloe, body: "\(pet.displayName): через неделю возраст для «\(name)».", on: week, hour: 11)
                }
                add("t.\(task.syncID).a0", cat: .misa, body: "\(pet.displayName) уже достаточно взрослый: «\(name)».", on: base, hour: 11)
            }
        }

        plans.sort { $0.fireDate < $1.fireDate }
        let selected = Array(plans.prefix(limit))

        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard !selected.isEmpty else { return }
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            for plan in selected {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
            }
        }
    }
}

// MARK: - Статистика

/// Траты на питомцев в статистике: общие у обоих, по каждому питомцу отдельно.
/// Данные читаются один раз в обычные значения (без @Query на экране).
struct StatisticsPetsSpend: View {
    let period: StatisticsPeriod

    private struct Line: Identifiable {
        let id: UUID
        let title: String
        let caption: String
        let amount: Double
        let petName: String
    }

    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @State private var lines: [Line] = []

    var body: some View {
        let total = lines.reduce(0) { $0 + $1.amount }
        let names = Array(Set(lines.map(\.petName))).sorted()
        StatisticsLine(title: "🐾 Траты на питомцев", value: PlannerPricing.format(total)) {
            if lines.isEmpty {
                Text("За период трат на питомцев нет").foregroundStyle(.secondary)
            }
            ForEach(names, id: \.self) { name in
                let list = lines.filter { $0.petName == name }
                StatisticsLine(title: name, value: PlannerPricing.format(list.reduce(0) { $0 + $1.amount })) {
                    ForEach(list) { line in
                        StatisticsDetailRow(title: line.title, caption: line.caption,
                                            value: "−" + PlannerPricing.format(line.amount))
                    }
                }
            }
        }
        .task(id: reloadKey) { load() }
    }

    private var reloadKey: String {
        "\(period.interval.start.timeIntervalSince1970)-\(period.interval.end.timeIntervalSince1970)-\(sync.dataVersion)"
    }

    private func load() {
        let pets = (try? context.fetch(FetchDescriptor<PetsPet>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let names = Dictionary(pets.map { ($0.syncID, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let entries = (try? context.fetch(FetchDescriptor<PetsEntry>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\PetsEntry.date, order: .reverse)]))) ?? []
        lines = entries.compactMap { entry in
            guard entry.amount > 0, period.contains(entry.date), let name = names[entry.petID] else { return nil }
            return Line(id: entry.syncID, title: entry.note.isEmpty ? entry.category : entry.note,
                        caption: "\(StatisticsFormat.day(entry.date)) · \(entry.category)",
                        amount: entry.amount, petName: name)
        }
    }
}
