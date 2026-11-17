import SwiftUI

struct SettingsView: View {
    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync

    @State private var name = ""
    @State private var renameError: String?
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ваше имя", text: $name)
                        .textContentType(.givenName)
                        .onSubmit(saveName)
                    if name != account.myName {
                        Button("Сохранить имя", action: saveName)
                    }
                    if let renameError {
                        Text(renameError).font(.footnote).foregroundStyle(.red)
                    }
                    LabeledContent("Аккаунт", value: account.current == .owner ? "Владелец" : "Партнёр")
                    if let email = account.email {
                        LabeledContent("Почта", value: email)
                    }
                    LabeledContent("Вторая половинка", value: account.partnerName)
                } header: {
                    Text("Профиль")
                }

                if account.mode == .local {
                    Section {
                        Picker("Войти как", selection: Binding(
                            get: { account.current },
                            set: { account.switchLocalProfile(to: $0) }
                        )) {
                            Text("Платоня").tag(CoupleMember.owner)
                            Text("Настенька").tag(CoupleMember.partner)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Проверка профилей")
                    } footer: {
                        Text("Работает без сервера. Нажми «Настенька», и вкладка «Планер» покажет её форму тренировки.")
                    }
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

                Section {
                    Button("Выйти из аккаунта", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Настройки")
            .onAppear { name = account.myName }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { account.signOut() }
            } message: {
                Text("Данные на телефоне сохранятся. Чтобы вернуться, нужно будет снова ввести почту и пароль.")
            }
        }
    }

    private func saveName() {
        renameError = nil
        let newName = name
        Task {
            do {
                try await account.rename(to: newName)
            } catch {
                renameError = error.localizedDescription
            }
        }
    }
}

extension SyncCoordinator.Status {
    var title: String {
        switch self {
        case .localOnly: "Только этот телефон"
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
    let account = AccountStore()
    return SettingsView()
        .environment(account)
        .environment(SyncCoordinator(container: AppDatabase.makeContainer(inMemory: true), models: [], account: account))
}
