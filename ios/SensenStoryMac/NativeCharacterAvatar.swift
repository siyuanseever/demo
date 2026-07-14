import AppKit
import SwiftUI

private final class NativeBundledImageCache {
    static let shared = NativeBundledImageCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 16
        return cache
    }()

    func image(named assetName: String) -> NSImage? {
        let cacheKey = assetName as NSString
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        for fileExtension in ["webp", "png", "jpg", "jpeg"] {
            guard let url = Bundle.main.url(forResource: assetName, withExtension: fileExtension),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            cache.setObject(image, forKey: cacheKey)
            return image
        }
        return nil
    }
}

struct NativeCharacterAvatar: View {
    let character: CompanionCharacter
    let expressionID: String?
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let image = bundledImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: character.systemImageName)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(character.bubbleColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(character.bubbleColor.opacity(0.16))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.avatarStroke.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: character.bubbleColor.opacity(0.18), radius: 4, y: 2)
        .accessibilityLabel(expressionLabel)
    }

    private var expression: CompanionExpression? {
        character.expression(id: expressionID ?? character.defaultExpressionID)
            ?? character.expression(id: character.defaultExpressionID)
    }

    private var expressionLabel: String {
        "\(character.name)，\(expression?.label ?? "正在倾听")"
    }

    private var bundledImage: NSImage? {
        let assetName = expression?.assetName ?? character.avatarName
        return NativeBundledImageCache.shared.image(named: assetName)
    }
}
