import SwiftUI
import UIKit

struct CompanionGardenView: View {
    @AppStorage("bailan.latestDiary") private var savedDiary = ""
    @AppStorage("bailan.dontCareItems") private var savedDontCareItems = ""

    @State private var diaryText = ""
    @State private var diaryReply = ""
    @State private var dontCareText = ""
    @State private var bailanMessage = "今天不想管了"
    @State private var rabbitState = BailanRabbitState.layingDown
    @State private var heroImageName = "bailan-background"
    @State private var pressureWordsVisible = true
    @State private var shakeCount = 0
    @State private var showOtherAlert = false
    @FocusState private var focusedField: BailanField?

    private let bailanMessages = [
        "今天不想管了",
        "爱咋咋地吧",
        "起床已经很厉害了",
        "其他以后再说",
        "先躺着",
        "没有意义也行",
        "不想努力了",
        "今日到此为止",
    ]

    private let diaryReplies = [
        "收到，烂得很真实",
        "嗯，先放这儿",
        "好，今天就这样",
        "不处理，先存着",
        "这事明天也不一定管",
    ]

    private let bailanVisuals: [(imageName: String, state: BailanRabbitState)] = [
        ("bailan-rabbit-couch", .layingDown),
        ("bailan-world-pause", .watchingCeiling),
        ("bailan-destroy-button", .turningOver),
        ("bailan-sticker-sheet", .pretendingNotToHear),
        ("bailan-sticker-suanle", .faceDown),
        ("bailan-sticker-dont-care", .pretendingNotToHear),
        ("bailan-sticker-lie-down", .layingDown),
        ("bailan-sticker-milk-tea", .watchingCeiling),
        ("bailan-sticker-tomorrow", .layingDown),
        ("bailan-sticker-not-moving", .faceDown),
        ("bailan-sticker-not-listening", .pretendingNotToHear),
        ("bailan-sticker-tired", .watchingCeiling),
        ("bailan-sticker-no-meaning", .turningOver),
        ("bailan-sticker-none-of-my-business", .pretendingNotToHear),
        ("bailan-sticker-tomorrow-chips", .layingDown),
        ("bailan-sticker-lying-flat", .layingDown),
        ("bailan-sticker-not-listening-blanket", .pretendingNotToHear),
        ("bailan-sticker-tired-table", .watchingCeiling),
        ("bailan-sticker-no-meaning-phone", .turningOver),
        ("bailan-sticker-none-of-my-business-butterfly", .pretendingNotToHear),
    ]

