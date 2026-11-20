import SwiftUI

/// Раздел «Питомцы»: карточки питомцев, заметки, прививки и вес.
enum PetsFeature {
    static let feature = Feature(
        id: "pets",
        title: "Питомцы",
        systemImage: "pawprint.fill",
        models: [PetsPet.self]
    ) {
        PetsRootView()
    }
}
