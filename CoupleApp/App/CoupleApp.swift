import SwiftUI
import SwiftData

/// Точка входа приложения.
@main
struct CoupleApp: App {
    private let environment: AppEnvironment

    init() {
        environment = AppEnvironment.live()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment.sync)
        }
        .modelContainer(environment.modelContainer)
    }
}
