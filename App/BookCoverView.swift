import SwiftUI

struct BookCoverView: View {
    let coverURL: String?
    let title: String
    let size: CGSize
    private let cornerRadius: CGFloat = 14

    var body: some View {
        if let url = resolvedCoverURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackCover
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.83, green: 0.93, blue: 0.99),
                                        Color(red: 0.77, green: 0.88, blue: 0.99),
                                        Color(red: 0.97, green: 0.87, blue: 0.76)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        ProgressView()
                            .tint(.white)
                    }
                    .frame(width: size.width, height: size.height)
                @unknown default:
                    fallbackCover
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 8)
        } else {
            fallbackCover
        }
    }

    private var resolvedCoverURL: URL? {
        guard let raw = coverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        if let direct = URL(string: raw), direct.scheme != nil {
            return direct
        }

        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }

        if raw.hasPrefix("/") {
            return URL(string: "https://www.bqg291.cc\(raw)")
        }

        return URL(string: "https://www.bqg291.cc/\(raw)")
    }

    private var fallbackCover: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.51, green: 0.74, blue: 0.96),
                        Color(red: 0.42, green: 0.48, blue: 0.88),
                        Color(red: 0.91, green: 0.70, blue: 0.90),
                        Color(red: 0.97, green: 0.81, blue: 0.60)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: size.width * 0.72)
                    .blur(radius: 10)
                    .offset(x: -size.width * 0.18, y: -size.height * 0.08)
            }
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: size.width * 0.24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))

                    Text(String(title.prefix(1)))
                        .font(.system(size: size.width * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(shortTitle)
                        .font(.system(size: max(size.width * 0.11, 10), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 8)
    }

    private var shortTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(8))
    }
}
