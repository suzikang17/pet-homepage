// ios/PetHomepage/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context

    /// v1 default vet-visit cadence: see the vet every 6 months.
    private let vetCadenceMonths = 6

    var body: some View {
        let petStore = PetStore(context: context)
        let medicationStore = MedicationStore(context: context, petStore: petStore)
        let doseLogStore = DoseLogStore(context: context)
        let vaccinationStore = VaccinationStore(context: context, petStore: petStore)
        let vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        let recommendationStore = VetRecommendationStore(context: context)
        let reminderScheduler = MedicationReminderScheduler(scheduler: UNNotificationScheduler())
        let dueScheduler = DueReminderScheduler(scheduler: UNNotificationScheduler())

        return TabView {
            PetProfileView(store: petStore)
                .tabItem { Label("Profile", systemImage: "pawprint") }
            MedicationsListView(medicationStore: medicationStore,
                                doseLogStore: doseLogStore,
                                reminderScheduler: reminderScheduler)
                .tabItem { Label("Meds", systemImage: "pills") }
            VaccinationsListView(store: vaccinationStore,
                                 dueScheduler: dueScheduler)
                .tabItem { Label("Vaccines", systemImage: "syringe") }
            VetVisitsListView(store: vetVisitStore,
                              recommendationStore: recommendationStore,
                              dueScheduler: dueScheduler,
                              cadenceMonths: vetCadenceMonths)
                .tabItem { Label("Vet", systemImage: "stethoscope") }
        }
    }
}
