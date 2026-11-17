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

    static func search(_ query: String, store: String?) async throws -> [NutritionOFFProduct] {
        var items = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "40"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,stores,nutriments,quantity"),
            URLQueryItem(name: "tagtype_0", value: "countries"),
            URLQueryItem(name: "tag_contains_0", value: "contains"),
            URLQueryItem(name: "tag_0", value: "russia"),
        ]
        if let store {
            items += [
                URLQueryItem(name: "tagtype_1", value: "stores"),
                URLQueryItem(name: "tag_contains_1", value: "contains"),
                URLQueryItem(name: "tag_1", value: store),
            ]
        }
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = items
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Vdvoem-private-app/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = root["products"] as? [[String: Any]] else { return [] }

        return products.compactMap { item -> NutritionOFFProduct? in
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
            let brand = (item["brands"] as? String ?? "").split(separator: ",").first.map(String.init) ?? ""
            let code = item["code"] as? String ?? UUID().uuidString
            let values = NutritionFoodValues(
                name: name, brand: brand.trimmingCharacters(in: .whitespaces), kcal: kcal.rounded(),
                protein: number(nutriments["proteins_100g"]) ?? 0,
                fat: number(nutriments["fat_100g"]) ?? 0,
                carbs: number(nutriments["carbohydrates_100g"]) ?? 0
            )
            return NutritionOFFProduct(id: code, values: values, store: item["stores"] as? String ?? "", barcode: code)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
