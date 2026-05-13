import SwiftUI

struct RankingView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var ranked: [(username: String, profile: ProfileRow)] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if ranked.isEmpty {
                    ContentUnavailableView(
                        "Nenhum contribuidor ainda",
                        systemImage: "person.3",
                        description: Text("Be the first to add points to the map!")
                    )
                } else {
                    Section("Map contributors") {
                        ForEach(Array(ranked.enumerated()), id: \.element.username) { index, entry in
                            rankRow(index: index, username: entry.username, profile: entry.profile)
                        }
                    }
                }

                if let myName = appState.currentUserName {
                    let myPOIs = appState.pois.filter { $0.author == myName }
                    if !myPOIs.isEmpty {
                        Section("My added points") {
                            ForEach(myPOIs.suffix(10).reversed()) { poi in
                                HStack(spacing: 10) {
                                    Text(poi.poiType.emoji)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(poi.title).font(.subheadline).fontWeight(.medium)
                                        Text(poi.poiType.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        dismiss()
                                        appState.selectedPOI = poi
                                    } label: {
                                        Image(systemName: "location.circle").foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("🏆 Ranking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadRanking() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadRanking() async {
        loading = true
        ranked = await appState.rankedUsers()
        loading = false
    }

    @ViewBuilder
    private func rankRow(index: Int, username: String, profile: ProfileRow) -> some View {
        let displayName = username == "admin" ? "Equipe BikeMap" : username
        let medal: String = index == 0 ? "🥇" : index == 1 ? "🥈" : index == 2 ? "🥉" : "\(index + 1)º"
        let isMe = username == appState.currentUserName

        HStack(spacing: 12) {
            Text(medal).font(.title3).frame(width: 36)

            AvatarView(id: profile.avatar, size: 40)
                .background(isMe ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName).fontWeight(isMe ? .bold : .regular)
                    if profile.isPremium { Text("⭐").font(.caption) }
                    if isMe { Text("(you)").font(.caption).foregroundStyle(.secondary) }
                }
                Text("\(profile.contributionCount) points")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .listRowBackground(isMe ? Color.blue.opacity(0.05) : nil)
    }
}
