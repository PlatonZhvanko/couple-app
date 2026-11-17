import SwiftUI

/// Клиенты: кто с абонементом, кто без, кому пора продлевать.
struct StatisticsClientsView: View {
    let snapshot: StatisticsSnapshot
    let period: StatisticsPeriod

    @State private var query = ""

    private var cal: Calendar { PlannerCalendar.calendar }

    private struct Row: Identifiable {
        let id: UUID
        let name: String
        let visits: Int
        let paid: Double
        let hasSubscription: Bool
        let note: String?
    }

    private var rows: [Row] {
        let inPeriod = snapshot.visits.filter { period.contains($0.day) && $0.start <= .now }
        let ids = Set(inPeriod.map(\.clientID)).union(snapshot.subscriptions.map(\.clientID))
        let monthStart = PlannerCalendar.startOfMonth(.now)
        let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let daysLeft = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: nextMonth).day ?? 30

        return ids.map { id in
            let mine = inPeriod.filter { $0.clientID == id }
            let subs = snapshot.subscriptions.filter { $0.clientID == id }
            let current = subs.first { cal.isDate($0.month, equalTo: .now, toGranularity: .month) }
            let next = subs.first { cal.isDate($0.month, equalTo: nextMonth, toGranularity: .month) }
            let cash = snapshot.cashPayments.filter { $0.clientID == id && period.contains($0.day) }.reduce(0) { $0 + $1.amount }
            let bought = subs.filter { period.contains($0.soldAt) }.reduce(0) { $0 + $1.amount }
            var note: String?
            if current != nil && next == nil && daysLeft <= 7 {
                note = "Пора продлевать: абонемент заканчивается через \(daysLeft) дн."
            } else if let current, snapshot.left(current) <= PlannerPricing.subscriptionCharge {
                note = "На абонементе почти не осталось денег"
            }
            return Row(id: id, name: snapshot.name(id), visits: mine.count, paid: cash + bought,
                       hasSubscription: current != nil, note: note)
        }
        .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let all = rows
        List {
            Section {
                TextField("Поиск клиента", text: $query).autocorrectionDisabled()
            }
            let renew = all.filter { $0.note != nil }
            if !renew.isEmpty {
                Section("Скоро продлевать") {
                    ForEach(renew) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            Text(row.note ?? "").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            Section("Купили абонемент в этом месяце") {
                let list = all.filter(\.hasSubscription)
                if list.isEmpty { Text("Пока никто").foregroundStyle(.secondary) }
                ForEach(list) { clientRow($0) }
            }
            Section("Ходят без абонемента") {
                let list = all.filter { !$0.hasSubscription && $0.visits > 0 }
                if list.isEmpty { Text("Таких нет").foregroundStyle(.secondary) }
                ForEach(list) { clientRow($0) }
            }
        }
    }

    private func clientRow(_ row: Row) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(row.name)
                Text("Занятий за период: \(row.visits)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(PlannerPricing.format(row.paid)).foregroundStyle(.secondary)
        }
    }
}
