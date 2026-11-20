/// Адрес сервера Supabase, «зашитый» в приложение.
///
/// Если заполнить эти две строки (Supabase → Project Settings → API),
/// на телефонах достаточно будет ввести только почту и пароль.
/// Если оставить пустыми, адрес и ключ можно ввести на экране входа.
/// anon key публичный по задумке Supabase: доступ к данным защищён правилами в базе.
enum BackendConfig {
    static let supabaseURL = "https://izyhshljamzgyzxoupss.supabase.co"
    static let supabaseAnonKey = "sb_publishable_JGpF10oVVeF9mfN4vxT6Aw_xf9_bSfI"

    static var defaultSupabase: SupabaseConfig {
        SupabaseConfig(url: supabaseURL, anonKey: supabaseAnonKey)
    }
}
