import SwiftUI

/// Раздел «Настроение».
///
/// Всё, что относится к разделу, лежит в папке `Features/Mood/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum MoodFeature {
    static let feature = Feature(
        id: "mood",
        title: "Настроение",
        systemImage: "face.smiling",
        models: [
            MoodEntry.self,
            MoodReaction.self,
            MoodDayCheckIn.self,
        ],
        calendarItems: MoodCalendar.items
    ) {
        MoodRootView()
    }
}
