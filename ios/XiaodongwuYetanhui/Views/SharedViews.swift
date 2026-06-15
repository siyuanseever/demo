import SwiftUI
import UIKit

struct WarmBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                .softPaper,
                Color(hex: 0xf8efe2),
                Color(hex: 0xeaf0df),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.nightInk)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SoftPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            }
    }
}

struct CharacterAvatar: View {
    let character: CompanionCharacter
    var size: CGFloat = 52
    var expressionID: String?

    var body: some View {
        let assetName = character.expression(id: expressionID)?.assetName ?? character.avatarName
        ZStack {
            Circle()
                .fill(character.bubbleColor)
            if let image = UIImage(named: assetName) ?? UIImage(named: "\(assetName).webp") ?? UIImage(named: "\(assetName).png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(Circle())
            } else {
                Image(systemName: character.systemImageName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.warmBrown)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle().stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .accessibilityLabel(character.name)
    }
}

struct EmptyHintView: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.warmBrown)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
