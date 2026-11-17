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
