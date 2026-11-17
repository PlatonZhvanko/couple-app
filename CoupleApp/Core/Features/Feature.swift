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
    let makeRootView: @MainActor () -> AnyView

    init<Content: View>(
        id: String,
        title: String,
        systemImage: String,
        models: [any PersistentModel.Type] = [],
        @ViewBuilder rootView: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.models = models
        self.makeRootView = { AnyView(rootView()) }
    }
}
