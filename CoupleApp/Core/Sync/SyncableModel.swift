import Foundation
import SwiftData

/// Модель SwiftData, которую нужно синхронизировать между телефонами.
///
/// Как сделать свою модель синхронизируемой:
/// 1. Объявить её как `@Model final class` и реализовать этот протокол.
/// 2. Описать `Payload`: все поля, которые должны попасть на второй телефон.
/// 3. При каждом изменении вызывать `markChanged()`, при удалении `markDeleted()`
///    (запись не удаляется из базы, а помечается удалённой, чтобы удаление
///    дошло до второго телефона). В списках фильтровать `deletedAt == nil`.
/// 4. Добавить модель в `models` своего раздела. Больше ничего не нужно:
///    сервер хранит все записи в одной общей таблице.
protocol SyncableModel: PersistentModel {
    associatedtype Payload: Codable

    /// Тип записи на сервере, например "nutrition.meal". Не менять после релиза.
    static var recordKind: String { get }

    var syncID: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    /// true, если есть локальные изменения, ещё не отправленные на сервер.
    var needsSync: Bool { get set }

    /// Данные записи для отправки на сервер.
    var payload: Payload { get }
    /// Создать запись, пришедшую со второго телефона.
    init(syncID: UUID, payload: Payload)
    /// Обновить запись данными со второго телефона.
    func apply(_ payload: Payload)
}

extension SyncableModel {
    /// Отметить, что запись изменилась и её надо отправить.
    func markChanged() {
        updatedAt = .now
        needsSync = true
    }

    /// Пометить запись удалённой (удаление тоже синхронизируется).
    func markDeleted() {
        deletedAt = .now
        markChanged()
    }
}
