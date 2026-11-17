import SwiftUI

/// Строка рейтинга: услуга или клиент, число визитов и сумма.
struct ClientsSummaryLine: Identifiable {
    let title: String
    let count: Int
    let sum: Double
    var id: String { title }
}

/// Посчитанные итоги месяца (простые типы, чтобы экран собирался быстро).
struct ClientsMonthStats {
    var earned: Double = 0
    var expected: Double = 0
    var visits: Int = 0
    var planned: Int = 0
    var noShows: Int = 0
    var cancelled: Int = 0
    var services: [ClientsSummaryLine] = []
    var topClients: [ClientsSummaryLine] = []

    var averageCheck: Double { visits > 0 ? earned / Double(visits) : 0 }

    init() {}

    init(month: Date, appointments: [ClientsAppointment], clients: [UUID: ClientsClient]) {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return }
        var serviceTotals: [String: (count: Int, sum: Double)] = [:]
        var clientTotals: [String: (count: Int, sum: Double)] = [:]

        for item in appointments where interval.contains(item.start) {
            switch item.status {
            case .done:
                visits += 1
                earned += item.price
                let service: String = item.service.isEmpty ? "Без названия" : item.service
                let current: (count: Int, sum: Double) = serviceTotals[service] ?? (0, 0)
                serviceTotals[service] = (current.count + 1, current.sum + item.price)

                var clientName: String = "Без клиента"
                if let id = item.clientID, let client = clients[id] { clientName = client.name }
                let currentClient: (count: Int, sum: Double) = clientTotals[clientName] ?? (0, 0)
                clientTotals[clientName] = (currentClient.count + 1, currentClient.sum + item.price)
            case .planned:
                planned += 1
                expected += item.price
            case .noShow:
                noShows += 1
            case .cancelled:
                cancelled += 1
            }
        }
        services = Self.top(serviceTotals)
        topClients = Self.top(clientTotals)
    }

    private static func top(_ totals: [String: (count: Int, sum: Double)]) -> [ClientsSummaryLine] {
        var lines: [ClientsSummaryLine] = []
        for (title, value) in totals {
            lines.append(ClientsSummaryLine(title: title, count: value.count, sum: value.sum))
        }
        lines.sort { (a: ClientsSummaryLine, b: ClientsSummaryLine) -> Bool in
            if a.sum != b.sum { return a.sum > b.sum }
            return a.count > b.count
        }
        return Array(lines.prefix(5))
    }
}

/// Итоги за месяц: заработок, визиты, неявки, популярные услуги и клиенты.
struct ClientsSummaryView: View {
    let appointments: [ClientsAppointment]
    let clients: [UUID: ClientsClient]

    @State private var month: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    private var stats: ClientsMonthStats {
        ClientsMonthStats(month: month, appointments: appointments, clients: clients)
    }

    private var monthTitle: String {
        month.formatted(.dateTime.month(.wide).year()).capitalized
    }

    private func shiftMonth(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    var body: some View {
        let stats: ClientsMonthStats = self.stats
        List {
            monthSection
            totalsSection(stats)
            ClientsSummaryLinesSection(title: "Услуги", lines: stats.services)
            ClientsSummaryLinesSection(title: "Лучшие клиенты", lines: stats.topClients)
        }
    }

    private var monthSection: some View {
        Section {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
        }
    }

    private func totalsSection(_ stats: ClientsMonthStats) -> some View {
        Section {
            ClientsEarnedHeader(earned: stats.earned, expected: stats.expected)
            LabeledContent("Визитов", value: String(stats.visits))
            LabeledContent("Запланировано", value: String(stats.planned))
            LabeledContent("Не пришли", value: String(stats.noShows))
            LabeledContent("Отменили", value: String(stats.cancelled))
            if stats.visits > 0 {
                LabeledContent("Средний чек", value: ClientsFormat.money(stats.averageCheck))
            }
        }
    }
}

/// Крупная сумма заработка за месяц.
private struct ClientsEarnedHeader: View {
    let earned: Double
    let expected: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Заработано")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(ClientsFormat.money(earned))
                .font(.largeTitle.bold())
            if expected > 0 {
                Text("ещё ожидается " + ClientsFormat.money(expected))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Список «название · визиты — сумма».
private struct ClientsSummaryLinesSection: View {
    let title: String
    let lines: [ClientsSummaryLine]

    var body: some View {
        if !lines.isEmpty {
            Section(title) {
                ForEach(lines) { line in
                    LabeledContent(line.title + " · " + String(line.count),
                                   value: ClientsFormat.money(line.sum))
                }
            }
        }
    }
}
