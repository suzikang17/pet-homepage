// ios/PetHomepage/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        PetProfileView(store: PetStore(context: context))
    }
}
