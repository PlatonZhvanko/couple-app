import SwiftUI

/// Итоги за месяц: заработок, визиты, неявки, популярные услуги и клиенты.
struct ClientsSummaryView: View {
    let appointments: [ClientsAppointment]
    let clients: [UUID: ClientsClient]

    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    private struct Line: Identifiable {
        let title: String
        let count: Int
        let sum: Double
        var id: String { title }
    }

    private var monthItems: [ClientsAppointment] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return appointments.filter { interval.contains($0.start) }
    }

    private func lines(_ items: [ClientsAppointment], key: (ClientsAppointment) -> String) -> [Line] {
        Dictionary(grouping: items, by: key)
            .map { Line(title: $0.key, count: $0.value.count, sum: $0.value.reduce(0) { $0 + $1.price }) }
            .sorted { $0.sum == $1.sum ? $0.count > $1.count : $0.sum > $1.sum }
            .prefix(5)
            .map { $0 }
    }

    private func shiftMonth(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    var body: some View {
        let items = monthItems
        let done = items.filter { $0.status == .done }
        let planned = items.filter { $0.status == .planned }
        let earned = done.reduce(0) { $0 + $1.price }
        let expected = planned.reduce(0) { $0 + $1.price }

        List {
            Section {
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                        .font(.headline)
                    Spacer()
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Заработано")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ClientsFormat.money(earned))
                        .font(.largeTitle.bold().monospacedDigit())
                    if expected > 0 {
                        Text("ещё ожидается \(ClientsFormat.money(expected))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Визитов", value: "\(done.count)")
                LabeledContent("Запланировано", value: "\(planned.count)")
                LabeledContent("Не пришли", value: "\(items.filter { $0.status == .noShow }.count)")
                LabeledContent("Отменили", value: "\(items.filter { $0.status == .cancelled }.count)")
                if !done.isEmpty {
                    LabeledContent("Средний чек", value: ClientsFormat.money(earned / Double(done.count)))
                }
            }

            let services = lines(done) { $0.service.isEmpty ? "Без названия" : $0.service }
            if !services.isEmpty {
                Section("Услуги") {
                    ForEach(services) { line in
                        LabeledContent("\(line.title) · \(line.count)", value: ClientsFormat.money(line.sum))
                    }
                }
            }

            let topClients = lines(done) { item in item.clientID.flatMap { clients[$0]?.name } ?? "Без клиента" }
            if !topClients.isEmpty {
                Section("Лучшие клиенты") {
                    ForEach(topClients) { line in
                        LabeledContent("\(line.title) · \(line.count)", value: ClientsFormat.money(line.sum))
                    }
                }
            }
        }
    }
}
