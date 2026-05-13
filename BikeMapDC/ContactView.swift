import SwiftUI

struct ContactView: View {
    @Environment(\.dismiss) private var dismiss

    private let adminEmail = "bikemap.dc@gmail.com"
    private let userGuideURL = URL(string: "https://eu2001.github.io/bikemap-dc-web/guide.html")!

    var body: some View {
        NavigationStack {
            List {

                // MARK: About
                Section {
                    HStack(spacing: 14) {
                        Image("logo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("BikeMap DC")
                                .font(.headline)
                            Text("DC Collaborative Bike Map")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // MARK: Contact
                Section("Contact the admin") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Email")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(adminEmail)
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                    } icon: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.blue)
                    }
                    .onTapGesture { openMail(subject: "Contact - BikeMap DC", body: "") }

                    Text("Questions, suggestions or info about the DC bike map? Contact the team.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: User Guide
                Section("Learn how to use the app") {
                    Button {
                        UIApplication.shared.open(userGuideURL)
                    } label: {
                        Label("Open user guide", systemImage: "book.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))

                    Text("Walks through every feature — adding points, registering bikes, reading the legend, and more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Report error
                Section("Report problem") {
                    Button {
                        openMail(
                            subject: "Report Error - BikeMap DC",
                            body: "Describe the issue you found on the map:\n\n"
                        )
                    } label: {
                        Label("Report map error", systemImage: "exclamationmark.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))

                    Text("Found an error or outdated info on the map? Use the button above to let us know by email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func openMail(subject: String, body: String) {
        let encoded = "mailto:\(adminEmail)?subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: encoded) {
            UIApplication.shared.open(url)
        }
    }
}
