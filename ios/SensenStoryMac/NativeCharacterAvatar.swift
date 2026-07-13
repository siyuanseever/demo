import AppKit
import SwiftUI

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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
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
        for fileExtension in ["webp", "png", "jpg", "jpeg"] {
            guard let url = Bundle.main.url(forResource: assetName, withExtension: fileExtension),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            return image
        }
        return nil
    }
}
