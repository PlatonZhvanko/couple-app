import SwiftData
import SwiftUI

/// Главный экран раздела «Клиенты»: расписание, список клиентов и настройки групп.
/// У каждого из пары свои клиенты и записи.
struct ClientsRootView: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        ClientsHomeView(member: account.current)
    }
}

/// Что открыть в отдельном окне.
enum ClientsSheet: Identifiable {
    case newAppointment(clientID: UUID?)
    case editAppointment(ClientsAppointment)
    case newClient
    case editClient(ClientsClient)

    var id: String {
        switch self {
        case .newAppointment(let clientID): "new-appointment-\(clientID?.uuidString ?? "")"
        case .editAppointment(let item): "appointment-\(item.syncID)"
        case .newClient: "new-client"
        case .editClient(let client): "client-\(client.syncID)"
        }
    }
}

/// Показывает окно `ClientsSheet` с нужной формой.
struct ClientsSheetView: View {
    let sheet: ClientsSheet
    let member: CoupleMember

    var body: some View {
        switch sheet {
        case .newAppointment(let clientID):
            ClientsAppointmentEditor(member: member, appointment: nil, presetClientID: clientID)
        case .editAppointment(let item):
            ClientsAppointmentEditor(member: member, appointment: item, presetClientID: item.clientID)
        case .newClient:
            ClientsClientEditor(member: member, client: nil)
        case .editClient(let client):
            ClientsClientEditor(member: member, client: client)
        }
    }
}

struct ClientsHomeView: View {
    enum Page: String, CaseIterable, Identifiable {
        case schedule = "📅 Расписание"
        case clients = "🙋 Клиенты"
        case groups = "👧👦 Группы"
        case subscriptions = "📜 Абонементы"
        var id: String { rawValue }
    }

    let member: CoupleMember

    @Environment(SyncCoordinator.self) private var sync
    @Query private var appointments: [ClientsAppointment]
    @Query private var clients: [ClientsClient]
    @AppStorage("clients.selectedTab") private var tab: Page = .schedule
    @State private var sheet: ClientsSheet?

    init(member: CoupleMember) {
        self.member = member
        let raw = member.rawValue
        _appointments = Query(
            filter: #Predicate<ClientsAppointment> { $0.deletedAt == nil && $0.member == raw },
            sort: \ClientsAppointment.start
        )
        _clients = Query(
            filter: #Predicate<ClientsClient> { $0.deletedAt == nil && $0.member == raw },
            sort: \ClientsClient.name
        )
    }

    private var clientsByID: [UUID: ClientsClient] {
        Dictionary(clients.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Меняется при любом изменении записей: тогда пересобираем напоминания.
    private var reminderKey: String {
        appointments.map { "\($0.syncID)\($0.updatedAt.timeIntervalSince1970)" }.joined()
            + clients.map { "\($0.syncID)\($0.name)" }.joined()
    }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .schedule:
                    ClientsScheduleView(appointments: appointments, clients: clientsByID) {
                        sheet = .newAppointment(clientID: nil)
                    }
                case .clients:
                    ClientsListView(clients: clients, appointments: appointments) {
                        sheet = .newClient
                    }
                case .groups:
                    PlannerGroupSettingsView()
                case .subscriptions:
                    PlannerSubscriptionSettingsView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Раздел", selection: $tab) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Клиенты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Новая запись", systemImage: "calendar.badge.plus") {
                            sheet = .newAppointment(clientID: nil)
                        }
                        Button("Новый клиент", systemImage: "person.badge.plus") {
                            sheet = .newClient
                        }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        sheet = tab == .clients ? .newClient : .newAppointment(clientID: nil)
                    }
                }
            }
            .navigationDestination(for: ClientsAppointment.self) { item in
                ClientsAppointmentDetailView(appointment: item, member: member)
            }
            .navigationDestination(for: ClientsClient.self) { client in
                ClientsClientDetailView(client: client, member: member)
            }
            .sheet(item: $sheet) { sheet in
                ClientsSheetView(sheet: sheet, member: member)
            }
            .refreshable { await sync.syncNow() }
            .task(id: reminderKey) {
                await ClientsReminders.refresh(
                    appointments: appointments,
                    clientNames: clientsByID.mapValues(\.name)
                )
            }
        }
    }
}

/// Строка записи в списках.
struct ClientsAppointmentRow: View {
    let appointment: ClientsAppointment
    let clientName: String
    var showDate = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.start.formatted(date: .omitted, time: .shortened))
                    .font(.headline.monospacedDigit())
                Text(ClientsFormat.duration(appointment.durationMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(clientName)
                    .font(.body.weight(.medium))
                    .strikethrough(appointment.status == .cancelled)
                if showDate {
                    Text(appointment.start.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !appointment.service.isEmpty {
                    Text(appointment.service)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if appointment.price > 0 {
                    Text(ClientsFormat.money(appointment.price))
                        .font(.subheadline.monospacedDigit())
                }
                if appointment.needsOutcome {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                } else if appointment.status != .planned {
                    Image(systemName: appointment.status.systemImage)
                        .foregroundStyle(appointment.status.color)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(appointment.status == .cancelled ? 0.5 : 1)
    }
}

extension ClientsAppointmentStatus {
    var color: Color {
        switch self {
        case .planned: .blue
        case .done: .green
        case .noShow: .red
        case .cancelled: .secondary
        }
    }
}
