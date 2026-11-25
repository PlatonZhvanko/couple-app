import SwiftUI

/// «Выбрать в планере»: открывает журнал, нажатие на любое время возвращает его в форму.
struct PlannerSlotPickerSheet: View {
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlannerCalendarView(showsPartner: false, pickSlot: { start in
                onPick(start)
                dismiss()
            })
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.locale, PlannerCalendar.locale)
    }
}
