import Foundation
import SwiftData

/// Единственное место раздела «Планер», которое обращается к базе клиентов
/// из раздела «Клиенты». Так тренировки в календаре используют те же карточки клиентов.
enum PlannerClientDirectory {
    struct Entry: Identifiable, Hashable {
        let id: UUID
        let name: String
        /// Название в нижнем регистре: поиск идёт по нему, без медленного сравнения на каждый символ.
        let lower: String

        init(id: UUID, name: String) {
            self.id = id
            self.name = name
            self.lower = name.lowercased()
        }

        func matches(_ lowercasedQuery: String) -> Bool { lower.contains(lowercasedQuery) }
    }

    /// Все клиенты по алфавиту.
    @MainActor
    static func all(_ context: ModelContext) -> [Entry] {
        let descriptor = FetchDescriptor<ClientsClient>(predicate: #Predicate { $0.deletedAt == nil })
        let clients = (try? context.fetch(descriptor)) ?? []
        return clients
            .map { Entry(id: $0.syncID, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Телефон клиента (пусто, если не указан).
    @MainActor
    static func phone(of id: UUID, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<ClientsClient>(predicate: #Predicate { $0.syncID == id })
        return (try? context.fetch(descriptor))?.first?.phone ?? ""
    }

    /// Добавить нового клиента в общую базу.
    @MainActor
    static func add(name: String, member: CoupleMember, context: ModelContext) -> Entry {
        // Одинаковых карточек не бывает: если такой клиент уже есть, возвращаем его.
        if let found = PlannerClientMerge.existing(name: name, member: member, context: context) {
            return Entry(id: found.syncID, name: found.name)
        }
        let client = ClientsClient(name: name, member: member)
        client.markChanged()
        context.insert(client)
        try? context.save()
        return Entry(id: client.syncID, name: client.name)
    }
}

extension PlannerClientDirectory {
    /// Клиента удалили: его индивидуальные занятия удаляются, а из групп он просто убирается.
    @MainActor
    static func removeEvents(of clientID: UUID, context: ModelContext) {
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        for event in events where event.participantIDs.contains(clientID) {
            let others = event.participantIDs.filter { $0 != clientID }
            if others.isEmpty && event.categoryValue == .personal {
                event.markDeleted()
            } else {
                event.participantIDs = others
                event.markChanged()
            }
        }
        try? context.save()
    }

    /// Сколько было тренировок с клиентом в журнале и сколько он оплатил.
    @MainActor
    static func stats(for clientID: UUID, context: ModelContext) -> (visits: Int, earned: Double) {
        let cal = PlannerCalendar.calendar
        let today = cal.startOfDay(for: .now)
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        var visits = 0
        for event in events where event.participantIDs.contains(clientID) && PlannerPaymentStore.isTraining(event) {
            var day = cal.startOfDay(for: event.start)
            var steps = 0
            // Повторяющиеся записи разворачиваем по дням (не дальше двух лет назад).
            while day <= today && steps < 800 {
                if event.startsOn(day), PlannerCalendar.combine(day: day, time: event.start) <= .now {
                    visits += 1
                }
                if event.repeatValue == .none { break }
                day = PlannerCalendar.addDays(1, to: day)
                steps += 1
            }
        }
        let cash = PlannerPaymentStore.cashPayments(context)
            .filter { $0.clientID == clientID }.reduce(0) { $0 + $1.amount }
        let sold = PlannerPaymentStore.allSubscriptions(context)
            .filter { $0.clientID == clientID }.reduce(0) { $0 + $1.amount }
        let earned = cash + sold
        return (visits, earned)
    }
}
