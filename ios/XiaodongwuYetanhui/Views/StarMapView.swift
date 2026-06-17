import SwiftUI

struct StarMapView: View {
    @EnvironmentObject private var store: CompanionStore

    let close: () -> Void

    var body: some View {
        ZStack {
            StarMapBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header

                    coreInsightCard(store.starMapInsight.coreInsight)
                        .padding(.top, 16)

                    VStack(spacing: 14) {
                        StarMapPatternCard(
                            title: store.starMapInsight.recentPatternTitle,
                            items: store.starMapInsight.recentPatternItems,
                            style: .moon
                        )

                        StarMapPatternCard(
                            title: store.starMapInsight.flowConditionTitle,
                            items: store.starMapInsight.flowConditionItems,
                            style: .cloud
                        )

                        StarMapReminderCard(text: store.starMapInsight.gentleReminder)
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 34)
            }
        }
        .task {
            store.refreshStarMapInsight()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.warmBrown.opacity(0.82))
                        .frame(width: 38, height: 38)
                        .background(Color(hex: 0xf8efdf), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回首页")

                Spacer()
            }

            VStack(spacing: 6) {
                Text("星图")
                    .font(.custom("HannotateSC-W5", size: 34))
                    .foregroundStyle(Color(hex: 0x6f5f7f))

                Text("森森发现的你的生命地图")
                    .font(.custom("HannotateSC-W5", size: 15))
                    .foregroundStyle(Color.warmBrown.opacity(0.58))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func coreInsightCard(_ text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0xfffbf0))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(hex: 0xe0d5c7).opacity(0.78), lineWidth: 1)
                }

            VStack(spacing: 18) {
                HStack(spacing: 9) {
                    StarDot(size: 5, color: Color(hex: 0xd7c4f2))
                    StarDot(size: 7, color: Color(hex: 0xf3d37d))
                    StarDot(size: 4, color: Color(hex: 0xc8d8ef))
                }

                Text(text)
                    .font(.custom("HannotateSC-W5", size: 24))
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(hex: 0x5d516e))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 30)
        }
        .shadow(color: Color(hex: 0x8b5f35).opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

private struct StarMapPatternCard: View {
    enum Style {
        case moon
        case cloud

        var tint: Color {
            switch self {
            case .moon:
                return Color(hex: 0xf4df9b)
            case .cloud:
                return Color(hex: 0xcad9ee)
            }
        }

        var fill: Color {
            switch self {
            case .moon:
                return Color(hex: 0xfff3df)
            case .cloud:
                return Color(hex: 0xf0f3fb)
            }
        }

        var symbol: String {
            switch self {
            case .moon:
                return "moon.stars.fill"
            case .cloud:
                return "cloud.fill"
            }
        }
    }

    let title: String
    let items: [String]
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: style.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style.tint)
                Text(title)
                    .font(.custom("HannotateSC-W5", size: 17))
                    .foregroundStyle(Color.warmBrown.opacity(0.82))
            }

            if style == .moon {
                VStack(spacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Text(item)
                            .font(.custom("HannotateSC-W5", size: 20))
                            .foregroundStyle(Color(hex: 0x5f5369))
                        if index < items.count - 1 {
                            Text("↓")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.warmBrown.opacity(0.36))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            } else {
                FlowLayout(items: items)
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: 0xdfd3c4).opacity(0.62), lineWidth: 1)
        }
    }
}

private struct StarMapReminderCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0xd7c4f2))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text("一个温柔提醒")
                    .font(.custom("HannotateSC-W5", size: 17))
                    .foregroundStyle(Color.warmBrown.opacity(0.82))

                Text(text)
                    .font(.custom("HannotateSC-W5", size: 20))
                    .lineSpacing(6)
                    .foregroundStyle(Color(hex: 0x655869))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xf8edf1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: 0xdfd3c4).opacity(0.62), lineWidth: 1)
        }
    }
}

private struct FlowLayout: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.custom("HannotateSC-W5", size: 18))
                    .foregroundStyle(Color(hex: 0x5f5369))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.54), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StarMapBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0xfffbf3),
                    Color(hex: 0xf4efe8),
                    Color(hex: 0xeef3fb),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(hex: 0xd7c4f2).opacity(0.2))
                .frame(width: 220, height: 220)
                .blur(radius: 42)
                .offset(x: 140, y: -240)

            Circle()
                .fill(Color(hex: 0xf4df9b).opacity(0.22))
                .frame(width: 170, height: 170)
                .blur(radius: 40)
                .offset(x: -160, y: 260)

            StarField()
        }
    }
}

private struct StarField: View {
    private let stars: [(CGFloat, CGFloat, CGFloat, UInt)] = [
        (0.15, 0.13, 5, 0xf3d37d),
        (0.82, 0.18, 4, 0xc8d8ef),
        (0.68, 0.31, 6, 0xd7c4f2),
        (0.25, 0.48, 4, 0xf3d37d),
        (0.9, 0.55, 5, 0xf3d37d),
        (0.12, 0.76, 4, 0xc8d8ef),
    ]

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<stars.count, id: \.self) { index in
                let star = stars[index]
                StarDot(size: star.2, color: Color(hex: star.3))
                    .position(x: geometry.size.width * star.0, y: geometry.size.height * star.1)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct StarDot: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size + 5, weight: .medium))
            .foregroundStyle(color.opacity(0.78))
    }
}
