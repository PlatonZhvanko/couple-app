import SwiftUI

/// Раздел «Авто».
///
/// Машины, журнал трат и заправок, напоминания о сроках.
/// Спецификация: `docs/features/car.md`.
///
/// Всё, что относится к разделу, лежит в папке `Features/Car/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum CarFeature {
    static let feature = Feature(
        id: "car",
        title: "Авто",
        systemImage: "car.fill",
        models: [
            CarVehicle.self,
            CarEntry.self,
            CarReminder.self,
            CarRepair.self,
        ],
        calendarItems: { context, interval in
            CarCalendar.items(context: context, interval: interval)
        }
    ) {
        CarRootView()
    }
}
