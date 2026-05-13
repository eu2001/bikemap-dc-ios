import SwiftUI
import PhotosUI

struct BikeFormView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Pass nil for a new bike, or an existing BikeRow to edit
    var existing: BikeRow?

    @State private var nickname     = ""
    @State private var brand        = ""
    @State private var color        = ""
    @State private var aro          = ""
    @State private var serialNumber = ""
    @State private var details      = ""
    @State private var bikeType     = "conventional"

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData:     Data?
    @State private var photoImage:    UIImage?

    @State private var loading = false
    @State private var error   = ""

    private var isEditing: Bool { existing != nil }

    // Aro presets
    private let aroOptions = ["20\"", "24\"", "26\"", "27.5\"", "29\"", "700c", "Other"]

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Photo
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else if let url = existing?.imageUrl.flatMap(URL.init) {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 120, height: 120)
                                    .overlay {
                                        Image(systemName: "bicycle")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(Color.blue, in: Circle())
                            }
                            .offset(x: 44, y: 44)
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // MARK: Basic info
                Section("Identification") {
                    TextField("Bike nickname *", text: $nickname)
                    Picker("Type", selection: $bikeType) {
                        Text("Conventional").tag("conventional")
                        Text("E-bike").tag("ebike")
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                    TextField("Brand (e.g. Trek, Specialized, Cannondale…)", text: $brand)
                    TextField("Color", text: $color)
                    Picker("Wheel size", selection: $aro) {
                        Text("Select").tag("")
                        ForEach(aroOptions, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Security") {
                    TextField("Serial number", text: $serialNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section("Additional details") {
                    TextField("E.g. marks, stickers, special components…",
                              text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !error.isEmpty {
                    Section {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text(isEditing ? "Save changes" : "Register bike")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                    .listRowBackground(Color.blue)
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle(isEditing ? "Editar Bike" : "Nova Bike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { prefill() }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        photoData  = data
                        photoImage = UIImage(data: data)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func prefill() {
        guard let b = existing else { return }
        nickname     = b.nickname
        brand        = b.brand
        color        = b.color
        aro          = b.aro
        serialNumber = b.serialNumber
        details      = b.details
        bikeType     = b.bikeType.isEmpty ? "conventional" : b.bikeType
    }

    private func save() async {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        error = ""; loading = true
        defer { loading = false }
        do {
            if var b = existing {
                b.nickname     = name
                b.brand        = brand
                b.color        = color
                b.aro          = aro
                b.serialNumber = serialNumber
                b.details      = details
                b.bikeType     = bikeType
                try await appState.updateBike(b, imageData: photoData)
            } else {
                try await appState.addBike(nickname: name, brand: brand, color: color,
                                           aro: aro, serialNumber: serialNumber,
                                           details: details, bikeType: bikeType,
                                           imageData: photoData)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
