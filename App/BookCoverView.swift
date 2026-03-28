import SwiftUI

struct BookCoverView: View {
    let coverURL: String?
    let title: String
    let size: CGSize

    var body: some View {
        if let urlStr = coverURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackCover
                case .empty:
                    ProgressView()
                        .frame(width: size.width, height: size.height)
                @unknown default:
                    fallbackCover
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        } else {
            fallbackCover
        }
    }

    private var fallbackCover: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [.accentColor.opacity(0.6), .accentColor.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(
                Text(String(title.prefix(1)))
                    .font(.system(size: size.width * 0.4, weight: .bold))
                    .foregroundColor(.white)
            )
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}
