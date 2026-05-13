import SwiftUI

struct POITypePickerSheet: View {
    let onSelect: (POIType) -> Void
    @Environment(\.dismiss) private var dismiss

    // General types only (furto and acidente have their own dedicated buttons)
    private let types: [POIType] = POIType.allCases.filter {
        $0.canContribute && $0 != .furto && $0 != .acidente_ferido
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select the type of point you want to add. Then tap the exact location on the map.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                }

                Section("Point type") {
                    ForEach(types, id: \.rawValue) { type in
                        Button {
                            onSelect(type)
                        } label: {
                            HStack(spacing: 14) {
                                Text(type.emoji)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(Color(type.uiColor).opacity(0.15),
                                                in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
