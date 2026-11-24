import Foundation
import SwiftData

/// Питомец. Три кота добавляются при первом запуске с постоянными id,
/// поэтому на двух телефонах это одни и те же записи.
@Model
final class PetsPet: SyncableModel {
    struct Payload: Codable {
        var name: String
        var species: String
        var iconKey: String
        var birthday: Date?
        var weightKg: Double
        var note: String
        var vetNote: String
        var createdAt: Date
        var breed: String?
    }

    static let recordKind = "pets.pet"

    var syncID: UUID = UUID()
    var name: String = ""
    /// «Кот», «Собака» и т.д. — просто текст.
    var species: String = "Кот"
    /// Ключ рисунка: `PetsCatStyle.rawValue` или пусто.
    var iconKey: String = ""
    var birthday: Date? = nil
    /// 0 — не указан.
    var weightKg: Double = 0
    var note: String = ""
    /// Прививки, обработки, визиты к врачу.
    var vetNote: String = ""
    /// Порода: «Дворовая», «Шотландская».
    var breed: String = ""
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
        Payload(name: name, species: species, iconKey: iconKey, birthday: birthday, weightKg: weightKg,
                note: note, vetNote: vetNote, createdAt: createdAt, breed: breed.isEmpty ? nil : breed)
    }

    func apply(_ payload: Payload) {
        name = payload.name
        species = payload.species
        iconKey = payload.iconKey
        birthday = payload.birthday
        weightKg = payload.weightKg
        note = payload.note
        vetNote = payload.vetNote
        createdAt = payload.createdAt
        breed = payload.breed ?? ""
    }

    var displayName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Питомец" : name }
}

/// Наши четыре кота. id фиксированные, чтобы на втором телефоне не было дублей.
enum PetsSeed {
    static let flagKey = "pets.seeded.v1"

    static let cats: [(id: String, name: String, style: PetsCatStyle, note: String)] = [
        ("6A0F3C10-0000-4000-8000-00000000A001", "Мироня", .tuxedo, "Большой чёрно-белый кот."),
        ("6A0F3C10-0000-4000-8000-00000000A002", "Гоша", .slim, "Чёрный худенький кот."),
        ("6A0F3C10-0000-4000-8000-00000000A003", "Хлоя", .grey, "Маленькая серая кошечка."),
        ("6A0F3C10-0000-4000-8000-00000000A004", "Миса", .cream, "Кремовая кошечка, порода атлантика."),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        // Первый запуск: все коты. Позже появилась Миса: добавляем только её, один раз.
        let defaults = UserDefaults.standard
        let hadFirst = defaults.bool(forKey: flagKey)
        guard !defaults.bool(forKey: "pets.seeded.v2") else { return }
        defaults.set(true, forKey: flagKey)
        defaults.set(true, forKey: "pets.seeded.v2")
        let existing = (try? context.fetch(FetchDescriptor<PetsPet>())) ?? []
        let known = Set(existing.map(\.syncID))
        for cat in cats where !hadFirst || cat.id.hasSuffix("A004") {
            guard let id = UUID(uuidString: cat.id), !known.contains(id) else { continue }
            let pet = PetsPet(name: cat.name)
            pet.syncID = id
            pet.iconKey = cat.style.rawValue
            pet.note = cat.note
            pet.breed = cat.id.hasSuffix("A004") ? "Шотландская" : "Дворовая"
            context.insert(pet)
        }
        try? context.save()
    }

    /// Породы нашим котам: всем «Дворовая», Мисе «Шотландская». Один раз, и только если порода пустая.
    @MainActor
    static func applyBreedsIfNeeded(context: ModelContext) {
        let key = "pets.breeds.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let pets = (try? context.fetch(FetchDescriptor<PetsPet>())) ?? []
        guard !pets.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: key)
        for pet in pets where pet.deletedAt == nil && pet.breed.isEmpty {
            guard let seed = cats.first(where: { UUID(uuidString: $0.id) == pet.syncID }) else { continue }
            pet.breed = seed.id.hasSuffix("A004") ? "Шотландская" : "Дворовая"
            pet.markChanged()
        }
        try? context.save()
    }
}
