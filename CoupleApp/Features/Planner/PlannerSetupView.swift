import SwiftUI

/// Вкладка рядом с «Клиентами»: группы, абонементы и цвета.
struct PlannerSetupView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PlannerGroupSettingsView().navigationTitle("Группы")
                } label: {
                    Label("👧👦 Группы", systemImage: "person.3.fill")
                }
                NavigationLink {
                    PlannerSubscriptionSettingsView().navigationTitle("Абонементы")
                } label: {
                    Label("📜 Абонементы", systemImage: "ticket.fill")
                }
                NavigationLink {
                    PlannerColorSettingsView().navigationTitle("Цвета")
                } label: {
                    Label("🎨 Цвета", systemImage: "paintpalette.fill")
                }
            }
            .navigationTitle("Группы и абонементы")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum PlannerSetupFeature {
    static let feature = Feature(
        id: "plannerSetup",
        title: "Группы и абонементы",
        systemImage: "person.3.fill",
        availableFor: [.partner]
    ) {
        PlannerSetupView()
    }
}
