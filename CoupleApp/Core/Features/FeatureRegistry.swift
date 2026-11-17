/// Список разделов в порядке вкладок.
///
/// Чтобы добавить новый раздел: создать папку `Features/<Раздел>/`
/// с файлом `<Раздел>Feature.swift` и дописать его сюда одной строкой.
enum FeatureRegistry {
    static let all: [Feature] = [
        PlannerFeature.feature,
        NutritionFeature.feature,
        SleepFeature.feature,
        MoodFeature.feature,
        ClientsFeature.feature,
        CarFeature.feature,
    ]
}