    private var dontCareItems: [String] {
        savedDontCareItems
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: 0xf1eadf)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 34) {
                        hero(height: max(geometry.size.height - 56, 650))
                        diary
                            .padding(.horizontal, 22)
                        todayPlan
                            .padding(.horizontal, 22)
                        dontCareList
                            .padding(.horizontal, 22)

                        Text("一个不帮助你变好的 App。")
                            .font(.custom("HannotateSC-W5", size: 14))
                            .foregroundStyle(Color(hex: 0x55504a).opacity(0.72))
                            .padding(.top, 4)
                            .padding(.bottom, 126)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .modifier(BailanShakeEffect(animatableData: CGFloat(shakeCount)))
        .alert("算了，别点了。", isPresented: $showOtherAlert) {
            Button("行吧", role: .cancel) {}
        }
    }

    private func hero(height: CGFloat) -> some View {
        ZStack {
            BailanBundleImage(name: heroImageName)
                .aspectRatio(contentMode: heroImageName == "bailan-background" ? .fill : .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .id(heroImageName)
                .transition(.opacity)

            VStack {
                if pressureWordsVisible {
                    HStack(spacing: 12) {
                        ForEach(["面试", "相亲", "简历", "KPI", "未来"], id: \.self) { word in
                            Text(word)
                                .font(.custom("HannotateSC-W5", size: 12))
                                .foregroundStyle(Color(hex: 0x5c5751))
                        }
                    }
                    .transition(.opacity)
                } else {
                    Text(bailanMessage)
                        .font(.custom("HannotateSC-W5", size: 18))
                        .foregroundStyle(Color(hex: 0x38342f))
                        .transition(.opacity)
                }

                Spacer()

                Text(rabbitState.title)
                    .font(.custom("HannotateSC-W5", size: 13))
                    .foregroundStyle(Color(hex: 0x55504a).opacity(0.72))
                    .padding(.bottom, 28)
            }

            Button(action: bailan) {
                Color.black.opacity(0.001)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("算了")
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var diary: some View {
        BailanSection(title: "摆烂日记", subtitle: "今天烂成什么样？") {
            VStack(spacing: 10) {
                TextField("随便写，写完也不用处理。", text: $diaryText, axis: .vertical)
                    .font(.custom("HannotateSC-W5", size: 16))
                    .lineLimit(2...5)
                    .focused($focusedField, equals: .diary)
                    .padding(12)
                    .background(Color(hex: 0xe4ddd3), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(diaryReply.isEmpty ? (savedDiary.isEmpty ? "" : "嗯，先放这儿") : diaryReply)
                        .font(.custom("HannotateSC-W5", size: 13))
                        .foregroundStyle(Color(hex: 0x5a554f))
                    Spacer()
                    Button("放这儿") {
                        submitDiary()
                    }
                    .font(.custom("HannotateSC-W5", size: 14))
                    .foregroundStyle(Color(hex: 0x3d3934))
                    .buttonStyle(.plain)
                    .disabled(diaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(diaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                }
            }
        }
    }

    private var todayPlan: some View {
        BailanSection(title: "今日计划", subtitle: nil) {
            VStack(alignment: .leading, spacing: 12) {
                BailanPlanRow(title: "起床", isDone: true)
                BailanPlanRow(title: "活着", isDone: true)
                Button {
                    showOtherAlert = true
                } label: {
                    BailanPlanRow(title: "其他", isDone: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dontCareList: some View {
        BailanSection(title: "不想管清单", subtitle: "扔到角落就行") {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    TextField("面试、相亲、KPI……", text: $dontCareText)
                        .font(.custom("HannotateSC-W5", size: 15))
                        .focused($focusedField, equals: .dontCare)
                        .submitLabel(.done)
                        .onSubmit(addDontCareItem)

                    Button(action: addDontCareItem) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0x393530))
                            .frame(width: 34, height: 34)
                            .background(Color(hex: 0x9a9d78), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: 0x716b64), lineWidth: 1.5)
                }

                if dontCareItems.isEmpty {
                    Text("角落还是空的。")
                        .font(.custom("HannotateSC-W5", size: 13))
                        .foregroundStyle(Color(hex: 0x625d57).opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                        ForEach(Array(dontCareItems.enumerated()), id: \.offset) { index, item in
                            Button {
                                removeDontCareItem(at: index)
                            } label: {
                                Text(item)
                                    .font(.custom("HannotateSC-W5", size: 13))
                                    .foregroundStyle(Color(hex: 0x393530))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(10)
                                    .frame(minWidth: 72, minHeight: 54)
                                    .background(Color(hex: 0xd8d1c6), in: RoundedRectangle(cornerRadius: 16))
                                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -3 : 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("把\(item)丢掉")
                            .accessibilityHint("不会再次确认")
                        }
                    }
                }
            }
        }
    }

    private func bailan() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let isFirstTap = pressureWordsVisible
        bailanMessage = bailanMessages.randomElement() ?? "先躺着"

        if heroImageName == "bailan-destroy-button" {
            heroImageName = "bailan-world-destroyed"
            rabbitState = .layingDown
        } else if isFirstTap {
            heroImageName = "bailan-sticker-suanle"
            rabbitState = .faceDown
        } else {
            let candidates = bailanVisuals.filter { $0.imageName != heroImageName }
            let visual = candidates.randomElement() ?? ("bailan-rabbit-couch", .layingDown)
            heroImageName = visual.imageName
            rabbitState = visual.state
        }

        focusedField = nil
        withAnimation(.linear(duration: 0.42)) {
            pressureWordsVisible = false
            shakeCount += 1
        }
    }

    private func submitDiary() {
        let entry = diaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        savedDiary = entry
        diaryReply = diaryReplies.randomElement() ?? "嗯，先放这儿"
        diaryText = ""
        focusedField = nil
    }

    private func addDontCareItem() {
        let item = dontCareText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        savedDontCareItems = (dontCareItems + [item]).joined(separator: "\n")
        dontCareText = ""
        focusedField = nil
    }

    private func removeDontCareItem(at index: Int) {
        var items = dontCareItems
        guard items.indices.contains(index) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        items.remove(at: index)
        withAnimation(.easeOut(duration: 0.2)) {
            savedDontCareItems = items.joined(separator: "\n")
        }
    }
}

private enum BailanField {
    case diary
    case dontCare
}

private enum BailanRabbitState: CaseIterable {
    case layingDown
    case faceDown
    case turningOver
    case watchingCeiling
    case pretendingNotToHear

    var title: String {
        switch self {
        case .layingDown: return "躺着"
        case .faceDown: return "趴着"
        case .turningOver: return "翻身"
        case .watchingCeiling: return "看天花板"
        case .pretendingNotToHear: return "假装没听见"
        }
    }

}

private struct BailanSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("HannotateSC-W5", size: 20))
                    .foregroundStyle(Color(hex: 0x302c28))
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("HannotateSC-W5", size: 13))
                        .foregroundStyle(Color(hex: 0x625d57))
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BailanPlanRow: View {
    let title: String
    let isDone: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark.square.fill" : "square")
                .foregroundStyle(isDone ? Color(hex: 0x747850) : Color(hex: 0x68625b))
            Text(title)
                .font(.custom("HannotateSC-W5", size: 16))
                .foregroundStyle(Color(hex: 0x37332f))
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

private struct BailanShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 5 * sin(animatableData * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

private struct BailanBundleImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = UIImage(named: name) ?? UIImage(named: "\(name).png") {
                Image(uiImage: image)
                    .resizable()
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
