import SwiftData
import SwiftUI

/// Записи клиентов для календаря «Планера» (только просмотр).
enum ClientsCalendar {
    @MainActor
    static func items(context: ModelContext, interval: DateInterval) -> [CalendarItem] {
        // Запись не длиннее суток, поэтому берём начало с запасом в день.
        let from = interval.start.addingTimeInterval(-86_400)
        let to = interval.end
        let cancelled = ClientsAppointmentStatus.cancelled.rawValue
        let descriptor = FetchDescriptor<ClientsAppointment>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.statusRaw != cancelled && $0.start >= from && $0.start < to
            },
            sortBy: [SortDescriptor(\.start)]
        )
        guard let appointments = try? context.fetch(descriptor) else { return [] }

        let clients = (try? context.fetch(FetchDescriptor<ClientsClient>())) ?? []
        let names = Dictionary(clients.map { ($0.syncID, $0.name) }, uniquingKeysWith: { first, _ in first })

        return appointments
            .filter { $0.end > interval.start }
            .map { item in
                let name = item.clientID.flatMap { names[$0] } ?? "Клиент"
                let calendarItem = CalendarItem(
                    id: "clients.appointment.\(item.syncID.uuidString)",
                    title: item.service.isEmpty ? name : "\(name) · \(item.service)",
                    start: item.start,
                    end: item.end,
                    member: CoupleMember(rawValue: item.member),
                    color: .gray,
                    systemImage: "person.crop.circle.badge.clock"
                )
                return calendarItem
            }
    }
}
