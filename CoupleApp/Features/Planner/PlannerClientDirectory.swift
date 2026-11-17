import Foundation
import SwiftData

/// Единственное место раздела «Планер», которое обращается к базе клиентов
/// из раздела «Клиенты». Так тренировки в календаре используют те же карточки клиентов.
enum PlannerClientDirectory {
    struct Entry: Identifiable, Hashable {
        let id: UUID
        let name: String
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

    /// Добавить нового клиента в общую базу.
    @MainActor
    static func add(name: String, member: CoupleMember, context: ModelContext) -> Entry {
        let client = ClientsClient(name: name, member: member)
        client.markChanged()
        context.insert(client)
        try? context.save()
        return Entry(id: client.syncID, name: client.name)
    }
}

extension PlannerClientDirectory {
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
