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
