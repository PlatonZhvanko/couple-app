import SwiftUI

/// Расписание: что отметить, ближайшие записи по дням и прошедшие.
struct ClientsScheduleView: View {
    /// Записи, отсортированные по времени.
    let appointments: [ClientsAppointment]
    let clients: [UUID: ClientsClient]
    let onAdd: () -> Void

    @State private var showPast = false

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [ClientsAppointment]
        var id: Date { day }
    }

    private var toMark: [ClientsAppointment] {
        appointments.filter(\.needsOutcome)
    }

    private var days: [DayGroup] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        let items: [ClientsAppointment]
        if showPast {
            items = appointments.filter { $0.start < .now }.reversed()
        } else {
            items = appointments.filter { $0.start >= startOfToday && !$0.needsOutcome }
        }
        var groups: [DayGroup] = []
        for item in items {
            let day = cal.startOfDay(for: item.start)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, items: last.items + [item])
            } else {
                groups.append(DayGroup(day: day, items: [item]))
            }
        }
        return groups
    }

    private func name(_ item: ClientsAppointment) -> String {
        item.clientID.flatMap { clients[$0]?.name } ?? "Без клиента"
    }

    var body: some View {
        List {
            Section {
                Picker("Показать", selection: $showPast) {
                    Text("Ближайшие").tag(false)
                    Text("Прошедшие").tag(true)
                }
                .pickerStyle(.menu)
            }

            if !showPast && !toMark.isEmpty {
                Section {
                    ForEach(toMark) { item in
                        NavigationLink(value: item) {
                            ClientsAppointmentRow(appointment: item, clientName: name(item), showDate: true)
                        }
                    }
                } header: {
                    Label("Отметьте, пришёл ли клиент", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
            }

            if days.isEmpty && (showPast || toMark.isEmpty) {
                ContentUnavailableView {
                    Label(showPast ? "Пока нет прошедших записей" : "Записей нет",
                          systemImage: "calendar")
                } description: {
                    Text(showPast ? "Здесь появятся записи, время которых прошло." : "Добавьте запись клиента на время.")
                } actions: {
                    if !showPast {
                        Button("Новая запись", action: onAdd)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(days) { group in
                Section {
                    ForEach(group.items) { item in
                        NavigationLink(value: item) {
                            ClientsAppointmentRow(appointment: item, clientName: name(item))
                        }
                    }
                } header: {
                    HStack {
                        Text(ClientsFormat.dayTitle(group.day))
                        Spacer()
                        let total = group.items.filter { $0.status != .cancelled }.reduce(0) { $0 + $1.price }
                        if total > 0 { Text(ClientsFormat.money(total)) }
                    }
                }
            }
        }
    }
}
