import Foundation
import Observation

/// Кто сейчас пользуется приложением.
///
/// Вход делается один раз: дальше аккаунт запоминается на телефоне
/// (пароль не хранится, хранится только токен входа в Keychain).
///
/// Во всех разделах доступен так:
/// ```swift
/// @Environment(AccountStore.self) private var account
/// Text("Привет, \(account.myName)")
/// ```
@Observable
@MainActor
final class AccountStore {
    /// Как выполнен вход.
    enum Mode: String, Codable {
        /// Через сервер Supabase: данные синхронизируются между телефонами.
        case server
        /// Без сервера: данные только на этом телефоне (для пробы и симулятора).
        case local
    }

    /// Чей это телефон. `nil` — вход ещё не выполнен.
    private(set) var me: CoupleMember? = nil
    private(set) var mode: Mode? = nil
    private(set) var email: String? = nil
    private(set) var names: [CoupleMember: String] = [:]
    private(set) var config: SupabaseConfig
    @ObservationIgnored private(set) var client: SupabaseClient? = nil

    /// Вызывается при входе и выходе (синхронизация начинает заново).
    @ObservationIgnored var onAccountChange: (() -> Void)? = nil

    var isSignedIn: Bool { me != nil }
    var isServerMode: Bool { mode == .server }

    /// Текущий человек. Используйте только после входа (экраны разделов
    /// показываются только после входа, так что там это всегда безопасно).
    var current: CoupleMember { me ?? .owner }

    var myName: String { name(of: current) }
    var partnerName: String { name(of: current.other) }

    func name(of member: CoupleMember) -> String {
        let name = names[member]?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? member.defaultName : name
    }

    // MARK: - Хранение

    private struct Saved: Codable {
        var me: CoupleMember
        var mode: Mode
        var email: String?
        var names: [String: String]
    }

    private enum Keys {
        static let saved = "account.saved"
        static let config = "account.supabaseConfig"
        static let session = "account.supabaseSession"
    }

    init() {
        let defaults = UserDefaults.standard
        let storedConfig = defaults.data(forKey: Keys.config)
            .flatMap { try? JSONDecoder().decode(SupabaseConfig.self, from: $0) }
        config = storedConfig ?? BackendConfig.defaultSupabase

        if let saved = defaults.data(forKey: Keys.saved).flatMap({ try? JSONDecoder().decode(Saved.self, from: $0) }) {
            me = saved.me
            mode = saved.mode
            email = saved.email
            for (key, value) in saved.names {
                if let member = CoupleMember(rawValue: key) { names[member] = value }
            }
        }

        let session = KeychainStore.data(for: Keys.session)
            .flatMap { try? JSONDecoder().decode(SupabaseSession.self, from: $0) }
        makeClient(session: mode == .server ? session : nil)
    }

    private func save() {
        guard let me, let mode else {
            UserDefaults.standard.removeObject(forKey: Keys.saved)
            return
        }
        let saved = Saved(
            me: me,
            mode: mode,
            email: email,
            names: Dictionary(uniqueKeysWithValues: names.map { ($0.key.rawValue, $0.value) })
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Keys.saved)
    }

    private func makeClient(session: SupabaseSession?) {
        guard config.isComplete else { client = nil; return }
        let client = SupabaseClient(config: config, session: session)
        client.onSessionChange = { session in
            KeychainStore.set(session.flatMap { try? JSONEncoder().encode($0) }, for: Keys.session)
        }
        self.client = client
    }

    // MARK: - Сервер

    func updateConfig(_ newConfig: SupabaseConfig) {
        guard newConfig != config else { return }
        config = newConfig
        UserDefaults.standard.set(try? JSONEncoder().encode(newConfig), forKey: Keys.config)
        makeClient(session: nil)
    }

    // MARK: - Вход и выход

    /// Вход через сервер. Аккаунты создаются в Supabase (см. docs/sync-setup.md).
    func signIn(email: String, password: String) async throws {
        guard let client else { throw SupabaseError.notConfigured }
        try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        do {
            try await loadMembers()
        } catch {
            client.signOut()
            throw error
        }
        mode = .server
        self.email = client.session?.email
        save()
        onAccountChange?()
    }

    /// Вход без сервера: данные только на этом телефоне.
    func continueLocally(as member: CoupleMember, name: String) {
        me = member
        mode = .local
        email = nil
        names[member] = name
        save()
        onAccountChange?()
    }

    /// Переключить профиль в режиме «без сервера» (для проверки): Платоня или Настенька.
    /// Данные на телефоне общие, меняется только то, кто сейчас вошёл.
    func switchLocalProfile(to member: CoupleMember) {
        guard mode == .local, me != member else { return }
        for item in CoupleMember.allCases where (names[item] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            names[item] = item == .owner ? "Платоня" : "Настенька"
        }
        me = member
        save()
        onAccountChange?()
    }

    func signOut() {
        client?.signOut()
        me = nil
        mode = nil
        email = nil
        names = [:]
        save()
        onAccountChange?()
    }

    /// Обновить имена из базы. Вызывается при открытии приложения; ошибки не важны.
    func refreshFromServer() async {
        guard mode == .server else { return }
        try? await loadMembers()
    }

    /// Поменять своё имя (видно и на втором телефоне).
    func rename(to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        names[current] = trimmed
        save()
        guard mode == .server, let client, let userID = client.session?.userID else { return }
        let body = try JSONSerialization.data(withJSONObject: ["display_name": trimmed])
        _ = try await client.rest(
            "couple_members",
            query: "user_id=eq.\(userID)",
            method: "PATCH",
            body: body,
            headers: ["Prefer": "return=minimal"]
        )
    }

    /// Узнать из базы, кто я в паре и как нас зовут.
    private func loadMembers() async throws {
        guard let client, let userID = client.session?.userID else { throw SupabaseError.notSignedIn }
        let data = try await client.rest("couple_members", query: "select=user_id,role,display_name")
        struct Row: Decodable {
            let user_id: String
            let role: CoupleMember?
            let display_name: String?
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard let mine = rows.first(where: { $0.user_id.lowercased() == userID.lowercased() }), let role = mine.role else {
            throw AccountError.notInCouple
        }
        var newNames: [CoupleMember: String] = [:]
        for row in rows {
            if let role = row.role, let name = row.display_name { newNames[role] = name }
        }
        me = role
        names = newNames
        save()
    }
}

enum AccountError: LocalizedError {
    case notInCouple

    var errorDescription: String? {
        switch self {
        case .notInCouple:
            "Вход выполнен, но этот аккаунт ещё не добавлен в пару. Выполните шаг 3 из инструкции docs/sync-setup.md."
        }
    }
}
