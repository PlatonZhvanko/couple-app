import SwiftData
import SwiftUI

/// Главный экран раздела «Планер»: журнал «Личный» и «Общий».
struct PlannerRootView: View {
    enum Page: String, CaseIterable, Identifiable {
        case personal, everyone
        var id: String { rawValue }
        var title: String { self == .personal ? "Личный" : "Общий" }
    }

    @Environment(AccountStore.self) private var account
    @AppStorage("planner.journal") private var page: Page = .personal
    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var events: [PlannerEvent]

    var body: some View {
        NavigationStack {
            PlannerCalendarView(showsEveryone: page == .everyone)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Журнал", selection: $page) {
                            ForEach(Page.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
        }
        .environment(\.locale, PlannerCalendar.locale)
        // При любых изменениях событий (в том числе со второго телефона)
        // пересчитываем напоминания.
        .task(id: reminderSignature) {
            PlannerReminders.reschedule(events: events, me: account.current)
        }
    }

    private var reminderSignature: Int {
        var hasher = Hasher()
        for event in events {
            hasher.combine(event.syncID)
            hasher.combine(event.updatedAt)
        }
        return hasher.finalize()
    }
}
