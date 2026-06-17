import SwiftUI
import UIKit

struct CompanionGardenView: View {
    @State private var selectedPlace: ForestPlace?

    private let places = ForestPlace.all

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let fullHeight = geometry.size.height + safeTop + safeBottom
            let backgroundOffset = -(safeTop - safeBottom) / 2

            ZStack {
                ForestBundleImage(name: "forest_map_background")
                    .frame(width: geometry.size.width, height: fullHeight)
                    .offset(y: backgroundOffset)
                    .clipped()
                    .ignoresSafeArea(.all)

                ForestMapOverlay(
                    places: places,
                    selectedPlace: $selectedPlace
                )
                .frame(width: geometry.size.width, height: fullHeight)
                .offset(y: backgroundOffset)

                if let selectedPlace {
                    ForestPlaceDetail(place: selectedPlace) {
                        self.selectedPlace = nil
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 112)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.snappy, value: selectedPlace)
            .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
    }
}

private struct ForestMapOverlay: View {
    let places: [ForestPlace]
    @Binding var selectedPlace: ForestPlace?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(places) { place in
                    ForestPlaceTag(place: place) {
                        selectedPlace = place
                    }
                    .frame(width: geometry.size.width * place.widthRatio)
                    .position(
                        x: geometry.size.width * place.xRatio,
                        y: geometry.size.height * place.yRatio
                    )
                }

                ForestCornerTag(
                    title: "忧忧兔的悄悄话",
                    subtitle: "一小句安静的陪伴"
                ) {
                    selectedPlace = ForestPlace.whisper
                }
                .frame(width: geometry.size.width * 0.34)
                .position(x: geometry.size.width * 0.22, y: geometry.size.height * 0.84)

                ForestCornerTag(
                    title: "星光瓶",
                    subtitle: "收藏被照亮的瞬间"
                ) {
                    selectedPlace = ForestPlace.bottle
                }
                .frame(width: geometry.size.width * 0.34)
                .position(x: geometry.size.width * 0.78, y: geometry.size.height * 0.84)
            }
        }
    }
}

private struct ForestPlaceTag: View {
    let place: ForestPlace
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(place.title)
                    .font(.custom("HannotateSC-W5", size: 14))
                    .foregroundStyle(Color(hex: 0x6a4f34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(place.subtitle)
                    .font(.custom("HannotateSC-W5", size: 9.5))
                    .foregroundStyle(Color(hex: 0x6a4f34).opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color(hex: 0xfff7e9).opacity(0.84), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color(hex: 0x5a3b24).opacity(0.12), radius: 7, x: 0, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.title)，\(place.subtitle)")
    }
}

private struct ForestCornerTag: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.custom("HannotateSC-W5", size: 13))
                    .foregroundStyle(Color(hex: 0x6a4f34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(subtitle)
                    .font(.custom("HannotateSC-W5", size: 9))
                    .foregroundStyle(Color(hex: 0x6a4f34).opacity(0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0x5a3b24).opacity(0.1), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct ForestPlaceDetail: View {
    let place: ForestPlace
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.title)
                        .font(.custom("HannotateSC-W5", size: 19))
                        .foregroundStyle(Color(hex: 0x5f452d))

                    Text(place.subtitle)
                        .font(.custom("HannotateSC-W5", size: 13))
                        .foregroundStyle(Color(hex: 0x7a6047).opacity(0.76))
                }

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x7a6047))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text(place.detail)
                .font(.custom("HannotateSC-W5", size: 14))
                .lineSpacing(5)
                .foregroundStyle(Color(hex: 0x5f452d).opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .background(Color(hex: 0xfff7e9).opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x3d2b1d).opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct ForestBundleImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = UIImage(named: name) ?? UIImage(named: "\(name).png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0x162315)
            }
        }
    }
}

private struct ForestPlace: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let xRatio: CGFloat
    let yRatio: CGFloat
    let widthRatio: CGFloat

    static let all: [ForestPlace] = [
        ForestPlace(
            id: "thinking-cabin",
            title: "思考小屋",
            subtitle: "最近常想的事",
            detail: "这里会慢慢收起你反复回到的问题。不是为了立刻解决，而是看见它为什么总在敲门。",
            xRatio: 0.31,
            yRatio: 0.18,
            widthRatio: 0.31
        ),
        ForestPlace(
            id: "emotion-pond",
            title: "情绪池塘",
            subtitle: "最近的心情流动",
            detail: "池塘会映出最近情绪的流向：哪些感受靠近了，哪些感受还在水面下面。",
            xRatio: 0.69,
            yRatio: 0.26,
            widthRatio: 0.32
        ),
        ForestPlace(
            id: "record-path",
            title: "记录小径",
            subtitle: "你留下的文字和瞬间",
            detail: "那些随手写下的句子、片段和瞬间，会在这里连成一条可以慢慢回看的小路。",
            xRatio: 0.25,
            yRatio: 0.39,
            widthRatio: 0.34
        ),
        ForestPlace(
            id: "reading-hollow",
            title: "阅读树洞",
            subtitle: "读过的书和触动",
            detail: "这里保存读到某句话时，心里轻轻动了一下的地方。",
            xRatio: 0.75,
            yRatio: 0.42,
            widthRatio: 0.34
        ),
        ForestPlace(
            id: "inspiration-tent",
            title: "灵感帐篷",
            subtitle: "那些突然出现的想法",
            detail: "还没成形的念头可以先在帐篷里住一晚，不急着变成计划。",
            xRatio: 0.26,
            yRatio: 0.58,
            widthRatio: 0.34
        ),
        ForestPlace(
            id: "important-moments",
            title: "重要时刻",
            subtitle: "值得被记住的日子",
            detail: "有些日子不一定宏大，但它们确实改变了一点点你看自己的方式。",
            xRatio: 0.74,
            yRatio: 0.59,
            widthRatio: 0.34
        ),
        ForestPlace(
            id: "growth-garden",
            title: "成长花园",
            subtitle: "正在悄悄长大的自己",
            detail: "这里不记录分数，只记录那些正在变得更稳、更柔软、更有生命力的部分。",
            xRatio: 0.5,
            yRatio: 0.72,
            widthRatio: 0.38
        ),
    ]

    static let whisper = ForestPlace(
        id: "yoyo-whisper",
        title: "忧忧兔的悄悄话",
        subtitle: "一小句安静的陪伴",
        detail: "等你愿意停一停，忧忧兔会在这里留下一句不催促你的话。",
        xRatio: 0.22,
        yRatio: 0.84,
        widthRatio: 0.34
    )

    static let bottle = ForestPlace(
        id: "starlight-bottle",
        title: "星光瓶",
        subtitle: "收藏被照亮的瞬间",
        detail: "那些短暂发亮的片刻，会先被放进瓶子里，等你以后再回来看看。",
        xRatio: 0.78,
        yRatio: 0.84,
        widthRatio: 0.34
    )
}
