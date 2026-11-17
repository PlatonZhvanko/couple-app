import SwiftUI

struct SettingsView: View {
    @Environment(SyncCoordinator.self) private var sync
    @AppStorage(ProfileKeys.name) private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    TextField("Как вас зовут", text: $name)
                        .textContentType(.givenName)
                }

                Section("Синхронизация") {
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        LabeledContent("Между телефонами", value: sync.status.title)
                    }
                    NavigationLink("Проверка синхронизации") {
                        ExampleNotesView()
                    }
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Настройки")
        }
    }
}

enum ProfileKeys {
    static let name = "profile.name"
}

extension SyncCoordinator.Status {
    var title: String {
        switch self {
        case .notConfigured: "Не настроена"
        case .signedOut: "Нужно войти"
        case .idle: "Включена"
        case .syncing: "Синхронизация…"
        case .failed: "Ошибка"
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(SyncCoordinator(container: AppDatabase.makeContainer(inMemory: true), models: []))
}
