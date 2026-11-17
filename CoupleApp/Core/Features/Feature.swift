import SwiftUI
import SwiftData

/// Описание одного раздела приложения (вкладки).
///
/// Каждый раздел живёт в своей папке `Features/<Раздел>/` и отдаёт наружу
/// только одно значение `Feature`: название, иконку, свои модели данных
/// и корневой экран. Так разделы не мешают друг другу.
struct Feature: Identifiable {
    /// Постоянный идентификатор вкладки, например "nutrition". Не менять после релиза.
    let id: String
    let title: String
    /// Имя иконки SF Symbols.
    let systemImage: String
    /// Модели SwiftData этого раздела. Модели, которые надо синхронизировать
    /// между телефонами, должны реализовать `SyncableModel`.
    let models: [any PersistentModel.Type]
    /// Кому показывать вкладку. По умолчанию обоим.
    /// Например, `availableFor: [.owner]` — вкладка только у владельца.
    let availableFor: Set<CoupleMember>
    /// Что раздел показывает в общем календаре (например, записи клиентов).
    /// См. `Core/Calendar/CalendarItem.swift`. `nil` — ничего.
    let calendarItems: CalendarItemProvider?
    let makeRootView: @MainActor () -> AnyView

    init<Content: View>(
        id: String,
        title: String,
        systemImage: String,
        models: [any PersistentModel.Type] = [],
        availableFor: Set<CoupleMember> = Set(CoupleMember.allCases),
        calendarItems: CalendarItemProvider? = nil,
        @ViewBuilder rootView: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.models = models
        self.availableFor = availableFor
        self.calendarItems = calendarItems
        self.makeRootView = { AnyView(rootView()) }
    }

    func isAvailable(for member: CoupleMember) -> Bool {
        availableFor.contains(member)
    }
}
