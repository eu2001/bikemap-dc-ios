import SwiftUI
import MapKit

struct AdminView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pendingPOIs: [POI] = []
    @State private var loading      = true
    @State private var processingId: String? = nil
    @State private var editingPOI: POI? = nil

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading pending points…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pendingPOIs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("No pending points")
                            .font(.headline)
                        Text("All points have been reviewed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("\(pendingPOIs.count) point(s) awaiting review") {
                            ForEach(pendingPOIs) { poi in
                                poiCard(poi)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await reload() }
            .sheet(item: $editingPOI) { poi in
                AdminEditPOISheet(appState: appState, poi: poi) { updated in
                    // Replace the row in our local pending list with the
                    // edited values so the card refreshes.
                    if let idx = pendingPOIs.firstIndex(where: { $0.id == updated.id }) {
                        pendingPOIs[idx] = updated
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - POI card

    private func poiCard(_ poi: POI) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack(spacing: 10) {
                Text(poi.poiType.emoji)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color(poi.poiType.uiColor).opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(poi.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(poi.poiType.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let date = poi.createdAt {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if processingId == poi.id {
                    ProgressView()
                }
            }

            // Mini map
            Map(position: .constant(.region(MKCoordinateRegion(
                center: poi.coordinate,
                span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )))) {
                Marker("", coordinate: poi.coordinate)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(true)

            // Description
            if !poi.description.isEmpty {
                Text(poi.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            // Author
            Text("Submitted by: \(poi.author)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Edit button (full width, above approve/reject)
            Button {
                editingPOI = poi
            } label: {
                Label("Edit before approving", systemImage: "pencil.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.blue)
            }
            .disabled(processingId != nil)

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    Task { await reject(poi) }
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.red)
                }
                .disabled(processingId != nil)

                Button {
                    Task { await approve(poi) }
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .disabled(processingId != nil)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        pendingPOIs = await appState.fetchPendingPOIs()
        loading = false
    }

    private func approve(_ poi: POI) async {
        processingId = poi.id
        do {
            try await appState.approvePOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Could not approve. Try again.")
        }
        processingId = nil
    }

    private func reject(_ poi: POI) async {
        processingId = poi.id
        do {
            try await appState.rejectPOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Could not reject. Try again.")
        }
        processingId = nil
    }
}

// MARK: - Edit Sheet
//
// Lets the admin fix the title / description and drag the map to relocate
// the pin before approving.

private struct AdminEditPOISheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let poi: POI
    let onSaved: (POI) -> Void

    @State private var title:       String
    @State private var description: String
    @State private var coord:       CLLocationCoordinate2D
    @State private var mapPosition: MapCameraPosition
    @State private var saving       = false
    @State private var errorMsg     = ""

    init(appState: AppState, poi: POI, onSaved: @escaping (POI) -> Void) {
        self.appState = appState
        self.poi = poi
        self.onSaved = onSaved
        _title       = State(initialValue: poi.title)
        _description = State(initialValue: poi.description)
        _coord       = State(initialValue: poi.coordinate)
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(
            center: poi.coordinate,
            span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ZStack {
                        Map(position: $mapPosition)
                            .onMapCameraChange(frequency: .continuous) { context in
                                coord = context.region.center
                            }
                        VStack(spacing: 0) {
                            Image(systemName: "mappin")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.red)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            Spacer().frame(height: 30)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .padding(.horizontal, -4)

                    Text("Drag the map to fine-tune the pin location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Location")
                }

                Section("Point type") {
                    Label {
                        Text(poi.poiType.label).foregroundStyle(.primary)
                    } icon: {
                        Text(poi.poiType.emoji)
                    }
                }

                Section("Info") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            errorMsg = "Title cannot be empty."
            return
        }
        saving = true; errorMsg = ""
        do {
            try await appState.updatePOIContent(
                poi,
                title: trimmedTitle,
                description: description,
                lat: coord.latitude,
                lng: coord.longitude,
            )
            let updated = POI(
                id: poi.id, type: poi.type,
                lat: coord.latitude, lng: coord.longitude,
                title: trimmedTitle, description: description,
                author: poi.author, createdAt: poi.createdAt
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMsg = "Could not save. Please try again."
        }
        saving = false
    }
}
