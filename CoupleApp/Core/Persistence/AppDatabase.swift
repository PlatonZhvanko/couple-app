import Foundation
import SwiftData

/// Локальная база данных на телефоне (SwiftData).
/// Все данные сначала сохраняются здесь, приложение работает и без интернета.
enum AppDatabase {
    /// Модели, общие для всего приложения (не принадлежат ни одному разделу).
    static let coreModels: [any PersistentModel.Type] = [
        ExampleNote.self,
    ]

    static var allModels: [any PersistentModel.Type] {
        coreModels
            + FeatureRegistry.all.flatMap(\.models)
            + SettingsFeature.feature.models
    }

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(allModels)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Не удалось открыть базу данных: \(error)")
        }
    }
}
