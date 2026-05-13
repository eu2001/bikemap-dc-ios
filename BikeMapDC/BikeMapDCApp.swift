import SwiftUI
import UserNotifications
import CoreLocation

/// User-selectable in-app language. "system" means follow the device locale.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .en:     return "English"
        case .es:     return "Español"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: return nil
        case .en:     return Locale(identifier: "en")
        case .es:     return Locale(identifier: "es-419")
        }
    }
}

@main
struct BikeMapDCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var appLocale: Locale {
        AppLanguage(rawValue: appLanguageRaw)?.locale ?? Locale.current
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if appState.currentUserName != nil {
                        ContentView(appState: appState)
                            .transition(.opacity)
                    } else {
                        WelcomeView(appState: appState)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: appState.currentUserName)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .environment(\.locale, appLocale)
            .animation(.easeInOut(duration: 0.5), value: showSplash)
            .task {
                // Splash visível por ~1s — tempo suficiente para o pulso da logo
                // sem bloquear a abertura do mapa.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                showSplash = false
            }
            .onAppear {
                appDelegate.appState = appState
                appState.requestPushPermission()
            }
            // Navigate to POI when notification is tapped
            .onChange(of: appState.notificationTargetPOI) { _, poi in
                // ContentView observes this via appState directly
            }
        }
    }
}

// MARK: - App Delegate (push notifications)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called when APNs gives us a device token
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        appState?.savePushToken(token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for push: \(error)")
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap → navigate to POI
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let latStr = info["lat"] as? String, let lngStr = info["lng"] as? String,
           let lat = Double(latStr), let lng = Double(lngStr) {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let title = info["poi_title"] as? String ?? String(localized: "Bike Theft")
            let desc  = info["poi_description"] as? String ?? ""
            let poiId = info["poi_id"] as? String ?? ""
            let poi   = POI(id: poiId, type: POIType.furto.rawValue,
                            lat: lat, lng: lng,
                            title: title, description: desc,
                            author: "", createdAt: nil)
            DispatchQueue.main.async {
                self.appState?.notificationTargetPOI = poi
            }
        }
        completionHandler()
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .opacity(pulse ? 1.0 : 0.35)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
        }
    }
}
