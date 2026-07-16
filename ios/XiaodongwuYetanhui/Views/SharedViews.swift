import SwiftUI
import UIKit

struct WarmBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.warmBg1,
                Color.warmBg2,
                Color.warmBg3,
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
                    .stroke(Color.overlaySubtle, lineWidth: 1)
            }
    }
}

struct CharacterAvatar: View {
    let character: CompanionCharacter
    var size: CGFloat = 52
    var expressionID: String?
    var cornerRadius: CGFloat = 8
    var isFixedSize: Bool = true

    var body: some View {
        let assetName = character.expression(id: expressionID)?.assetName ?? character.avatarName
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(character.bubbleColor)
            if let image = UIImage(named: assetName) ?? UIImage(named: "\(assetName).webp") ?? UIImage(named: "\(assetName).png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: character.systemImageName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.warmBrown)
            }
        }
        .frame(width: isFixedSize ? size : nil, height: isFixedSize ? size : nil)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.avatarStroke.opacity(0.75), lineWidth: 1)
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
