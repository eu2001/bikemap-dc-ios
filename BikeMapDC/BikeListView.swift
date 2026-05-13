import SwiftUI

struct BikeListView: View {
    @ObservedObject var appState: AppState
    @State private var showAddBike   = false
    @State private var editingBike: BikeRow?
    @State private var deletingBike: BikeRow?
    @State private var loading       = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.bikes.isEmpty && !loading {
                    emptyState
                } else {
                    List {
                        ForEach(appState.bikes) { bike in
                            bikeRow(bike)
                        }
                    }
                }
            }
            .navigationTitle("My Bikes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddBike = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                loading = true
                await appState.fetchBikes()
                loading = false
            }
            .sheet(isPresented: $showAddBike) {
                BikeFormView(appState: appState)
            }
            .sheet(item: $editingBike) { bike in
                BikeFormView(appState: appState, existing: bike)
            }
            .alert("Remove bike?", isPresented: .init(
                get: { deletingBike != nil },
                set: { if !$0 { deletingBike = nil } }
            )) {
                Button("Cancel", role: .cancel) { deletingBike = nil }
                Button("Remove", role: .destructive) {
                    if let bike = deletingBike {
                        Task { try? await appState.deleteBike(bike) }
                        deletingBike = nil
                    }
                }
            } message: {
                Text("Tem certeza que deseja remover \"\(deletingBike?.nickname ?? "")\"?")
            }
        }
    }

    // MARK: - Bike row

    private func bikeRow(_ bike: BikeRow) -> some View {
        HStack(spacing: 14) {
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
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(bike.nickname)
                    .font(.headline)
                HStack(spacing: 6) {
                    if !bike.brand.isEmpty {
                        Text(bike.brand)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !bike.color.isEmpty {
                        Label(bike.color, systemImage: "paintbrush.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !bike.aro.isEmpty {
                        Label(bike.aro, systemImage: "circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !bike.serialNumber.isEmpty {
                    Text("S/N: \(bike.serialNumber)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions
            Menu {
                Button {
                    editingBike = bike
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deletingBike = bike
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No bike registered")
                .font(.headline)
            Text("Register your bike to have all the info on hand in case it's stolen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showAddBike = true
            } label: {
                Label("Register my bike", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
