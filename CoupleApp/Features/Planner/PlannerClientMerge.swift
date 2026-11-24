import Foundation
import SwiftData

/// Объединение одинаковых карточек клиентов (одно имя у одного владельца).
/// Записи, участие в группах, оплаты и абонементы переезжают в одну карточку, лишние удаляются.
@MainActor
enum PlannerClientMerge {
    /// Имя для сравнения: без регистра, без лишних пробелов, «ё» = «е».
    static func key(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Ищет живую карточку с таким же именем у этого владельца.
    static func existing(name: String, member: CoupleMember, context: ModelContext) -> ClientsClient? {
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<ClientsClient>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        return all.first { $0.member == member.rawValue && key($0.name) == wanted }
    }

    /// Склеивает все дубли. Возвращает true, если что-то поменялось.
    @discardableResult
    static func mergeAll(_ context: ModelContext) -> Bool {
        let clients = (try? context.fetch(FetchDescriptor<ClientsClient>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        var groups: [String: [ClientsClient]] = [:]
        for client in clients {
            let k = key(client.name)
            if k.isEmpty { continue }
            groups["\(client.member)|\(k)", default: []].append(client)
        }
        let duplicated = groups.values.filter { $0.count > 1 }
        guard !duplicated.isEmpty else { return false }

        let appointments = (try? context.fetch(FetchDescriptor<ClientsAppointment>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let events = (try? context.fetch(FetchDescriptor<PlannerEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let allPayments = (try? context.fetch(FetchDescriptor<PlannerPayment>())) ?? []
        let allSubs = (try? context.fetch(FetchDescriptor<PlannerSubscription>())) ?? []
        var paymentByID = Dictionary(allPayments.map { ($0.syncID, $0) }, uniquingKeysWith: { a, _ in a })
        var subByID = Dictionary(allSubs.map { ($0.syncID, $0) }, uniquingKeysWith: { a, _ in a })

        for group in duplicated {
            // Главная карточка: пришедшая из YClients (её находит синхронизация), иначе самая старая.
            let sorted = group.sorted {
                let a = $0.source == "iclients", b = $1.source == "iclients"
                if a != b { return a }
                return $0.createdAt < $1.createdAt
            }
            let keeper = sorted[0]
            let dups = Array(sorted.dropFirst())
            let dupIDs = Set(dups.map(\.syncID))

            for dup in dups {
                if keeper.phone.isEmpty { keeper.phone = dup.phone }
                if keeper.birthday == nil { keeper.birthday = dup.birthday }
                let note = dup.note.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty, !keeper.note.contains(note) {
                    keeper.note = keeper.note.isEmpty ? note : keeper.note + "\n" + note
                }
            }

            for item in appointments {
                if let id = item.clientID, dupIDs.contains(id) {
                    item.clientID = keeper.syncID
                    item.markChanged()
                }
            }

            for event in events where event.participantIDs.contains(where: { dupIDs.contains($0) }) {
                var seen = Set<UUID>()
                var result: [UUID] = []
                for id in event.participantIDs {
                    let mapped = dupIDs.contains(id) ? keeper.syncID : id
                    if seen.insert(mapped).inserted { result.append(mapped) }
                }
                event.participantIDs = result
                event.markChanged()
            }

            for old in allPayments where old.deletedAt == nil && dupIDs.contains(old.clientID) {
                let newID = PlannerPayment.makeID(eventID: old.eventID, day: old.day, clientID: keeper.syncID)
                if let target = paymentByID[newID] {
                    if target.deletedAt != nil {
                        target.deletedAt = nil
                        target.method = old.method
                        target.amount = old.amount
                        target.markChanged()
                    } else if target.methodValue == PlannerPayMethod.none, old.methodValue != PlannerPayMethod.none {
                        target.method = old.method
                        target.amount = old.amount
                        target.markChanged()
                    }
                } else {
                    let row = PlannerPayment(eventID: old.eventID, day: old.day, clientID: keeper.syncID, method: old.methodValue, amount: old.amount)
                    row.markChanged()
                    context.insert(row)
                    paymentByID[newID] = row
                }
                old.markDeleted()
            }

            for old in allSubs where old.deletedAt == nil && dupIDs.contains(old.clientID) {
                let newID = PlannerSubscription.makeID(clientID: keeper.syncID, month: old.month)
                if let target = subByID[newID] {
                    if target.deletedAt != nil {
                        target.deletedAt = nil
                        target.amount = old.amount
                        target.kindName = old.kindName
                        target.soldAt = old.soldAt
                        target.expiresAt = old.expiresAt
                        target.charge = old.charge
                    } else {
                        target.amount += old.amount
                        target.expiresAt = max(target.expiresAt, old.expiresAt)
                    }
                    target.markChanged()
                } else {
                    let row = PlannerSubscription(clientID: keeper.syncID, month: old.month, amount: old.amount)
                    row.kindName = old.kindName
                    row.soldAt = old.soldAt
                    row.expiresAt = old.expiresAt
                    row.charge = old.charge
                    row.markChanged()
                    context.insert(row)
                    subByID[newID] = row
                }
                old.markDeleted()
            }

            keeper.markChanged()
            for dup in dups { dup.markDeleted() }
        }
        try? context.save()
        return true
    }
}
