import SwiftUI

/// Экран входа. Показывается один раз: после входа аккаунт запоминается.
struct LoginView: View {
    @Environment(AccountStore.self) private var account

    @State private var email = ""
    @State private var password = ""
    @State private var serverURL = ""
    @State private var serverKey = ""
    @State private var showServer = false
    @State private var isWorking = false
    @State private var errorText: String?

    @State private var showLocal = false
    @State private var localMember: CoupleMember = .owner
    @State private var localName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                        Text("Вдвоём")
                            .font(.largeTitle.bold())
                        Text("Войдите в свой аккаунт. Это нужно сделать один раз.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                if showServer || !account.config.isComplete {
                    Section {
                        TextField("https://xxxx.supabase.co", text: $serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("anon public key", text: $serverKey, axis: .vertical)
                            .lineLimit(1...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                    } header: {
                        Text("Сервер")
                    } footer: {
                        Text("Адрес и ключ из Supabase: Project Settings → API. Нужно один раз.")
                    }
                }

                Section("Аккаунт") {
                    TextField("Почта", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .onSubmit(signIn)
                    Button(action: signIn) {
                        HStack {
                            Text("Войти")
                            if isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!canSignIn)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if account.config.isComplete {
                        Button(showServer ? "Скрыть настройки сервера" : "Изменить сервер") {
                            showServer.toggle()
                        }
                    }
                    Button("Попробовать без сервера") { showLocal = true }
                } footer: {
                    Text("Без сервера данные хранятся только на этом телефоне и не видны второму.")
                }
            }
            .onAppear {
                serverURL = account.config.url
                serverKey = account.config.anonKey
            }
            .sheet(isPresented: $showLocal) { localSheet }
        }
    }

    private var serverConfig: SupabaseConfig {
        SupabaseConfig(url: serverURL, anonKey: serverKey)
    }

    private var canSignIn: Bool {
        !email.isEmpty && !password.isEmpty && serverConfig.isComplete && !isWorking
    }

    private func signIn() {
        guard canSignIn else { return }
        account.updateConfig(serverConfig)
        isWorking = true
        errorText = nil
        Task {
            do {
                try await account.signIn(email: email, password: password)
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    private var localSheet: some View {
        NavigationStack {
            Form {
                Section("Кто вы") {
                    Picker("Аккаунт", selection: $localMember) {
                        Text("Владелец").tag(CoupleMember.owner)
                        Text("Партнёр").tag(CoupleMember.partner)
                    }
                    .pickerStyle(.segmented)
                    TextField("Ваше имя", text: $localName)
                }
                Section {
                    Button("Продолжить") {
                        showLocal = false
                        account.continueLocally(as: localMember, name: localName)
                    }
                }
            }
            .navigationTitle("Без сервера")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    LoginView()
        .environment(AccountStore())
}
