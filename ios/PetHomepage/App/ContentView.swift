// ios/PetHomepage/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        let petStore = PetStore(context: context)
        let medicationStore = MedicationStore(context: context, petStore: petStore)
        let doseLogStore = DoseLogStore(context: context)
        let reminderScheduler = MedicationReminderScheduler(scheduler: UNNotificationScheduler())

        return TabView {
            PetProfileView(store: petStore)
                .tabItem { Label("Profile", systemImage: "pawprint") }
            MedicationsListView(medicationStore: medicationStore,
                                doseLogStore: doseLogStore,
                                reminderScheduler: reminderScheduler)
                .tabItem { Label("Meds", systemImage: "pills") }
        }
    }
}
