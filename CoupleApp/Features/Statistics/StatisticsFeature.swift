import SwiftUI

/// Раздел «Статистика». Пока только «Деньги» и «Клиенты».
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
