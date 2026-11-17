import SwiftUI

/// Раздел «Авто».
///
/// Всё, что относится к разделу, лежит в папке `Features/Car/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum CarFeature {
    static let feature = Feature(
        id: "car",
        title: "Авто",
        systemImage: "car.fill",
        models: [
            // Сюда добавлять модели SwiftData раздела, например: CarEntry.self
        ]
    ) {
        CarRootView()
    }
}
