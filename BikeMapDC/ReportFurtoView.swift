import SwiftUI
import PhotosUI
import MapKit

struct ReportFurtoView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var incidentDate    = Date()
    @State private var description     = ""
    @State private var contact         = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoUIImage: UIImage?
    @State private var loading          = false
    @State private var error            = ""
    @State private var showConfirmAlert = false
    @State private var selectedBike: BikeRow?
    @State private var outOfBounds      = false

    private var coordinate: CLLocationCoordinate2D? { appState.pendingAddCoordinate }
    private var isRecent: Bool { Date().timeIntervalSince(incidentDate) < 2 * 24 * 3600 }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Location
                Section("Incident location") {
                    if let coord = coordinate {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                            Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: coord,
                            span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
                        )))) {
                            Marker("", coordinate: coord)
                        }
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .padding(.horizontal, -4)
                        if outOfBounds {
                            Label(SJCBounds.outOfBoundsMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Label("No location selected", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                // MARK: Bike selector (if user has registered bikes)
                if !appState.bikes.isEmpty {
                    Section {
                        Picker("Selecionar bike", selection: $selectedBike) {
                            Text("None selected").tag(Optional<BikeRow>.none)
                            ForEach(appState.bikes) { bike in
                                Text(bike.nickname + (bike.brand.isEmpty ? "" : " (\(bike.brand))"))
                                    .tag(Optional(bike))
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedBike) { _, bike in
                            guard let bike else { return }
                            // Auto-fill description with bike details
                            var parts: [String] = []
                            if !bike.brand.isEmpty  { parts.append("Marca: \(bike.brand)") }
                            if !bike.color.isEmpty  { parts.append("Cor: \(bike.color)") }
                            if !bike.aro.isEmpty    { parts.append("Aro: \(bike.aro)") }
                            if !bike.serialNumber.isEmpty { parts.append("S/N: \(bike.serialNumber)") }
                            if !bike.details.isEmpty { parts.append(bike.details) }
                            description = parts.joined(separator: "\n")
                        }

                        if let bike = selectedBike {
                            HStack(spacing: 12) {
                                // Thumbnail
                                Group {
                                    if let urlStr = bike.imageUrl, let url = URL(string: urlStr) {
                                        AsyncImage(url: url) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Color(.systemGray5)
                                        }
                                    } else {
                                        Color(.systemGray5)
                                            .overlay {
                                                Image(systemName: "bicycle")
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bike.nickname).font(.subheadline.weight(.semibold))
                                    HStack(spacing: 4) {
                                        if !bike.brand.isEmpty { Text(bike.brand).font(.caption).foregroundStyle(.secondary) }
                                        if !bike.color.isEmpty { Text("· \(bike.color)").font(.caption).foregroundStyle(.secondary) }
                                        if !bike.aro.isEmpty   { Text("· \(bike.aro)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    if !bike.serialNumber.isEmpty {
                                        Text("S/N: \(bike.serialNumber)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Stolen bike")
                    } footer: {
                        Text("Select a registered bike to autofill the details.")
                            .font(.caption)
                    }
                }

                // MARK: Date & Time
                Section("Date and time") {
                    DatePicker("Date and time of the incident",
                               selection: $incidentDate,
                               in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }

                // MARK: Description
                Section("Incident description") {
                    TextField("Describe what happened, bike features, suspects, etc.",
                              text: $description, axis: .vertical)
                        .lineLimit(4...8)
                }

                // MARK: Photo
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoUIImage == nil ? "Add bike photo" : "Replace photo",
                              systemImage: "photo.badge.plus")
                    }
                    if let photoUIImage {
                        Image(uiImage: photoUIImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .listRowInsets(.init(top: 8, leading: 8, bottom: 8, trailing: 8))
                        Button(role: .destructive) {
                            self.photoUIImage = nil
                            self.photoData    = nil
                            self.selectedPhoto = nil
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Bike photo (optional)")
                }

                // MARK: Contact (required so the community can reach the owner)
                Section("Contact info *") {
                    TextField("Phone or email — required", text: $contact)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                // MARK: Error
                if !error.isEmpty {
                    Section {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // MARK: Submit
                Section {
                    Button {
                        // Only offer community alert if incident was within the last 2 days
                        if isRecent {
                            showConfirmAlert = true
                        } else {
                            Task { await submit() }
                        }
                    } label: {
                        Group {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Label("Report Theft", systemImage: "lock.open.fill")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(
                        description.trimmingCharacters(in: .whitespaces).isEmpty
                        || contact.trimmingCharacters(in: .whitespaces).isEmpty
                        || coordinate == nil || loading || outOfBounds
                    )
                    .listRowBackground(Color.red)
                    .foregroundStyle(.white)
                }
                .alert("Alert the community?", isPresented: $showConfirmAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Yes, alert", role: .destructive) {
                        Task { await submit() }
                    }
                } message: {
                    Text("If the theft happened less than 24h ago, all BikeMap community members will be notified about this bike theft in the area.")
                }
            }
            .navigationTitle("Report Theft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: coordinate?.latitude) { _, _ in
            if let coord = coordinate {
                outOfBounds = !SJCBounds.contains(coord)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoData    = data
                    photoUIImage = UIImage(data: data)
                }
            }
        }
    }

    // MARK: - Submit

    private func submit() async {
        guard let coord = coordinate else { return }
        guard SJCBounds.contains(coord) else { outOfBounds = true; return }
        let desc = description.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return }
        let contactTrim = contact.trimmingCharacters(in: .whitespaces)
        guard !contactTrim.isEmpty else {
            error = String(localized: "Contact info is required so the community can reach you.")
            return
        }

        error = ""; loading = true
        defer { loading = false }

        // Format date/time
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: incidentDate)

        // Upload photo if present
        var imageURL: String? = nil
        if let photoData {
            imageURL = await appState.uploadFurtoPhoto(photoData)
        }

        // Build description block
        var fullDesc = "📅 \(dateStr)\n📝 \(desc)"
        if let contact = contact.trimmingCharacters(in: .whitespaces).nonEmpty {
            fullDesc += "\n📞 \(contact)"
        }
        if let url = imageURL {
            fullDesc += "\n🖼️ \(url)"
        }

        let poiTitle: String
        if let bike = selectedBike {
            poiTitle = String(localized: "Theft: \(bike.nickname)")
        } else {
            poiTitle = String(localized: "Bike Theft")
        }

        appState.addPOI(
            type: .furto,
            coordinate: coord,
            title: poiTitle,
            description: fullDesc
        )

        appState.pendingAddCoordinate = nil
        appState.pendingPOIType = nil
        dismiss()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
