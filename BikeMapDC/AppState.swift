import Foundation
import MapKit
import Combine
import Supabase
import UserNotifications
import AVFoundation

class AppState: ObservableObject {

    // MARK: - Auth

    @Published var currentUserName: String?
    @Published var currentUserId: UUID?
    @Published var currentProfile: ProfileRow?
    @Published var selectedBikeId: String? = UserDefaults.standard.string(forKey: "selectedBikeId") {
        didSet { UserDefaults.standard.set(selectedBikeId, forKey: "selectedBikeId") }
    }

    var selectedBike: BikeRow? {
        guard let id = selectedBikeId else { return nil }
        return bikes.first { $0.id.uuidString == id }
    }

    // MARK: - Data

    @Published var pois:           [POI]              = []
    @Published var bikes:          [BikeRow]          = []
    @Published var userPOIs:       [POI]              = []
    @Published var infraFeatures:  [BikeInfraFeature] = []
    /// Count of POIs awaiting admin review. Drives the red-dot badge on the
    /// avatar + the "Administrator Panel" row in My Profile.
    @Published var pendingPOICount: Int = 0

    /// Latest known user location (updated by BikeMapView). Used to gate
    /// contributions to people physically in/near DC.
    @Published var lastKnownUserLocation: CLLocationCoordinate2D?

    /// Maximum distance from the Washington Monument where a user may add
    /// new points or reports (5 miles).
    static let contributionRadiusMeters: Double = 5 * 1609.34
    static let dcCenter = CLLocationCoordinate2D(latitude: 38.8895, longitude: -77.0353)

    /// True if the user is currently within `contributionRadiusMeters` of
    /// DC. Returns false if we don't have a location fix yet — that's safer
    /// than silently allowing remote submissions.
    var userIsInContributionArea: Bool {
        guard let loc = lastKnownUserLocation else { return false }
        let from = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        let dc = CLLocation(latitude: AppState.dcCenter.latitude,
                            longitude: AppState.dcCenter.longitude)
        return from.distance(from: dc) <= AppState.contributionRadiusMeters
    }

    // MARK: - Layer visibility

    @Published var layerVisibility: [String: Bool] = {
        var v: [String: Bool] = [:]
        // All categories on by default EXCEPT unpaved trail and mountain bike trail.
        let defaultOnInfra: Set<InfraType> = [
            .protected_lane, .bike_lane, .contraflow_lane, .bus_bike_lane,
            .shared_lane, .signed_route, .off_street_trail,
        ]
        InfraType.allCases.forEach { v[$0.rawValue] = defaultOnInfra.contains($0) }
        let defaultOnPOI: Set<POIType> = [.capital_bikeshare, .secure_parking, .fixit_stand]
        POIType.allCases.forEach { v[$0.rawValue] = defaultOnPOI.contains($0) }
        return v
    }()

    // MARK: - UI state

    /// True when the user chose "Browse the map without an account" on the
    /// welcome screen. Required by Apple guideline 5.1.1(v) — non-account
    /// features (just viewing the map) must be available without sign-in.
    /// Cleared automatically when a sign-in / sign-up succeeds.
    @Published var guestAccess       = false
    @Published var showSidebar       = false
    @Published var showLegend        = false
    @Published var showRanking       = false
    @Published var showAuth          = false
    @Published var showAddPoint      = false
    @Published var showReportFurto   = false
    @Published var selectedPOI: POI?
    @Published var mapPickingMode: MapPickingMode?
    @Published var pendingAddCoordinate: CLLocationCoordinate2D?
    @Published var pendingPOIType: POIType?
    @Published var shouldCenterOnUser    = false
    /// One-shot map recenter target. BikeMapView observes and clears it.
    @Published var centerOnCoordinate: CLLocationCoordinate2D? = nil
    @Published var notificationTargetPOI: POI? = nil

    struct UnreadAlert: Identifiable {
        let id: UUID
        let poiId: String
        let title: String
        let body: String
        let lat: Double?
        let lng: Double?
    }
    @Published var unreadAlerts: [UnreadAlert] = []

