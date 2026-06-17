import SwiftUI

struct StarMapView: View {
    @EnvironmentObject private var store: CompanionStore

    let openHome: () -> Void
    let openForest: () -> Void
    let openMe: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let fullHeight = geometry.size.height + safeTop + safeBottom
            let backgroundOffset = -(safeTop - safeBottom) / 2

            ZStack {
                StarMapBundleImage(name: "starmap_background_cloud")
                    .frame(width: geometry.size.width, height: fullHeight)
                    .offset(y: backgroundOffset)
                    .clipped()
                    .ignoresSafeArea(.all)

                StarMapTextOverlay(insight: store.starMapInsight)
                    .frame(width: geometry.size.width, height: fullHeight)
                    .offset(y: backgroundOffset)

                StarMapBottomBar(
                    openHome: openHome,
                    openForest: openForest,
                    openStarMap: {},
                    openMe: openMe
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .ignoresSafeArea(.all)
        }
        .task {
            await store.refreshStarMapInsight()
        }
    }
}

private struct StarMapBundleImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = UIImage(named: name) ?? UIImage(named: "\(name).png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0xf4efe8)
            }
        }
    }
}

private struct StarMapTextOverlay: View {
    let insight: StarMapInsight

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                Text(insight.coreInsight)
                    .font(.custom("HannotateSC-W5", size: 22))
                    .lineSpacing(8)
                    .foregroundStyle(Color(hex: 0x5d536f))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .frame(width: width * 0.72, height: height * 0.18)
                    .position(x: width * 0.5, y: height * 0.36)

                Text(patternText)
                    .font(.custom("HannotateSC-W5", size: 17))
                    .lineSpacing(8)
                    .foregroundStyle(Color(hex: 0x5f5369))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)
                    .frame(width: width * 0.2, height: height * 0.15)
                    .position(x: width * 0.17, y: height * 0.64)

                Text(flowText)
                    .font(.custom("HannotateSC-W5", size: 15))
                    .lineSpacing(7)
                    .foregroundStyle(Color(hex: 0x5f5369))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.74)
                    .frame(width: width * 0.24, height: height * 0.16)
                    .position(x: width * 0.5, y: height * 0.64)

                Text(insight.gentleReminder)
                    .font(.custom("HannotateSC-W5", size: 16))
                    .lineSpacing(7)
                    .foregroundStyle(Color(hex: 0x6a5c59))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.76)
                    .frame(width: width * 0.23, height: height * 0.16)
                    .position(x: width * 0.83, y: height * 0.64)
            }
        }
        .allowsHitTesting(false)
    }

    private var patternText: String {
        insight.recentPattern.joined(separator: "\n↓\n")
    }

    private var flowText: String {
        insight.flowConditions.joined(separator: "\n")
    }
}

private struct StarMapBottomBar: View {
    let openHome: () -> Void
    let openForest: () -> Void
    let openStarMap: () -> Void
    let openMe: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            StarMapTabButton(title: "首页", systemImage: "house.fill", isSelected: false, action: openHome)
            StarMapTabButton(title: "森林", systemImage: "tree.fill", isSelected: false, action: openForest)
            StarMapTabButton(title: "星图", systemImage: "sparkles", isSelected: true, action: openStarMap)
            StarMapRabbitTabButton(action: openMe)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(hex: 0xf2e6d0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xd8c8b2).opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.warmBrown.opacity(0.1), radius: 14, x: 0, y: 6)
    }
}

private struct StarMapTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 31, height: 24)
                    .background(isSelected ? Color(hex: 0xd7c4f2).opacity(0.5) : Color.clear, in: Capsule())
                Text(title)
                    .font(.custom("HannotateSC-W5", size: 10))
            }
            .foregroundStyle(isSelected ? Color(hex: 0x8a6ea8) : Color.warmBrown.opacity(0.72))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct StarMapRabbitTabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image("sensen-rabbit-flat-icon-v1")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 31, height: 31)
                    .clipShape(Circle())
                Text("我的")
                    .font(.custom("HannotateSC-W5", size: 10))
            }
            .foregroundStyle(Color.warmBrown.opacity(0.72))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
