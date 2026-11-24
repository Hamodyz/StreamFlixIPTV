import SwiftUI
import StreamFlixCore

struct LiveTVView: View {
    @ObservedObject var catalogVM: CatalogViewModel
    @State private var selectedCategoryId: String?

    var displayedChannels: [LiveChannel] {
        if let catId = selectedCategoryId {
            return catalogVM.channels(for: catId)
        }
        return catalogVM.liveChannels
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            CategoryChip(title: "All", isSelected: selectedCategoryId == nil) {
                                selectedCategoryId = nil
                            }
                            ForEach(catalogVM.liveCategories) { cat in
                                CategoryChip(title: cat.categoryName, isSelected: selectedCategoryId == cat.categoryId) {
                                    selectedCategoryId = cat.categoryId
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    List(displayedChannels) { channel in
                        Button {
                            catalogVM.playChannel(channel, preferHLS: true)
                        } label: {
                            HStack(spacing: 14) {
                                AsyncImage(url: URL(string: channel.streamIcon ?? "")) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fit)
                                    } else {
                                        Image(systemName: "tv")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 48, height: 36)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                                Text(channel.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "play.fill")
                                    .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                            }
                        }
                        .listRowBackground(Color.black)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Live TV")
        }
    }
}

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color.white.opacity(0.14), in: Capsule())
        }
    }
}