    /// One-shot in-app banner shown when an admin approves a recent furto POI
    /// while this user has the app open. Tapping it opens the POI; otherwise
    /// it auto-dismisses after ~5 seconds. The crow-caw sound plays once on
    /// arrival so the alert is hard to miss even on silent ringer.
    struct FurtoBanner: Identifiable, Equatable {
        let id = UUID()
        let poiId: String
        let title: String
        let body: String
        let lat: Double
        let lng: Double
    }
    @Published var furtoBanner: FurtoBanner? = nil
    private var furtoSoundPlayer: AVAudioPlayer?

    struct NotificationEntry: Identifiable, Decodable {
        let id: UUID
        let type: String
        let poi_id: String?
        let title: String
        let body: String?
        let lat: Double?
        let lng: Double?
        let read_at: Date?
        let created_at: Date
    }
    @Published var notifications: [NotificationEntry] = []
    @Published var zoomDelta: Double     = 0   // +1 = zoom in, -1 = zoom out

    // MARK: - Toast

    @Published var toastMessage: String?
    private var toastTimer: Timer?

    // MARK: - Realtime

    private var realtimeTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        Task { await restoreSession() }
        startFurtoListener()
    }

    deinit { realtimeTask?.cancel() }

    private func startFurtoListener() {
        realtimeTask = Task {
            let channel = supabase.channel("furto-alerts")
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "pois")
            await channel.subscribe()
            for await change in changes {
                switch change {
                case .insert(let action):
                    let record = action.record
                    guard let type = record["type"]?.stringValue, type == "furto",
                          let authorId = record["author_id"]?.stringValue else { continue }
                    // Don't notify the user who just reported it
                    await MainActor.run {
                        if authorId != self.currentUserId?.uuidString {
                            self.showToast(String(localized: "🔓 New bike theft reported in the area! Stay alert."))
                        }
                    }

                case .update(let action):
                    // Admin just approved a furto: status flipped pending→approved.
                    // Show the in-app banner + crow-caw sound for everyone except
                    // the author and (optionally) the approving admin themselves.
                    let new = action.record
                    let old = action.oldRecord
                    guard let type = new["type"]?.stringValue, type == "furto",
                          let newStatus = new["status"]?.stringValue, newStatus == "approved",
                          let oldStatus = old["status"]?.stringValue, oldStatus != "approved" else { continue }

                    let poiId   = new["id"]?.stringValue ?? ""
                    let authorId = new["author_id"]?.stringValue
                    let title   = new["title"]?.stringValue ?? String(localized: "🚨 Stolen bike reported nearby")
                    let descRaw = new["description"]?.stringValue ?? ""
                    // Strip the "🖼️ <url>" line so it doesn't show as a raw link in the banner.
                    let body    = descRaw.replacingOccurrences(
                        of: "🖼️\\s*https?://\\S+", with: "", options: .regularExpression
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    let lat = Double(new["lat"]?.stringValue ?? "") ?? 0
                    let lng = Double(new["lng"]?.stringValue ?? "") ?? 0

                    // Only enforce the 24-h window if incident_at is present.
                    var isRecent = true
                    if let incStr = new["incident_at"]?.stringValue,
                       let incidentAt = ISO8601DateFormatter().date(from: incStr) {
                        isRecent = Date().timeIntervalSince(incidentAt) <= 24 * 60 * 60
                    }

                    await MainActor.run {
                        guard isRecent else { return }
                        if authorId == self.currentUserId?.uuidString { return }
                        let banner = FurtoBanner(poiId: poiId, title: title,
                                                 body: body.isEmpty ? title : body,
                                                 lat: lat, lng: lng)
                        self.furtoBanner = banner
                        self.playFurtoSound()
                    }

                default:
                    continue
                }
            }
        }
    }

    /// Plays the 2-second crow caw bundled at the app root. Mixes with other
    /// audio (music, podcasts) and ducks them briefly so the alert is audible
    /// without stopping playback.
    func playFurtoSound() {
        guard let url = Bundle.main.url(forResource: "crow_caw", withExtension: "caf") else {
            print("playFurtoSound: crow_caw.caf not found in bundle")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                             options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            furtoSoundPlayer = p
            DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.2) { [weak self] in
                self?.furtoSoundPlayer = nil
                try? AVAudioSession.sharedInstance().setActive(
                    false, options: [.notifyOthersOnDeactivation]
                )
            }
        } catch {
            print("playFurtoSound error: \(error)")
        }
    }

    // MARK: - Session restore

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                self.currentUserId = session.user.id
            }
            await fetchProfile(userId: session.user.id)
            await MainActor.run { self.requestPushPermission() }
        } catch {
            // No active session — show welcome screen
        }
        // Always load POIs — the table is publicly readable
        await fetchPOIs()
        // If this user is an admin, prime the pending-count badge.
        await refreshPendingCount()
        // After POIs are loaded, surface any unread theft alert.
        await openLatestUnreadFurtoIfAny()
    }

    // MARK: - Auth

    func register(email: String, password: String, username: String, avatar: String) async throws {
        // Call edge function so we can validate username uniqueness server-side
        struct RegisterBody: Encodable {
            let email, password, username, avatar: String
        }
        struct RegisterResponse: Decodable {
            let error: String?
        }

        let url = URL(string: "https://hobulqkujiczaakaucwz.supabase.co/functions/v1/register-user")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(RegisterBody(email: email, password: password,
                                                             username: username, avatar: avatar))
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 201 {
            let body = try JSONDecoder().decode(RegisterResponse.self, from: data)
            throw AppError.message(body.error ?? String(localized: "Could not create account."))
        }

        // Now sign in
        try await signIn(email: email, password: password)
        await MainActor.run { showToast(String(localized: "🎉 Account created! Welcome, \(username)!")) }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        await MainActor.run {
            self.currentUserId = session.user.id
            self.guestAccess = false
        }
        await fetchProfile(userId: session.user.id)
        await fetchPOIs()
        await MainActor.run { self.requestPushPermission() }
        await openLatestUnreadFurtoIfAny()
    }

    func logout() {
        Task {
            try? await supabase.auth.signOut()
            await MainActor.run {
                self.currentUserName = nil
                self.currentUserId = nil
                self.currentProfile = nil
                self.guestAccess = false
                self.pois          = []
                self.bikes         = []
                self.userPOIs      = []
                self.selectedBikeId = nil
                showToast(String(localized: "You've been signed out. 👋"))
            }
        }
    }

    /// Permanently deletes the current user's account.
    ///
    /// Calls the `delete-account` Supabase Edge Function, which uses the
    /// service role to: remove bikes + bike photos, delete push tokens,
    /// anonymize POI contributions, delete the profile row, and finally
    /// delete the auth user. On success the caller is signed out and all
    /// local state is cleared.
    ///
    /// Required for App Store Guideline 5.1.1(v) — apps with account
    /// creation must offer in-app account deletion.
    func deleteAccount() async throws {
        guard currentUserId != nil else {
            throw AppError.message(String(localized: "You are not signed in."))
        }
        // The Supabase Swift SDK automatically attaches the current
        // session's JWT in the Authorization header, which the edge
        // function uses to identify the caller.
        try await supabase.functions.invoke(
            "delete-account",
            options: .init()
        )

        // Sign out locally (server already deleted the user)
        try? await supabase.auth.signOut()
        await MainActor.run {
            self.currentUserName = nil
            self.currentUserId = nil
            self.currentProfile = nil
            self.guestAccess = false
            self.pois          = []
            self.bikes         = []
            self.userPOIs      = []
            self.selectedBikeId = nil
            showToast(String(localized: "Account deleted. We'll miss you. 🚴"))
        }
    }

    // MARK: - Profile

    func fetchProfile(userId: UUID) async {
        do {
            let rows: [ProfileRow] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value

            guard let profile = rows.first else {
                print("fetchProfile: profile row missing — forcing logout")
                await MainActor.run {
                    showToast(String(localized: "Your account was removed by the administrator."))
                    logout()
                }
                return
            }
            if profile.isBlocked {
                print("fetchProfile: profile is_blocked = true — forcing logout")
                await MainActor.run {
                    showToast(String(localized: "Your account was blocked by the administrator."))
                    logout()
                }
                return
            }
            await MainActor.run {
                self.currentProfile = profile
                self.currentUserName = profile.username
            }
        } catch {
            print("fetchProfile error: \(error)")
        }
    }

    var currentUser: ProfileRow? { currentProfile }

    func updateProfile(username: String, avatar: String) async throws {
        guard let userId = currentUserId else { return }
        try await supabase
            .from("profiles")
            .update(["username": username, "avatar": avatar])
            .eq("id", value: userId)
            .execute()
        await MainActor.run {
            self.currentProfile?.username = username
            self.currentProfile?.avatar   = avatar
            self.currentUserName          = username
        }
    }

    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    func changePassword(newPassword: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }

    // MARK: - POIs

    func fetchPOIs() async {
        // PostgREST caps each request at 1000 rows. With 5k+ imported POIs we
        // need to page through everything so layers like Metro / Commuter Rail
        // don't fall off the end of the first page.
        let pageSize = 1000
        var all: [POIRow] = []
        var offset = 0
        do {
            while true {
                let page: [POIRow] = try await supabase
                    .from("pois")
                    .select()
                    .eq("status", value: "approved")
                    .order("id")
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                all.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
                if offset > 50_000 { break } // safety
            }
            await MainActor.run {
                self.pois = all.map(\.asPOI)
            }
        } catch {
            print("fetchPOIs error: \(error)")
            await MainActor.run {
                if self.pois.isEmpty { self.pois = MapData.initialPOIs }
            }
        }
    }

    func addPOI(type: POIType, coordinate: CLLocationCoordinate2D,
                title: String, description: String,
                incidentAt: Date? = nil) {
        guard let userId = currentUserId,
              let userName = currentUserName else { return }

        let id = "u_\(Int(Date().timeIntervalSince1970))"
        let newPOI = POI(id: id, type: type.rawValue,
                         lat: coordinate.latitude, lng: coordinate.longitude,
                         title: title, description: description, author: userName,
                         createdAt: Date())

        Task {
            do {
                struct InsertRow: Encodable {
                    let id, type, title, description, status: String
                    let lat, lng: Double
                    let authorUsername: String
                    let authorId: UUID
                    let incidentAt: String?
                    enum CodingKeys: String, CodingKey {
                        case id, type, title, description, status, lat, lng
                        case authorUsername = "author_username"
                        case authorId = "author_id"
                        case incidentAt = "incident_at"
                    }
                }
                // All user submissions start as "pending" — admin must approve before appearing on map
                let status = "pending"
                let incidentAtISO = incidentAt.map { ISO8601DateFormatter().string(from: $0) }
                try await supabase.from("pois").insert(
                    InsertRow(id: id, type: type.rawValue, title: title,
                              description: description, status: status,
                              lat: coordinate.latitude, lng: coordinate.longitude,
                              authorUsername: userName, authorId: userId,
                              incidentAt: incidentAtISO)
                ).execute()

                await MainActor.run {
                    showToast(String(localized: "✅ Point submitted! It will be reviewed by an admin before appearing on the map."))
                }

                // Always notify admins about new submissions awaiting review.
                try? await supabase.functions.invoke(
                    "notify-admins-new-poi",
                    options: .init(body: [
                        "poi_id":      id,
                        "type":        type.rawValue,
                        "title":       title,
                        "description": description,
                        "lat":         String(coordinate.latitude),
                        "lng":         String(coordinate.longitude),
                        "author":      userName
                    ])
                )

                // Furto reports also fan out to the community-wide channel.
                if type == .furto {
                    try? await supabase.functions.invoke(
                        "notify-admin-furto",
                        options: .init(body: [
                            "poi_id":      id,
                            "title":       title,
                            "description": description,
                            "lat":         String(coordinate.latitude),
                            "lng":         String(coordinate.longitude),
                            "author":      userName
                        ])
                    )
                }
            } catch {
                await MainActor.run {
                    showToast("❌ Erro ao salvar ponto. Tente novamente.")
                }
            }
        }
    }

    // MARK: - User POIs

    func fetchUserPOIs() async {
        guard let userId = currentUserId else { return }
        do {
            // Only approved contributions count for the profile screen —
            // rejected submissions shouldn't pad the list.
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select()
                .eq("author_id", value: userId)
                .eq("status", value: "approved")
                .order("created_at", ascending: false)
                .execute()
                .value
            await MainActor.run { self.userPOIs = rows.map(\.asPOI) }
        } catch {
            print("fetchUserPOIs error: \(error)")
        }
    }

    /// Admin-only: permanently delete a POI from the map.
    func adminDeletePOI(_ poi: POI) async throws {
        guard isAdmin else { return }
        try await supabase.from("pois").delete().eq("id", value: poi.id).execute()
        await MainActor.run {
            pois.removeAll { $0.id == poi.id }
            userPOIs.removeAll { $0.id == poi.id }
            if selectedPOI?.id == poi.id { selectedPOI = nil }
            showToast(String(localized: "🗑️ Point deleted from the map."))
        }
    }

    // MARK: - Bikes

    func fetchBikes() async {
        guard let userId = currentUserId else { return }
        do {
            let rows: [BikeRow] = try await supabase
                .from("bikes")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            await MainActor.run { self.bikes = rows }
        } catch {
            print("fetchBikes error: \(error)")
        }
    }

    func addBike(nickname: String, brand: String, color: String, aro: String,
                 serialNumber: String, details: String, bikeType: String,
                 imageData: Data?) async throws {
        guard let userId = currentUserId else { return }

        var imageUrl: String? = nil
        if let imageData { imageUrl = await uploadBikePhoto(imageData) }

        struct InsertBike: Encodable {
            let user_id: UUID
            let nickname, brand, color, aro, serial_number, details, bike_type: String
            let image_url: String?
        }
        let inserted: BikeRow = try await supabase
            .from("bikes")
            .insert(InsertBike(user_id: userId, nickname: nickname, brand: brand,
                               color: color, aro: aro, serial_number: serialNumber,
                               details: details, bike_type: bikeType,
                               image_url: imageUrl))
            .select()
            .single()
            .execute()
            .value
        await MainActor.run { self.bikes.insert(inserted, at: 0) }
    }

    func updateBike(_ bike: BikeRow, imageData: Data?) async throws {
        var imageUrl = bike.imageUrl
        if let imageData { imageUrl = await uploadBikePhoto(imageData) }

        struct UpdateBike: Encodable {
            let nickname, brand, color, aro, serial_number, details, bike_type: String
            let image_url: String?
        }
        let updated: BikeRow = try await supabase
            .from("bikes")
            .update(UpdateBike(nickname: bike.nickname, brand: bike.brand,
                               color: bike.color, aro: bike.aro,
                               serial_number: bike.serialNumber,
                               details: bike.details, bike_type: bike.bikeType,
                               image_url: imageUrl))
            .eq("id", value: bike.id)
            .select()
            .single()
            .execute()
            .value
        await MainActor.run {
            if let idx = self.bikes.firstIndex(where: { $0.id == bike.id }) {
                self.bikes[idx] = updated
            }
        }
    }

    func deleteBike(_ bike: BikeRow) async throws {
        try await supabase.from("bikes").delete().eq("id", value: bike.id).execute()
        await MainActor.run { self.bikes.removeAll { $0.id == bike.id } }
    }

    private func uploadBikePhoto(_ data: Data) async -> String? {
        let fileName = "bike_\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try await supabase.storage
                .from("bike-photos")
                .upload(fileName, data: data, options: .init(contentType: "image/jpeg", upsert: false))
            let url = try supabase.storage.from("bike-photos").getPublicURL(path: fileName)
            return url.absoluteString
        } catch {
            print("uploadBikePhoto error: \(error)")
            return nil
        }
    }

    // MARK: - Photo Upload

    func uploadFurtoPhoto(_ data: Data) async -> String? {
        let fileName = "furto_\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try await supabase.storage
                .from("furto-photos")
                .upload(fileName, data: data, options: .init(contentType: "image/jpeg", upsert: false))
            let url = try supabase.storage
                .from("furto-photos")
                .getPublicURL(path: fileName)
            return url.absoluteString
        } catch {
            print("uploadFurtoPhoto error: \(error)")
            return nil
        }
    }

    // MARK: - Infrastructure Features

    func fetchInfraFeatures() async {
        do {
            struct InfraRow: Decodable {
                let name: String
                let type: String
                let coordinates: [[Double]]  // [[lng, lat], ...]
                let extensionKm: String?
                let reason: String?
                let status: String?
                let forecast: String?
                enum CodingKeys: String, CodingKey {
                    case name, type, coordinates
                    case extensionKm  = "extension_km"
                    case reason, status, forecast
                }
            }
            let rows: [InfraRow] = try await supabase
                .from("infra_features")
                .select()
                .execute()
                .value

            let features = rows.compactMap { row -> BikeInfraFeature? in
                guard let infraType = InfraType(rawValue: row.type) else { return nil }
                let coords = row.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
                }
                return BikeInfraFeature(
                    name: row.name, type: infraType,
                    coordinates: coords,
                    extensionKm: row.extensionKm,
                    reason: row.reason,
                    status: row.status,
                    forecast: row.forecast
                )
            }
            await MainActor.run {
                self.infraFeatures = features
            }
        } catch {
            // Fallback to hardcoded data if Supabase is unreachable
            await MainActor.run {
                if self.infraFeatures.isEmpty {
                    self.infraFeatures = MapData.infraFeatures
                }
            }
            print("fetchInfraFeatures error: \(error)")
        }
    }

    // MARK: - Admin

    var isAdmin: Bool { currentProfile?.isAdmin == true }

    func fetchPendingPOIs() async -> [POI] {
        do {
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select()
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value
            await MainActor.run { self.pendingPOICount = rows.count }
            return rows.map { $0.asPOI }
        } catch {
            print("fetchPendingPOIs error: \(error)")
            return []
        }
    }

    /// Refresh just the pending count (cheaper than fetching all rows).
    /// Called on app foreground + after every admin approve/reject so the
    /// avatar dot stays accurate.
    func refreshPendingCount() async {
        guard isAdmin else {
            await MainActor.run { pendingPOICount = 0 }
            return
        }
        do {
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select("id")
                .eq("status", value: "pending")
                .execute()
                .value
            await MainActor.run { pendingPOICount = rows.count }
        } catch {
            // leave count as-is on transient errors
        }
    }

    // approvePOI / rejectPOI — mirrors BikeMap SJC's admin flow exactly:
    // status update → refetch (pick up the trigger-renamed title) →
    // in-place replace → centerOnCoordinate → background forced re-fetch
    // → notify-poi-approved fan-out (payload carries author_id so the
    // submitter gets a "your point was approved" push).
    func approvePOI(_ poi: POI) async throws {
        try await supabase
            .from("pois")
            .update(["status": "approved"])
            .eq("id", value: poi.id)
            .execute()

        // The server-side trigger `assign_code_on_approve` assigns a fresh
        // <PREFIX><####> code and prepends it to the title. Re-fetch the row
        // so the local copy uses the new title instead of the old one.
        var finalPOI = poi
        var authorIdStr: String? = nil
        if let rows: [POIRow] = try? await supabase
            .from("pois").select().eq("id", value: poi.id).limit(1)
            .execute().value,
           let row = rows.first {
            finalPOI = row.asPOI
            authorIdStr = row.authorId?.uuidString
        }

        await MainActor.run {
            if let idx = self.pois.firstIndex(where: { $0.id == finalPOI.id }) {
                self.pois[idx] = finalPOI
            } else {
                self.pois.append(finalPOI)
                print("approvePOI: appended \(finalPOI.id) of type '\(finalPOI.type)' as \(finalPOI.title)")
            }
            self.layerVisibility[finalPOI.type] = true
            self.centerOnCoordinate = finalPOI.coordinate
            pendingPOICount = max(0, pendingPOICount - 1)
            showToast(String(localized: "✅ Point approved and published on the map."))
        }

        // notify-poi-approved fires AFTER local state is updated so the
        // payload carries the final code-prefixed title.
        var body: [String: String] = [
            "poi_id":      finalPOI.id,
            "poi_type":    finalPOI.type,
            "title":       finalPOI.title,
            "description": finalPOI.description,
            "lat":         String(finalPOI.lat),
            "lng":         String(finalPOI.lng),
        ]
        if let aid = authorIdStr { body["author_id"] = aid }
        try? await supabase.functions.invoke(
            "notify-poi-approved", options: .init(body: body)
        )
    }

    func rejectPOI(_ poi: POI) async throws {
        // Reject = DELETE the row entirely. The pois_archive trigger keeps a
        // 30-day backup; the on_poi_deleted trigger decrements the author's
        // contribution_count so it stops counting toward the ranking.
        print("rejectPOI: DELETE \(poi.id)")
        let resp = try await supabase
            .from("pois")
            .delete()
            .eq("id", value: poi.id)
            .execute()
        print("rejectPOI: DELETE response status \(resp.response.statusCode)")
        await MainActor.run {
            self.pois.removeAll { $0.id == poi.id }
            self.userPOIs.removeAll { $0.id == poi.id }
            pendingPOICount = max(0, pendingPOICount - 1)
            showToast(String(localized: "🗑️ Point rejected."))
        }
        print("rejectPOI: done for \(poi.id)")
    }

    /// Forces a fresh fetch from Supabase even if in-memory state is stale.
    /// Used after admin actions that mutate the public POI set. If
    /// `ensuringIncludes` is provided, the POI is re-injected when the server
    /// fetch happens to miss it (read-after-write lag) so the map stays
    /// consistent with what the admin just did.
    private func fetchPOIsForcingRefresh(ensuringIncludes ensure: POI? = nil,
                                         idForCheck ensureId: String? = nil) async {
        do {
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select()
                .eq("status", value: "approved")
                .execute()
                .value
            var finalPOIs = rows.map(\.asPOI)
            if let ensure, let id = ensureId,
               !finalPOIs.contains(where: { $0.id == id }) {
                finalPOIs.append(ensure)
                print("fetchPOIsForcingRefresh: server missed \(id); re-injected locally")
            }
            await MainActor.run { self.pois = finalPOIs }
            print("fetchPOIsForcingRefresh: \(finalPOIs.count) POIs in array")
        } catch {
            print("fetchPOIsForcingRefresh error: \(error)")
        }
    }

    /// Allows an admin to edit title, description, and location of any POI.
    /// Pass `lat`/`lng` to also relocate; omit to keep the existing position.
    func updatePOIContent(_ poi: POI,
                          title: String,
                          description: String,
                          lat: Double? = nil,
                          lng: Double? = nil) async throws {
        guard isAdmin else { return }
        struct Patch: Encodable {
            let title: String
            let description: String
            let lat: Double?
            let lng: Double?
        }
        try await supabase
            .from("pois")
            .update(Patch(title: title, description: description, lat: lat, lng: lng))
            .eq("id", value: poi.id)
            .execute()

        let newLat = lat ?? poi.lat
        let newLng = lng ?? poi.lng

        await MainActor.run {
            if let idx = pois.firstIndex(where: { $0.id == poi.id }) {
                pois[idx] = POI(
                    id: poi.id, type: poi.type,
                    lat: newLat, lng: newLng,
                    title: title, description: description,
                    author: poi.author, createdAt: poi.createdAt
                )
            }
            if selectedPOI?.id == poi.id {
                selectedPOI = POI(
                    id: poi.id, type: poi.type,
                    lat: newLat, lng: newLng,
                    title: title, description: description,
                    author: poi.author, createdAt: poi.createdAt
                )
            }
            showToast("✏️ Point updated.")
        }
    }

    // MARK: - Unread furto notifications

    /// If the current user has any unread `furto_alert` notification, open the
    /// most recent one in the POI detail sheet and mark it as read so it won't
    /// surface again. Called on app launch/foreground so users who open the
    /// app from the home screen (not via the push tap) still land on the new
    /// stolen-bike point.
    func openLatestUnreadFurtoIfAny() async {
        guard let userId = currentUserId else { return }
        struct NotifRow: Decodable {
            let id: UUID
            let poi_id: String?
            let title: String?
            let body: String?
            let lat: Double?
            let lng: Double?
        }
        do {
            let rows: [NotifRow] = try await supabase
                .from("notifications")
                .select("id,poi_id,title,body,lat,lng")
                .eq("user_id", value: userId)
                .eq("type", value: "furto_alert")
                .is("read_at", value: nil)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value
            let alerts: [UnreadAlert] = rows.compactMap { n in
                guard let pid = n.poi_id else { return nil }
                return UnreadAlert(
                    id: n.id, poiId: pid,
                    title: n.title ?? "Missing bike",
                    body: n.body ?? "",
                    lat: n.lat, lng: n.lng
                )
            }
            await MainActor.run {
                self.unreadAlerts = alerts
                if !alerts.isEmpty {
                    self.layerVisibility[POIType.furto.rawValue] = true
                }
            }
        } catch {
            print("openLatestUnreadFurtoIfAny error: \(error)")
        }
    }

    /// Loads recent notifications for the profile screen.
    func fetchNotifications() async {
        guard let userId = currentUserId else { return }
        do {
            let rows: [NotificationEntry] = try await supabase
                .from("notifications")
                .select("id,type,poi_id,title,body,lat,lng,read_at,created_at")
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value
            await MainActor.run { self.notifications = rows }
        } catch {
            print("fetchNotifications error: \(error)")
        }
    }

    func openNotification(_ entry: NotificationEntry) async {
        if let pid = entry.poi_id {
            let poi: POI
            if let existing = pois.first(where: { $0.id == pid }) {
                poi = existing
            } else if let lat = entry.lat, let lng = entry.lng {
                poi = POI(id: pid, type: POIType.furto.rawValue,
                          lat: lat, lng: lng,
                          title: entry.title, description: entry.body ?? "",
                          author: "", createdAt: entry.created_at)
            } else {
                return
            }
            await MainActor.run {
                self.selectedPOI = poi
                self.layerVisibility[poi.type] = true
                if !self.pois.contains(where: { $0.id == poi.id }) {
                    self.pois.append(poi)
                }
            }
        }
        if entry.read_at == nil {
            try? await supabase
                .from("notifications")
                .update(["read_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: entry.id)
                .execute()
            await MainActor.run {
                self.unreadAlerts.removeAll { $0.id == entry.id }
            }
            await fetchNotifications()
        }
    }

    func openAlert(_ alert: UnreadAlert) async {
        let poi: POI
        if let existing = pois.first(where: { $0.id == alert.poiId }) {
            poi = existing
        } else if let lat = alert.lat, let lng = alert.lng {
            poi = POI(id: alert.poiId, type: POIType.furto.rawValue,
                      lat: lat, lng: lng,
                      title: alert.title, description: alert.body,
                      author: "", createdAt: nil)
        } else {
            return
        }
        await MainActor.run {
            self.selectedPOI = poi
            self.layerVisibility[POIType.furto.rawValue] = true
            if !self.pois.contains(where: { $0.id == poi.id }) {
                self.pois.append(poi)
            }
            self.unreadAlerts.removeAll { $0.id == alert.id }
        }
        try? await supabase
            .from("notifications")
            .update(["read_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: alert.id)
            .execute()
    }

    // MARK: - Push Notifications

    func requestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func savePushToken(_ token: String) {
        // RLS on push_tokens requires user_id = auth.uid().
        // If the APNs token arrives before login, skip; we'll re-register after signIn / restoreSession.
        guard let userId = currentUserId else {
            print("savePushToken skipped: not authenticated yet")
            return
        }
        Task {
            do {
                struct TokenRow: Encodable {
                    let token: String
                    let platform: String
                    let userId: UUID
                    enum CodingKeys: String, CodingKey {
                        case token, platform
                        case userId = "user_id"
                    }
                }
                try await supabase
                    .from("push_tokens")
                    .upsert(TokenRow(token: token, platform: "ios", userId: userId),
                            onConflict: "token")
                    .execute()
            } catch {
                print("savePushToken error: \(error)")
            }
        }
    }

    // MARK: - Ranking

    func rankedUsers() async -> [(username: String, profile: ProfileRow)] {
        do {
            let profiles: [ProfileRow] = try await supabase
                .from("profiles")
                .select()
                .order("contribution_count", ascending: false)
                .limit(50)
                .execute()
                .value
            return profiles.map { (username: $0.username, profile: $0) }
        } catch {
            return []
        }
    }

    // MARK: - Admin moderation

    @discardableResult
    func moderateUser(_ targetId: UUID, action: String) async -> Bool {
        guard isAdmin else { return false }
        struct Body: Encodable {
            let target_user_id: String
            let action: String
        }
        do {
            try await supabase.functions.invoke(
                "admin-moderate-user",
                options: .init(body: Body(
                    target_user_id: targetId.uuidString,
                    action: action
                ))
            )
            return true
        } catch {
            print("moderateUser \(action) failed: \(error)")
            return false
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastMessage = message
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.toastMessage = nil }
        }
    }
}

// MARK: - App errors

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}
