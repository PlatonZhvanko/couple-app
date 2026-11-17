import SwiftUI

/// Подключение к Supabase: адрес проекта, ключ и вход в аккаунт.
/// Пошаговая инструкция: docs/sync-setup.md в репозитории.
struct SyncSettingsView: View {
    @Environment(SyncCoordinator.self) private var sync

    @State private var url = ""
    @State private var anonKey = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                TextField("https://xxxx.supabase.co", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("anon public key", text: $anonKey, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button("Сохранить") {
                    sync.updateConfig(SupabaseConfig(url: url, anonKey: anonKey))
                }
                .disabled(SupabaseConfig(url: url, anonKey: anonKey) == sync.config)
            } header: {
                Text("Сервер Supabase")
            } footer: {
                Text("Адрес и ключ есть в Supabase: Project Settings → API. На обоих телефонах они одинаковые.")
            }

            if sync.config.isComplete {
                if let email = sync.signedInEmail {
                    Section("Аккаунт") {
                        LabeledContent("Вошли как", value: email)
                        Button("Выйти", role: .destructive) { sync.signOut() }
                    }
                } else {
                    Section("Вход") {
                        TextField("Почта", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Пароль", text: $password)
                            .textContentType(.password)
                        Button("Войти") {
                            run { await sync.signIn(email: email, password: password) }
                        }
                        .disabled(email.isEmpty || password.isEmpty || isWorking)
                    }
                }
            }

            Section("Состояние") {
                LabeledContent("Статус", value: sync.status.title)
                if case let .failed(message) = sync.status {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let last = sync.lastSyncedAt {
                    LabeledContent("Последний раз", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Синхронизировать сейчас") {
                    run { await sync.syncNow() }
                }
                .disabled(sync.signedInEmail == nil || isWorking)
            }
        }
        .navigationTitle("Синхронизация")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            url = sync.config.url
            anonKey = sync.config.anonKey
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}
