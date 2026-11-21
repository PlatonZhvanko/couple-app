import SwiftUI

/// Раздел «Здоровье» (раньше «Настроение»: id и папка остались прежними).
///
/// Всё, что относится к разделу, лежит в папке `Features/Mood/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum MoodFeature {
    static let feature = Feature(
        id: "mood",
        title: "Здоровье",
        systemImage: "heart.text.square",
        models: [
            MoodEntry.self,
            MoodReaction.self,
            MoodDayCheckIn.self,
            MoodWeightEntry.self,
        ],
        calendarItems: MoodCalendar.items
    ) {
        MoodRootView()
    }
}
