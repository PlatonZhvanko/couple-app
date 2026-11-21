import Foundation

/// Продукт, найденный в Open Food Facts.
struct NutritionOFFProduct: Identifiable {
    let id: String
    var values: NutritionFoodValues
    var store: String
    var barcode: String
}

/// Поиск продуктов в Open Food Facts — открытой общей базе упаковок.
/// Нужен интернет. Найденный продукт сохраняется в «Мои», дальше работает без сети.
enum NutritionOpenFoodFacts {
    static let stores = ["Пятёрочка", "Магнит", "Перекрёсток", "Яндекс Лавка"]

    /// Поиск с запасными вариантами: быстрый поиск Open Food Facts, затем старый,
    /// а если ничего нет — упрощённые запросы (меньше слов, обрезанные окончания).
    static func search(_ query: String, store: String?) async throws -> [NutritionOFFProduct] {
        var lastError: Error?
        var gotAnswer = false
        for variant in queryVariants(query) {
            if Task.isCancelled { throw CancellationError() }
            for source in [Source.fast, Source.classic] {
                if Task.isCancelled { throw CancellationError() }
                do {
                    var found = try await run(source, query: variant)
                    gotAnswer = true
                    if let store {
                        let key = store.lowercased().replacingOccurrences(of: "ё", with: "е")
                        found = found.filter {
                            $0.store.lowercased().replacingOccurrences(of: "ё", with: "е").contains(key)
                        }
                    }
                    if !found.isEmpty { return found }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                }
            }
        }
        if !gotAnswer, let lastError { throw lastError }
        return []
    }

    private enum Source { case fast, classic }

    /// Запрос в нижнем регистре, без знаков, «ё» как «е».
    static func normalized(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Запросы от точного к простому: целиком, первые слова, обрезанные окончания, самое длинное слово.
    static func queryVariants(_ query: String) -> [String] {
        let words = normalized(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var result: [String] = [words.joined(separator: " ")]
        if words.count > 3 { result.append(words.prefix(3).joined(separator: " ")) }
        if words.count > 2 { result.append(words.prefix(2).joined(separator: " ")) }
        let stems = words.filter { $0.count > 2 }.map { $0.count > 6 ? String($0.prefix($0.count - 2)) : $0 }
        if !stems.isEmpty { result.append(stems.prefix(2).joined(separator: " ")) }
        if let longest = words.max(by: { $0.count < $1.count }), words.count > 1 { result.append(longest) }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private static func run(_ source: Source, query: String) async throws -> [NutritionOFFProduct] {
        var components: URLComponents
        let timeout: TimeInterval
        switch source {
        case .fast:
            components = URLComponents(string: "https://search.openfoodfacts.org/search")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page_size", value: "40"),
                URLQueryItem(name: "fields", value: "code,product_name,brands,stores,nutriments"),
            ]
            timeout = 8
        case .classic:
            components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
            components.queryItems = [
                URLQueryItem(name: "search_terms", value: query),
                URLQueryItem(name: "search_simple", value: "1"),
                URLQueryItem(name: "action", value: "process"),
                URLQueryItem(name: "json", value: "1"),
                URLQueryItem(name: "page_size", value: "40"),
                URLQueryItem(name: "fields", value: "code,product_name,brands,stores,nutriments"),
                URLQueryItem(name: "tagtype_0", value: "countries"),
                URLQueryItem(name: "tag_contains_0", value: "contains"),
                URLQueryItem(name: "tag_0", value: "russia"),
            ]
            timeout = 12
        }
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Vdvoem-private-app/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let products = (root["hits"] as? [[String: Any]]) ?? (root["products"] as? [[String: Any]]) ?? []
        return products.compactMap(product(from:))
    }

    private static func product(from item: [String: Any]) -> NutritionOFFProduct? {
        let name = (item["product_name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let nutriments = item["nutriments"] as? [String: Any] else { return nil }
        let kcal: Double
        if let value = number(nutriments["energy-kcal_100g"]) {
            kcal = value
        } else if let kj = number(nutriments["energy_100g"]) {
            kcal = kj / 4.184
        } else {
            return nil
        }
        var brand = ""
        if let text = item["brands"] as? String {
            brand = text.split(separator: ",").first.map(String.init) ?? ""
        } else if let list = item["brands"] as? [String] {
            brand = list.first ?? ""
        }
        var store = ""
        if let text = item["stores"] as? String {
            store = text
        } else if let list = item["stores"] as? [String] {
            store = list.joined(separator: ", ")
        }
        let code = item["code"] as? String ?? UUID().uuidString
        let values = NutritionFoodValues(
            name: name, brand: brand.trimmingCharacters(in: .whitespaces), kcal: kcal.rounded(),
            protein: number(nutriments["proteins_100g"]) ?? 0,
            fat: number(nutriments["fat_100g"]) ?? 0,
            carbs: number(nutriments["carbohydrates_100g"]) ?? 0
        )
        return NutritionOFFProduct(id: code, values: values, store: store, barcode: code)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
