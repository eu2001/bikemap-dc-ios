import SwiftUI
import MapKit

struct AdminView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pendingPOIs: [POI] = []
    @State private var loading      = true
    @State private var processingId: String? = nil
    @State private var processingKind: ProcessKind? = nil
    @State private var rejectingPOI: POI? = nil

    private enum ProcessKind { case approve, reject }

    // Furto reports embed the photo as a "🖼️ <url>" line in the description.
    // Helpers to extract / strip it so the admin can preview the photo.
    private static let photoRegex = try! NSRegularExpression(pattern: "🖼️\\s*(https?://\\S+)")
    fileprivate static func extractPhotoURL(_ text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = photoRegex.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return URL(string: String(text[r]))
    }
    fileprivate static func stripPhotoURL(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return photoRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
            .confirmationDialog(
                "Reject this point?",
                isPresented: Binding(
                    get: { rejectingPOI != nil },
                    set: { if !$0 { rejectingPOI = nil } }
                ),
                titleVisibility: .visible,
                presenting: rejectingPOI
            ) { poi in
                Button("Reject and delete", role: .destructive) {
                    rejectingPOI = nil
                    Task { await reject(poi) }
                }
                Button("Cancel", role: .cancel) { rejectingPOI = nil }
            } message: { _ in
                Text("Permanently removes the point. It will not appear on the map or count toward the contributor's ranking.")
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

            // Photo (extracted from description) — admin needs to see it before approving
            if let photoURL = Self.extractPhotoURL(poi.description) {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    case .success(let img):
                        img.resizable().scaledToFit().cornerRadius(10)
                    case .failure:
                        Label("Photo unavailable", systemImage: "photo.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: 220)
            }

            // Description (with photo URL stripped so the link doesn't show twice)
            let descText = Self.stripPhotoURL(poi.description)
            if !descText.isEmpty {
                Text(descText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            // Author
            Text("Submitted by: \(poi.author)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Action buttons — `.borderless` so SwiftUI treats each Button as
            // its own tap target. Without this, a List row with multiple
            // Buttons routes any tap to the first one (Reject).
            HStack(spacing: 10) {
                Button {
                    rejectingPOI = poi
                } label: {
                    if processingId == poi.id && processingKind == .reject {
                        ProgressView()
                            .tint(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Label("Reject", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(processingId != nil)

                Button {
                    Task { await approve(poi) }
                } label: {
                    if processingId == poi.id && processingKind == .approve {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.borderless)
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
        processingKind = .approve
        do {
            try await appState.approvePOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Could not approve. Try again.")
        }
        processingId = nil
        processingKind = nil
    }

    private func reject(_ poi: POI) async {
        processingId = poi.id
        processingKind = .reject
        do {
            try await appState.rejectPOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Could not reject. Try again.")
        }
        processingId = nil
        processingKind = nil
    }
}
