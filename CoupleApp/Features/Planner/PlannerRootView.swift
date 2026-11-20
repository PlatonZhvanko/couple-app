import SwiftData
import SwiftUI

/// Главный экран раздела «Планер»: журнал «Личный» и «Общий».
struct PlannerRootView: View {
    enum Page: String, CaseIterable, Identifiable {
        case personal, partner
        var id: String { rawValue }
        
    }

    @Environment(AccountStore.self) private var account
    @AppStorage("planner.journal") private var page: Page = .personal
    @Query(filter: #Predicate<PlannerEvent> { $0.deletedAt == nil })
    private var events: [PlannerEvent]

    var body: some View {
        NavigationStack {
            PlannerCalendarView(showsPartner: page == .partner)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Журнал", selection: $page) {
                            ForEach(Page.allCases) { item in
                                Text(item == .personal ? "Мой" : "Партнёр").tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 150)
                    }
                }
        }
        .environment(\.locale, PlannerCalendar.locale)
        // Коты заглядывают редко: раз в 6 часов и не каждый раз.
        .catVisit(
            Self.visitingCat, topic: .money,
            chance: 0.35, cooldown: 6 * 3600, messages: CatPhrases.planner
        )
        // При любых изменениях событий (в том числе со второго телефона)
        // пересчитываем напоминания.
        .task(id: reminderSignature) {
            PlannerReminders.reschedule(events: events, me: account.current)
        }
    }

    /// Один кот на день, чтобы ограничение «раз в 6 часов» не обходилось сменой кота.
    private static var visitingCat: Cat {
        let all: [Cat] = [.miron, .gosha, .chloe]
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return all[day % all.count]
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
