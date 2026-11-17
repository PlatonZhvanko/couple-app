import Foundation

/// Сервер, через который телефоны обмениваются данными.
///
/// Сейчас это Supabase (`SupabaseSyncBackend`). Если когда-нибудь захотим
/// другой сервер, достаточно написать новую реализацию этого протокола:
/// разделы приложения про сервер ничего не знают.
@MainActor
protocol SyncBackend {
    /// Отправить локальные изменения.
    func push(_ records: [SyncRecord]) async throws
    /// Получить все записи, изменённые на сервере после `cursor`.
    /// Возвращает записи и новый курсор.
    func pull(since cursor: Date?) async throws -> (records: [SyncRecord], cursor: Date?)
}
