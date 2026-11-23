import Foundation
import SwiftData
import SwiftUI

/// Клиент. Принадлежит тому, кто его добавил (`member`).
@Model
final class ClientsClient: SyncableModel {
    struct Payload: Codable {
        var name: String
        var phone: String
        var note: String
        var member: String
        var createdAt: Date
        /// День рождения. Нет в старых записях.
        var birthday: Date?
        /// "iclients" — клиент добавлен автоматически из iClients. Нет в старых записях.
        var source: String?
    }

    static let recordKind = "clients.client"

    var syncID: UUID = UUID()
    var name: String = ""
    var phone: String = ""
    var note: String = ""
    var member: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    var birthday: Date? = nil
    var source: String? = nil
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(name: String, phone: String = "", note: String = "", member: CoupleMember) {
        self.name = name
        self.phone = phone
        self.note = note
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(name: name, phone: phone, note: note, member: member, createdAt: createdAt, birthday: birthday, source: source)
    }

    func apply(_ payload: Payload) {
        name = payload.name
        phone = payload.phone
        note = payload.note
        member = payload.member
        createdAt = payload.createdAt
        birthday = payload.birthday
        source = payload.source
    }

    /// Только цифры телефона (для WhatsApp и звонка).
    var phoneDigits: String { phone.filter(\.isNumber) }
}

/// Статус записи.
enum ClientsAppointmentStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case done
    case noShow
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: "Запланирована"
        case .done: "Пришёл"
        case .noShow: "Не пришёл"
        case .cancelled: "Отменена"
        }
    }

    var systemImage: String {
        switch self {
        case .planned: "clock"
        case .done: "checkmark.circle.fill"
        case .noShow: "person.fill.xmark"
        case .cancelled: "xmark.circle"
        }
    }
}

/// Запись клиента на время.
@Model
final class ClientsAppointment: SyncableModel {
    struct Payload: Codable {
        var clientID: UUID?
        var service: String
        var start: Date
        var durationMinutes: Int
        var price: Double
        var status: String
        var note: String
        var reminderMinutes: Int
        var member: String
        /// Откуда запись: "iclients" — подтянута из журнала iClients. Нет в старых записях.
        var source: String?
    }

    static let recordKind = "clients.appointment"

    var syncID: UUID = UUID()
    /// `syncID` клиента.
    var clientID: UUID? = nil
    var service: String = ""
    var start: Date = Date.now
    var durationMinutes: Int = 60
    var price: Double = 0
    var statusRaw: String = ClientsAppointmentStatus.planned.rawValue
    var note: String = ""
    /// За сколько минут напомнить. 0 — не напоминать.
    var reminderMinutes: Int = 60
    var member: String = CoupleMember.owner.rawValue
    /// "iclients" — запись пришла из журнала iClients автоматически.
    var source: String? = nil
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    var isFromIClients: Bool { source == "iclients" }

    init(member: CoupleMember) {
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(
            clientID: clientID, service: service, start: start,
            durationMinutes: durationMinutes, price: price, status: statusRaw,
            note: note, reminderMinutes: reminderMinutes, member: member, source: source
        )
    }

    func apply(_ payload: Payload) {
        clientID = payload.clientID
        service = payload.service
        start = payload.start
        durationMinutes = payload.durationMinutes
        price = payload.price
        statusRaw = payload.status
        note = payload.note
        reminderMinutes = payload.reminderMinutes
        member = payload.member
        source = payload.source
    }

    var status: ClientsAppointmentStatus {
        get { ClientsAppointmentStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    /// Время прошло, а результат не отмечен.
    var needsOutcome: Bool { status == .planned && end < .now }
}

/// Общие форматы раздела.
enum ClientsFormat {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "RUB" }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) мин"
        case (_, 0): return "\(h) ч"
        default: return "\(h) ч \(m) мин"
        }
    }

    static func time(_ a: ClientsAppointment) -> String {
        "\(a.start.formatted(date: .omitted, time: .shortened))–\(a.end.formatted(date: .omitted, time: .shortened))"
    }

    static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Сегодня" }
        if cal.isDateInTomorrow(date) { return "Завтра" }
        if cal.isDateInYesterday(date) { return "Вчера" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Значок White Lions: жёлтый скруглённый квадрат с тёмной буквой V (рисуется кодом).
struct ClientsIClientsBadge: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(Color(red: 1.0, green: 0.80, blue: 0.10))
            Path { p in
                let w = size, h = size
                p.move(to: CGPoint(x: w * 0.22, y: h * 0.26))
                p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.26))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.55))
                p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.26))
                p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.26))
                p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.78))
                p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.78))
                p.closeSubpath()
            }
            .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("White Lions")
    }
}
