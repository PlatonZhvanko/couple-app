import SwiftUI

/// Раздел «Планер»: общий календарь и списки дел.
///
/// Всё, что относится к разделу, лежит в папке `Features/Planner/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
/// Описание функций: `docs/planner.md`.
enum PlannerFeature {
    static let feature = Feature(
        id: "planner",
        title: "Планер",
        systemImage: "calendar",
        models: [
            PlannerEvent.self,
            PlannerTask.self,
            PlannerPayment.self,
            PlannerSubscription.self,
            PlannerGroupKind.self, PlannerSubscriptionType.self,
            PlannerErrandKind.self,
            PlannerColorRule.self,
            PlannerMoneyKind.self, PlannerMoneyOp.self, PlannerShift.self,
            PlannerStatusStyle.self,
            PlannerOlimpicDay.self,
        ]
    ) {
        PlannerRootView()
    }
}
