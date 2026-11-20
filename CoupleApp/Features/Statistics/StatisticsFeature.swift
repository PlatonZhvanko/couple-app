import SwiftUI

/// Раздел «Статистика»: «Финансы», «Загруженность» и «Настроение».
/// Новые подразделы добавляются в `StatisticsSection` (см. StatisticsRootView.swift).
enum StatisticsFeature {
    static let feature = Feature(
        id: "statistics",
        title: "Статистика",
        systemImage: "chart.bar.xaxis",
        // Данные сна временно остаются в базе, пока вкладка «Сон» убрана.
        models: [
            SleepEntry.self,
        ]
    ) {
        StatisticsRootView()
    }
}
