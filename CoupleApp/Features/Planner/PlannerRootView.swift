import SwiftData
import SwiftUI

/// Главный экран раздела «Планер»: календарь и дела.
struct PlannerRootView: View {
    enum Page: String, CaseIterable, Identifiable {
        case calendar, tasks
        var id: String { rawValue }
        var title: String { self == .calendar ? "Календарь" : "Дела" }
    }

    @Environment(AccountStore.self) private var account
    @AppStorage("planner.page") private var page: Page = .calendar
    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var events: [PlannerEvent]

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .calendar: PlannerCalendarView()
                case .tasks: PlannerTasksView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Раздел", selection: $page) {
                        ForEach(Page.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
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
