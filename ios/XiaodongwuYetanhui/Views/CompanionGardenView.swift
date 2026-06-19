import SwiftUI
import UIKit

struct CompanionGardenView: View {
    @State private var phase: BailanPhase = .paused

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: 0xf3ece2)
                    .ignoresSafeArea()

                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        phase = phase.next
                    }
                } label: {
                    BailanBundleImage(name: phase.imageName)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: min(geometry.size.width, 480))
                        .id(phase)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(phase.accessibilityLabel)
                .padding(.bottom, 92)
            }
        }
    }
}

private enum BailanPhase: Int, CaseIterable {
    case paused
    case armed
    case destroyed

    var imageName: String {
        switch self {
        case .paused:
            return "bailan-world-pause"
        case .armed:
            return "bailan-destroy-button"
        case .destroyed:
            return "bailan-world-destroyed"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .paused:
            return "世界暂停按钮。点击后什么都不想了。"
        case .armed:
            return "世界毁灭按钮。点击确认毁灭。"
        case .destroyed:
            return "地球爆炸了，摆烂兔正在休息。点击重新开始。"
        }
    }

    var next: BailanPhase {
        switch self {
        case .paused:
            return .armed
        case .armed:
            return .destroyed
        case .destroyed:
            return .paused
        }
    }
}

private struct BailanBundleImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = UIImage(named: name) ?? UIImage(named: "\(name).png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(hex: 0xe4ddd2)
                    .overlay {
                        Image(systemName: "hare.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(Color(hex: 0x777168))
                    }
            }
        }
    }
}
