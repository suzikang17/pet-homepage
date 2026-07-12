// ios/PetHomepage/Features/Settings/HomeLocationPickerView.swift
import CoreLocation
import MapKit
import SwiftUI

/// Map sheet for choosing the home geofence center: tap to drop the pin, or use the
/// one-shot current location.
struct HomeLocationPickerView: View {
    @ObservedObject var permissions: LocationPermissionModel
    let initial: (latitude: Double, longitude: Double)?
    let onSave: ((latitude: Double, longitude: Double)) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker("Home", systemImage: "house.fill", coordinate: pin)
                            .tint(Theme.primary)
                    }
                }
                .onTapGesture { screenPoint in
                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        pin = coordinate
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Home location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let pin {
                            onSave((latitude: pin.latitude, longitude: pin.longitude))
                        }
                        dismiss()
                    }
                    .disabled(pin == nil)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        permissions.requestCurrentLocation()
                    } label: {
                        Label("Use current location", systemImage: "location.fill")
                    }
                }
            }
            .onAppear {
                if let initial {
                    let coordinate = CLLocationCoordinate2D(latitude: initial.latitude,
                                                            longitude: initial.longitude)
                    pin = coordinate
                    camera = .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                }
            }
            .onReceive(permissions.$lastLocation) { location in
                guard let location else { return }
                pin = location
                camera = .region(MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            }
        }
    }
}
