import Foundation
import SwiftData
import SwiftUI

// MARK: - Машина

/// Машина. Записи журнала и напоминания ссылаются на неё через `carID` = `syncID`.
@Model
final class CarVehicle: SyncableModel {
    struct Payload: Codable {
        var name: String
        var plate: String
        var vin: String
        var year: Int
        var startOdometer: Int
        var createdAt: Date
    }

    static let recordKind = "car.vehicle"

    var syncID: UUID = UUID()
    var name: String = ""
    var plate: String = ""
    var vin: String = ""
    /// 0 — не указан.
    var year: Int = 0
    /// Пробег на момент добавления машины в приложение.
    var startOdometer: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(name: String) {
        self.name = name
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(name: name, plate: plate, vin: vin, year: year, startOdometer: startOdometer, createdAt: createdAt)
    }

    func apply(_ payload: Payload) {
        name = payload.name
        plate = payload.plate
        vin = payload.vin
        year = payload.year
        startOdometer = payload.startOdometer
        createdAt = payload.createdAt
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Машина" : name
    }
}

// MARK: - Журнал расходов

enum CarEntryCategory: String, CaseIterable, Identifiable {
    case fuel, service, repair, tires, wash, parking, fine, insurance, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuel: "Заправка"
        case .service: "ТО"
        case .repair: "Ремонт"
        case .tires: "Шины"
        case .wash: "Мойка"
        case .parking: "Парковка"
        case .fine: "Штраф"
        case .insurance: "Страховка"
        case .other: "Другое"
        }
    }

    var systemImage: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .service: "wrench.and.screwdriver.fill"
        case .repair: "hammer.fill"
        case .tires: "circle.circle.fill"
        case .wash: "drop.fill"
        case .parking: "parkingsign.circle.fill"
        case .fine: "exclamationmark.triangle.fill"
        case .insurance: "shield.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fuel: .orange
        case .service: .blue
        case .repair: .indigo
        case .tires: .gray
        case .wash: .cyan
        case .parking: .teal
        case .fine: .red
        case .insurance: .green
        case .other: .secondary
        }
    }
}

/// Одна трата по машине. Заправка — тоже трата, с литрами.
@Model
final class CarEntry: SyncableModel {
    struct Payload: Codable {
        var carID: UUID
        var category: String
        var date: Date
        var amount: Double
        var odometer: Int
        var liters: Double
        var isFullTank: Bool
        var note: String
        var member: String
        var createdAt: Date
    }

    static let recordKind = "car.entry"

    var syncID: UUID = UUID()
    var carID: UUID = UUID()
    var categoryRaw: String = CarEntryCategory.other.rawValue
    var date: Date = Date.now
    /// Сумма в рублях.
    var amount: Double = 0
    /// Пробег на момент записи. 0 — не указан.
    var odometer: Int = 0
    /// Только для заправок.
    var liters: Double = 0
    var isFullTank: Bool = true
    var note: String = ""
    /// Кто добавил: `CoupleMember.rawValue`.
    var member: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(carID: UUID, category: CarEntryCategory, member: CoupleMember) {
        self.carID = carID
        self.categoryRaw = category.rawValue
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(
            carID: carID, category: categoryRaw, date: date, amount: amount, odometer: odometer,
            liters: liters, isFullTank: isFullTank, note: note, member: member, createdAt: createdAt
        )
    }

    func apply(_ payload: Payload) {
        carID = payload.carID
        categoryRaw = payload.category
        date = payload.date
        amount = payload.amount
        odometer = payload.odometer
        liters = payload.liters
        isFullTank = payload.isFullTank
        note = payload.note
        member = payload.member
        createdAt = payload.createdAt
    }

    var category: CarEntryCategory {
        get { CarEntryCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var memberValue: CoupleMember { CoupleMember(rawValue: member) ?? .owner }
}

// MARK: - Напоминания

enum CarReminderKind: String, CaseIterable, Identifiable {
    /// Документ со сроком действия: ОСАГО, техосмотр, права.
    case document
    /// Обслуживание: масло, фильтры, шины.
    case service

    var id: String { rawValue }

    var title: String {
        switch self {
        case .document: "Документы"
        case .service: "Обслуживание"
        }
    }
}

/// Напоминание о сроке: по дате, по пробегу или по обоим сразу.
@Model
final class CarReminder: SyncableModel {
    struct Payload: Codable {
        var carID: UUID
        var title: String
        var kind: String
        var dueDate: Date?
        var dueOdometer: Int
        var repeatMonths: Int
        var repeatKm: Int
        var note: String
        var isDone: Bool
        var lastDoneAt: Date?
        var member: String
        var createdAt: Date
    }

    static let recordKind = "car.reminder"

    var syncID: UUID = UUID()
    var carID: UUID = UUID()
    var title: String = ""
    var kindRaw: String = CarReminderKind.service.rawValue
    /// Срок по дате. `nil` — без даты.
    var dueDate: Date? = nil
    /// Срок по пробегу. 0 — без пробега.
    var dueOdometer: Int = 0
    /// Повтор через N месяцев. 0 — без повтора по времени.
    var repeatMonths: Int = 0
    /// Повтор через N км. 0 — без повтора по пробегу.
    var repeatKm: Int = 0
    var note: String = ""
    /// Разовое напоминание выполнено.
    var isDone: Bool = false
    var lastDoneAt: Date? = nil
    var member: String = CoupleMember.owner.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil
    var needsSync: Bool = true

    init(carID: UUID, kind: CarReminderKind, member: CoupleMember) {
        self.carID = carID
        self.kindRaw = kind.rawValue
        self.member = member.rawValue
    }

    init(syncID: UUID, payload: Payload) {
        self.syncID = syncID
        apply(payload)
    }

    var payload: Payload {
        Payload(
            carID: carID, title: title, kind: kindRaw, dueDate: dueDate, dueOdometer: dueOdometer,
            repeatMonths: repeatMonths, repeatKm: repeatKm, note: note, isDone: isDone,
            lastDoneAt: lastDoneAt, member: member, createdAt: createdAt
        )
    }

    func apply(_ payload: Payload) {
        carID = payload.carID
        title = payload.title
        kindRaw = payload.kind
        dueDate = payload.dueDate
        dueOdometer = payload.dueOdometer
        repeatMonths = payload.repeatMonths
        repeatKm = payload.repeatKm
        note = payload.note
        isDone = payload.isDone
        lastDoneAt = payload.lastDoneAt
        member = payload.member
        createdAt = payload.createdAt
    }

    var kind: CarReminderKind {
        get { CarReminderKind(rawValue: kindRaw) ?? .service }
        set { kindRaw = newValue.rawValue }
    }

    var repeats: Bool { repeatMonths > 0 || repeatKm > 0 }
}
