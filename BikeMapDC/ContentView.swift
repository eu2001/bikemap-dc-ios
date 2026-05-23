import SwiftUI
import MapKit
import CoreLocation
import Combine

struct ContentView: View {
    @ObservedObject var appState: AppState
    @StateObject private var locationManager = LocationManager()
    @StateObject private var network = NetworkMonitor()
    @State private var showContact = false

    var body: some View {
        ZStack(alignment: .top) {

            // MARK: Map (full screen)
            BikeMapView(appState: appState)
                .ignoresSafeArea()
                .task {
                    await appState.fetchInfraFeatures()
                }

            // MARK: Picking mode banner
            if appState.mapPickingMode != nil {
                pickingBanner
            }

            // MARK: Header
            header
                .padding(.top, topSafeArea)

            // MARK: Unread community-alert banner
            if !appState.unreadAlerts.isEmpty {
                VStack {
                    Spacer().frame(height: topSafeArea + 56)
                    unreadAlertBanner
                    Spacer()
                }
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: appState.unreadAlerts.count)
                .zIndex(3)
            }

            // MARK: Offline banner
            if !network.isConnected {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.subheadline.weight(.semibold))
                        Text("Offline — the map may be outdated")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange, ignoresSafeAreaEdges: [])
                    Spacer()
                }
                .padding(.top, topSafeArea + 56)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: network.isConnected)
                .zIndex(2)
            }

            // MARK: Floating controls (right side)
            VStack {
                Spacer()
                floatingControls
                    .padding(.bottom, 30)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .ignoresSafeArea(edges: .bottom)

            // MARK: Furto banner (in-app alert when an admin approves a recent stolen-bike POI)
            if let banner = appState.furtoBanner {
                VStack {
                    furtoBannerView(banner)
                        .padding(.top, topSafeArea + 4)
                        .padding(.horizontal, 12)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appState.furtoBanner)
                .zIndex(50)
            }

            // MARK: Toast
            if let msg = appState.toastMessage {
                VStack {
                    Spacer()
                    toastView(msg)
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: appState.toastMessage)
            }

            // MARK: Sidebar dim overlay
            if appState.showSidebar {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            appState.showSidebar = false
                        }
                    }
            }

            // MARK: Sidebar drawer (slides in from left)
            HStack(spacing: 0) {
                LayersPanelView(appState: appState)
                    .frame(width: 300)
                    .padding(.vertical, 60)
                    .contentShape(Rectangle())
                Spacer()
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .offset(x: appState.showSidebar ? 0 : -300)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.showSidebar)
            .allowsHitTesting(appState.showSidebar)

            // MARK: Left-edge tap zone (opens sidebar)
            if !appState.showSidebar {
                HStack {
                    Color.clear
                        .frame(width: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                appState.showSidebar = true
                            }
                        }
                    Spacer()
                }
                .ignoresSafeArea()
            }

            // MARK: Legend overlay
            if appState.showLegend {
                VStack {
                    Spacer()
                    LegendView(appState: appState)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
                .animation(.spring(response: 0.3), value: appState.showLegend)
            }
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $appState.showRanking)      { RankingView(appState: appState) }
        .sheet(isPresented: $appState.showAuth)         { AuthView(appState: appState) }
        .sheet(isPresented: $appState.showAddPoint) {
            if appState.pendingPOIType == .furto {
                ReportFurtoView(appState: appState)
            } else {
                AddPointView(appState: appState)
            }
        }
        .sheet(item: $appState.selectedPOI)             { poi in POIDetailView(poi: poi, appState: appState) }
        .sheet(isPresented: $showContact)               { ContactView() }
        .onReceive(locationManager.$authorizationStatus) { _ in }
        // Open POI detail when user taps a push notification
        .onChange(of: appState.notificationTargetPOI) { _, poi in
            guard let poi else { return }
            appState.shouldCenterOnUser = false
            appState.selectedPOI = poi
            appState.notificationTargetPOI = nil
        }
    }

    // MARK: - Unread alert banner

    @ViewBuilder
    private var unreadAlertBanner: some View {
        VStack(spacing: 6) {
            ForEach(appState.unreadAlerts.prefix(3)) { alert in
                Button {
                    Task { await appState.openAlert(alert) }
                } label: {
                    HStack(spacing: 10) {
                        Text("🚨").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("Tap to see the location")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Header bar

    private var header: some View {
        HStack(spacing: 8) {
            Button { withAnimation { appState.showSidebar.toggle() } } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            Button { showContact = true } label: {
                Image("logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(.systemGray3), lineWidth: 2)
                    )
            }

            Spacer()

            Button { appState.showRanking = true } label: {
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                            .padding(2)
                    )
            }

            if let name = appState.currentUserName {
                Button { appState.showAuth = true } label: {
                    AvatarView(id: appState.currentUser?.avatar ?? "bobcat", size: 38)
                }
                .overlay(alignment: .topTrailing) {
                    if appState.currentUser?.isPremium == true {
                        Text("⭐").font(.system(size: 10)).offset(x: 4, y: -4)
                    }
                    // Red dot when there are pending POIs for the admin to review.
                    if appState.isAdmin && appState.pendingPOICount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }
                let _ = name  // suppress warning
            } else {
                Button {
                    // Guest tapping "Sign in" returns to the welcome screen
                    // (with sign-in / create-account / browse-as-guest).
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.guestAccess = false
                    }
                } label: {
                    Text("Sign in")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Floating controls

    private var floatingControls: some View {
        VStack(spacing: 10) {
            mapButton(icon: "location.fill") {
                locationManager.requestLocation()
                appState.shouldCenterOnUser = true
            }

            mapButton(icon: "plus.magnifyingglass") {
                appState.zoomDelta = 1
            }

            mapButton(icon: "minus.magnifyingglass") {
                appState.zoomDelta = -1
            }
        }
    }

    private func mapButton(icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        }
    }

    // MARK: - Picking banner

    private var pickingBanner: some View {
        VStack {
            Spacer().frame(height: topSafeArea + 64)
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill").foregroundStyle(.white)
                Text(pickingModeLabel).foregroundStyle(.white).font(.subheadline).fontWeight(.medium)
                Spacer()
                Button("Cancel") {
                    appState.mapPickingMode = nil
                }
                .foregroundStyle(.white.opacity(0.85))
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: appState.mapPickingMode != nil)
    }

    private var pickingModeLabel: String {
        switch appState.mapPickingMode {
        case .addPoint: return String(localized: "Tap the map to add a point")
        case .none:     return ""
        }
    }

    // MARK: - Furto banner

    private func furtoBannerView(_ banner: AppState.FurtoBanner) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("🚨")
                .font(.system(size: 28))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(banner.body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { appState.furtoBanner = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Color(red: 0.85, green: 0.15, blue: 0.15),
                                    Color(red: 0.65, green: 0.05, blue: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            // Open the POI by injecting it through selectedPOI.
            if let poi = appState.pois.first(where: { $0.id == banner.poiId }) {
                appState.selectedPOI = poi
            } else {
                // POI not in local array yet (the realtime UPDATE arrived first);
                // synthesise a minimal POI so the detail sheet still opens.
                appState.selectedPOI = POI(
                    id: banner.poiId, type: POIType.furto.rawValue,
                    lat: banner.lat, lng: banner.lng,
                    title: banner.title, description: banner.body,
                    author: "", createdAt: Date()
                )
            }
            appState.furtoBanner = nil
        }
        .task(id: banner.id) {
            // Auto-dismiss after 6 seconds if the user doesn't interact.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if appState.furtoBanner?.id == banner.id {
                withAnimation { appState.furtoBanner = nil }
            }
        }
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
    }

    // MARK: - Safe area helper

    private var topSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }
}

// MARK: - Legend View

struct LegendView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Legend").font(.headline)
                Spacer()
                Button { withAnimation { appState.showLegend = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            Text("Infrastructure").font(.caption).foregroundStyle(.secondary).fontWeight(.semibold)
            ForEach(InfraType.allCases, id: \.rawValue) { type in
                HStack(spacing: 8) {
                    legendLine(color: type.color, dashed: type.dashPattern != nil)
                    Text(type.label).font(.caption)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Points of Interest").font(.caption).foregroundStyle(.secondary).fontWeight(.semibold)
            let poiRows = POIType.allCases.chunked(into: 2)
            ForEach(0..<poiRows.count, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(poiRows[row], id: \.rawValue) { type in
                        HStack(spacing: 4) {
                            Text(type.emoji).font(.caption)
                            Text(type.label).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.15), radius: 8)
    }

    private func legendLine(color: Color, dashed: Bool) -> some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: .init(x: 0, y: size.height / 2))
            path.addLine(to: .init(x: size.width, y: size.height / 2))
            ctx.stroke(path, with: .color(color), style: .init(lineWidth: 3,
                dash: dashed ? [6, 4] : []))
        }
        .frame(width: 28, height: 14)
    }
}

// MARK: - POI Detail Sheet

struct POIDetailView: View {
    let poi: POI
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var deleting = false

    private var currentPOI: POI {
        appState.pois.first(where: { $0.id == poi.id }) ?? poi
    }

    /// Splits the description into (text-without-photo-line, photoURL?).
    /// Furto reports embed the photo as a "🖼️ <url>" line in the description.
    private func extractPhoto(_ text: String) -> (String, URL?) {
        let pattern = "🖼️\\s*(https?://\\S+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, nil) }
        let range = NSRange(text.startIndex..., in: text)
        var photoURL: URL? = nil
        if let m = regex.firstMatch(in: text, range: range),
           let r = Range(m.range(at: 1), in: text) {
            photoURL = URL(string: String(text[r]))
        }
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stripped, photoURL)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Text(currentPOI.poiType.emoji).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentPOI.poiType.label).font(.caption).foregroundStyle(.secondary)
                            Text(currentPOI.title).font(.headline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                let (descNoPhoto, photoURL) = extractPhoto(currentPOI.description)

                if let photoURL {
                    Section("Photo") {
                        AsyncImage(url: photoURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                            case .success(let img):
                                img.resizable().scaledToFit().cornerRadius(8)
                            case .failure:
                                Label("Could not load photo", systemImage: "photo.badge.exclamationmark")
                                    .foregroundStyle(.secondary)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }

                if !descNoPhoto.isEmpty {
                    Section("Description") {
                        Text(descNoPhoto)
                    }
                }

                Section("Contribution") {
                    Label("By: \(currentPOI.author == "admin" ? "BikeMap Team" : currentPOI.author)", systemImage: "person.circle")
                }

                // Admin-only delete tile.
                if appState.isAdmin {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Label("Delete point", systemImage: "trash")
                                Spacer()
                                if deleting { ProgressView() }
                            }
                        }
                        .disabled(deleting)
                    } header: {
                        Text("Danger zone")
                    } footer: {
                        Text("Removes this point from the map for all users.")
                    }
                }

            }
            .navigationTitle("Map Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if appState.isAdmin {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showEdit = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                AdminEditPOIView(poi: currentPOI, appState: appState)
            }
            .alert("Delete this point?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        deleting = true
                        try? await appState.adminDeletePOI(currentPOI)
                        deleting = false
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently remove “\(currentPOI.title)” from the map. This action cannot be undone.")
            }
            // Once the user actually sees the theft details, clear the
            // unread badge on the app icon.
            .onAppear {
                if currentPOI.poiType == .furto { AppDelegate.clearBadge() }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Admin: edit POI title/description

struct AdminEditPOIView: View {
    let poi: POI
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var loading = false
    @State private var error = ""

    init(poi: POI, appState: AppState) {
        self.poi = poi
        self.appState = appState
        _title = State(initialValue: poi.title)
        _description = State(initialValue: poi.description)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 140)
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
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
                        if loading { ProgressView() } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        let newTitle = title.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty else {
            error = String(localized: "Title cannot be empty.")
            return
        }
        loading = true; error = ""
        defer { loading = false }
        do {
            try await appState.updatePOIContent(poi, title: newTitle, description: description)
            dismiss()
        } catch {
            self.error = String(localized: "Could not save. Please try again.")
        }
    }
}

// MARK: - Array chunk helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
