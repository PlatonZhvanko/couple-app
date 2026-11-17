import SwiftUI

/// Раздел «Клиенты».
///
/// Всё, что относится к разделу, лежит в папке `Features/Clients/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum ClientsFeature {
    static let feature = Feature(
        id: "clients",
        title: "Клиенты",
        systemImage: "person.2.fill",
        models: [
            ClientsClient.self,
            ClientsAppointment.self,
        ],
        calendarItems: { context, interval in
            ClientsCalendar.items(context: context, interval: interval)
        }
    ) {
        ClientsRootView()
    }
}
