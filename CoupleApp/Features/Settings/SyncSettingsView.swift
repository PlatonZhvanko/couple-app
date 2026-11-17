import SwiftUI

/// Состояние синхронизации между телефонами.
/// Как настроить сервер: docs/sync-setup.md в репозитории.
struct SyncSettingsView: View {
    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Статус", value: sync.status.title)
                if case let .failed(message) = sync.status {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let last = sync.lastSyncedAt {
                    LabeledContent("Последний раз", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if account.isServerMode {
                    Button("Синхронизировать сейчас") {
                        isWorking = true
                        Task {
                            await sync.syncNow()
                            isWorking = false
                        }
                    }
                    .disabled(isWorking)
                }
            } footer: {
                if !account.isServerMode {
                    Text("Вы вошли без сервера, поэтому данные хранятся только на этом телефоне. Чтобы включить синхронизацию, выйдите из аккаунта и войдите по почте и паролю.")
                }
            }

            if account.isServerMode {
                Section("Сервер") {
                    LabeledContent("Адрес", value: account.config.url)
                }
            }
        }
        .navigationTitle("Синхронизация")
        .navigationBarTitleDisplayMode(.inline)
    }
}
