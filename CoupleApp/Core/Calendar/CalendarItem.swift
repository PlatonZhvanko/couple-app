import SwiftData
import SwiftUI

/// Элемент, который другой раздел хочет показать в календаре «Планера»
/// (например, запись клиента). Только для просмотра: правится в своём разделе.
struct CalendarItem: Identifiable {
    /// Уникальный id, например "clients.appointment.<uuid>".
    let id: String
    let title: String
    let start: Date
    let end: Date
    /// Чьё это. `nil` — касается обоих.
    let member: CoupleMember?
    let color: Color
    /// Имя иконки SF Symbols.
    let systemImage: String
    /// Окно записи (открывается по нажатию в Планере). `nil` — запись только для просмотра.
    /// Кому ещё показывать запись, кроме `member` (например, тому, кто поставил ремонт чужой машины).
    var sharedWith: [CoupleMember] = []
    /// Маленький эмодзи в правом верхнем углу записи (например, 🔧). Пусто — без него.
    var emoji = ""
    /// Маленький эмодзи в левом верхнем углу записи. Пусто — без него.
    var leadingEmoji = ""
    var detail: (@MainActor () -> AnyView)? = nil
    /// Перенос записи на новое начало (перетаскиванием в Планере). Вызывается только для владельца.
    var move: (@MainActor (Date) -> Void)? = nil
}

/// Отдаёт элементы раздела, которые пересекаются с интервалом `interval`.
/// Удалённые и отменённые записи отдавать не нужно.
typealias CalendarItemProvider = @MainActor (_ context: ModelContext, _ interval: DateInterval) -> [CalendarItem]

extension FeatureRegistry {
    /// Все элементы календаря из всех разделов за интервал.
    @MainActor
    static func calendarItems(context: ModelContext, interval: DateInterval) -> [CalendarItem] {
        all.compactMap(\.calendarItems).flatMap { $0(context, interval) }
    }
}
