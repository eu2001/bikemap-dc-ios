import SwiftUI
import MapKit

struct AddPointView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: POIType = .secure_parking

    // Live coordinate the user can fine-tune by panning the mini map.
    @State private var pinCoordinate: CLLocationCoordinate2D
    @State private var mapPosition:    MapCameraPosition
    @State private var title       = ""
    @State private var description = ""
    @State private var outOfBounds = false

    init(appState: AppState) {
        self.appState = appState
        let initial = appState.pendingAddCoordinate ?? DCBounds.defaultCenter
        _pinCoordinate = State(initialValue: initial)
        _mapPosition   = State(initialValue: .region(MKCoordinateRegion(
            center: initial,
            span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )))
        _selectedType  = State(initialValue: appState.pendingPOIType ?? .secure_parking)
    }

    // Type is always pre-selected before AddPointView opens
    private var generalTypes: [POIType] {
        POIType.allCases.filter { $0.canContribute && $0 != .furto && $0 != .acidente_ferido }
    }

    var body: some View {
        NavigationStack {
            Form {

                Section {
                    // Live coordinate readout
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        Text(String(format: "%.5f, %.5f", pinCoordinate.latitude, pinCoordinate.longitude))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if outOfBounds {
                        Label(SJCBounds.outOfBoundsMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    // Interactive mini map: drag to position the pin.
                    ZStack {
                        Map(position: $mapPosition)
                            .mapStyle(.standard(elevation: .flat))
                            .onMapCameraChange(frequency: .continuous) { context in
                                pinCoordinate = context.region.center
                                outOfBounds   = !SJCBounds.contains(pinCoordinate)
                            }

                        // Fixed center pin — its tip points to the map center.
                        VStack(spacing: 0) {
                            Image(systemName: "mappin")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.red)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            // Spacer below to anchor pin tip at the map center.
                            Spacer().frame(height: 30)
                        }
                        .allowsHitTesting(false)

                        // Faint crosshair so the user knows the pin marks the exact map center.
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                            .frame(width: 6, height: 6)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .padding(.horizontal, -4)

                    Text("Drag the map to move the pin to the exact location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Selected location")
                }

                Section("Point type") {
                    Label {
                        Text(selectedType.label).foregroundStyle(.primary)
                    } icon: {
                        Text(selectedType.emoji)
                    }
                }

                Section("Info") {
                    TextField("Title *", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Text(selectedType.emoji)
                            Text("Add \(selectedType.label)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespaces).isEmpty || outOfBounds
                    )
                }
            }
            .navigationTitle("New Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func submit() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard SJCBounds.contains(pinCoordinate) else { outOfBounds = true; return }
        appState.addPOI(
            type: selectedType,
            coordinate: pinCoordinate,
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces)
        )
        appState.pendingAddCoordinate = nil
        appState.pendingPOIType = nil
        dismiss()
    }
}
