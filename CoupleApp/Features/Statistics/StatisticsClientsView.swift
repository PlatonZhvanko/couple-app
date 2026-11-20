import SwiftUI

/// Клиенты: кто с абонементом, кто без, кому пора продлевать. Каждый клиент раскрывается.
struct StatisticsClientsView: View {
    let snapshot: StatisticsSnapshot
    let period: StatisticsPeriod

    @State private var query = ""

    private var cal: Calendar { PlannerCalendar.calendar }

    private struct Row: Identifiable {
        let id: UUID
        let name: String
        let visits: [StatisticsVisit]
        let subs: [PlannerSubscription]
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
            let mine = inPeriod.filter { $0.clientID == id }.sorted { $0.start > $1.start }
            let subs = snapshot.subscriptions.filter { $0.clientID == id }.sorted { $0.soldAt > $1.soldAt }
            let current = subs.first { cal.isDate($0.month, equalTo: .now, toGranularity: .month) && !$0.isExpired }
            let next = subs.first { cal.isDate($0.month, equalTo: nextMonth, toGranularity: .month) }
            let cash = snapshot.cashPayments.filter { $0.clientID == id && period.contains($0.day) }.reduce(0) { $0 + $1.amount }
            let bought = subs.filter { period.contains($0.soldAt) }.reduce(0) { $0 + $1.amount }
            var note: String?
            if current != nil && next == nil && daysLeft <= 7 {
                note = "Пора продлевать: абонемент заканчивается через \(daysLeft) дн."
            } else if let current, snapshot.left(current) <= current.charge {
                note = "На абонементе почти не осталось денег"
            }
            return Row(id: id, name: snapshot.name(id), visits: mine, subs: subs, paid: cash + bought,
                       hasSubscription: current != nil, note: note)
        }
        .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let all = rows
        List {
            Section {
                TextField("🔍 Поиск клиента", text: $query).autocorrectionDisabled()
            }
            let renew = all.filter { $0.note != nil }
            if !renew.isEmpty {
                Section("⏰ Скоро продлевать") {
                    ForEach(renew) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            Text(row.note ?? "").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            Section("📜 С абонементом") {
                let list = all.filter(\.hasSubscription)
                if list.isEmpty { Text("Пока никто").foregroundStyle(.secondary) }
                ForEach(list) { clientRow($0) }
            }
            Section("🎾 Ходят без абонемента") {
                // Только те, кто ходит в группы; кто занимается лично, без абонемента — не считаются.
                let list = all.filter { !$0.hasSubscription && $0.visits.contains { $0.category == .group } }
                if list.isEmpty { Text("Таких нет").foregroundStyle(.secondary) }
                ForEach(list) { clientRow($0) }
            }
        }
    }

    private func clientRow(_ row: Row) -> some View {
        StatisticsLine(title: row.name, value: PlannerPricing.format(row.paid)) {
            StatisticsDetailRow(title: "Занятий за период", value: "\(row.visits.count)")
            ForEach(row.visits) { visit in
                StatisticsDetailRow(
                    title: visit.eventTitle,
                    caption: "\(StatisticsFormat.day(visit.start)) · \(visit.method.title)",
                    value: PlannerPricing.format(visit.amount)
                )
            }
            ForEach(row.subs) { sub in
                StatisticsDetailRow(
                    title: "📜 \(sub.kindName.isEmpty ? "Абонемент" : sub.kindName)",
                    caption: "продан \(StatisticsFormat.day(sub.soldAt)), до \(StatisticsFormat.day(sub.expiresAt)), остаток \(PlannerPricing.format(snapshot.left(sub)))",
                    value: PlannerPricing.format(sub.amount)
                )
            }
        }
    }
}
