/// Один из двух людей в паре.
///
/// Используйте его, чтобы разделы вели себя по-разному для разных аккаунтов
/// и чтобы помечать, чья это запись:
///
/// ```swift
/// @Environment(AccountStore.self) private var account
/// if account.me == .owner { ... }               // только для владельца
/// entry.member = account.me.rawValue            // запись принадлежит мне
/// ```
///
/// Значение не зависит от сервера и не меняется, поэтому его можно хранить в моделях.
enum CoupleMember: String, Codable, CaseIterable, Identifiable {
    /// Владелец приложения (Гаджи).
    case owner
    /// Партнёр.
    case partner

    var id: String { rawValue }

    /// Второй человек в паре.
    var other: CoupleMember { self == .owner ? .partner : .owner }

    /// Название по умолчанию, пока имя не задано.
    var defaultName: String { self == .owner ? "Я" : "Партнёр" }
}
