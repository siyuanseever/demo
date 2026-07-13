import SwiftUI

struct NativeConversationView: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var draft = ""
    @State private var hoveredTurnID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusArea
            conversationBody
            Divider()
            composer
        }
        .background(
            LinearGradient(
                colors: [Color.conversationBgTop, Color.conversationBgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            NativeCharacterAvatar(
                character: store.selectedCharacter,
                expressionID: store.messages.last(where: { $0.role == .assistant })?.expressionID,
                size: 34
            )
            VStack(alignment: .leading, spacing: 1) {
                Text("和\(store.selectedCharacter.name)夜谈")
                    .font(.headline)
                Text(store.selectedSessionID == nil ? "一段新的夜谈" : "正在继续这段对话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("新夜谈", systemImage: "plus") { store.newConversation() }
            if store.isSending {
                Button("停止", systemImage: "stop.fill") { store.cancelSend() }
            } else {
                Button("结束并总结", systemImage: "sparkles") {
                    Task { await store.closeCurrentSession() }
                }
                .disabled(store.messages.allSatisfy { $0.role != .user })
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var statusArea: some View {
        if store.operationStatus != nil || store.notice != nil || store.latestAssessment != nil || store.closeSummary != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let operationStatus = store.operationStatus {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(operationStatus)
                    }
                    .font(.caption)
                }
                if let notice = store.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let assessment = store.latestAssessment {
                    NativeAssessmentStrip(assessment: assessment)
                }
                if let summary = store.closeSummary {
                    NativeCloseSummaryCard(summary: summary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.thinMaterial)
        }
    }

    private var conversationBody: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                Group {
                    if store.messages.isEmpty {
                        ContentUnavailableView {
                            Label("今晚想从哪里说起？", systemImage: "moon.stars")
                        } description: {
                            Text("不用整理好。先写下一句最靠近此刻的话。")
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(store.messages) { message in
                                    NativeMessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .trailing) {
                    if let turn = turns.first(where: { $0.id == hoveredTurnID }) {
                        NativeTurnPreview(turn: turn)
                            .frame(width: 280)
                            .padding(.trailing, 48)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }

                Divider()
                NativeConversationTrail(
                    turns: turns,
                    hoveredTurnID: $hoveredTurnID,
                    onSelect: { turn in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(turn.user.id, anchor: .top)
                        }
                    }
                )
                .frame(width: 44)
            }
            .onChange(of: store.messages.count) {
                guard let lastID = store.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("慢慢说，我在听…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.inputBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.cardBorder.opacity(0.7))
                )
                .disabled(store.isSending)

            Button("发送", systemImage: "paperplane.fill") { submit() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private var turns: [NativeConversationTurn] {
        NativeConversationTurn.build(from: store.messages)
    }

    private func submit() {
        let text = draft
        draft = ""
        store.send(text)
    }
}

private struct NativeMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                avatar
            } else {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 7) {
                if message.role == .assistant {
                    HStack(spacing: 6) {
                        Text(character.name)
                            .font(.caption.bold())
                        if !message.replyStage.isEmpty {
                            Text(message.replyStage == "quick" ? "先接住你" : "再想深一点")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.overlayLight.opacity(0.82), in: Capsule())
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(message.role == .user ? .secondary : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16))

                if let routeSummary = message.routeSummary, !routeSummary.isEmpty {
                    Label(routeSummary, systemImage: "point.3.filled.connected.trianglepath.dotted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !message.knowledgeCards.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.knowledgeCards.prefix(3)) { card in
                            Label(card.title, systemImage: "leaf.fill")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: 700, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var character: CompanionCharacter {
        CompanionFixtures.character(id: message.characterID) ?? CompanionFixtures.characters[0]
    }

    private var bubbleColor: Color {
        message.role == .user ? Color.overlaySubtle.opacity(0.92) : character.bubbleColor.opacity(0.82)
    }

    private var avatar: some View {
        NativeCharacterAvatar(
            character: character,
            expressionID: message.expressionID,
            size: 38
        )
    }
}

private struct NativeConversationTrail: View {
    let turns: [NativeConversationTurn]
    @Binding var hoveredTurnID: String?
    let onSelect: (NativeConversationTurn) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                ForEach(turns) { turn in
                    Button {
                        onSelect(turn)
                    } label: {
                        Capsule()
                            .fill(hoveredTurnID == turn.id ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: hoveredTurnID == turn.id ? 24 : 9, height: 4)
                            .frame(width: 32, height: 12, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) {
                            hoveredTurnID = hovering ? turn.id : nil
                        }
                    }
                    .help(turn.user.content)
                }
            }
            .padding(.vertical, 18)
        }
    }
}

private struct NativeTurnPreview: View {
    let turn: NativeConversationTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.user.content)
                .font(.callout.bold())
                .lineLimit(3)
            Divider()
            Text(turn.replies.map(\.content).joined(separator: "\n"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(14)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

private struct NativeAssessmentStrip: View {
    let assessment: UserConversationAssessment

    var body: some View {
        HStack(spacing: 8) {
            assessmentItem("状态", assessment.userState)
            assessmentItem("需要", assessment.coreNeed)
            assessmentItem("风险", assessment.riskLevel)
            assessmentItem("策略", assessment.responseMode)
        }
    }

    private func assessmentItem(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.overlaySubtle.opacity(0.82), in: Capsule())
    }
}

private struct NativeCloseSummaryCard: View {
    let summary: SessionCloseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("本轮整理完成", systemImage: "checkmark.seal.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
            Text(summary.journalSummary)
                .font(.caption)
                .lineLimit(4)
            HStack {
                Text("\(summary.memoryCount) 条记忆")
                Text("\(summary.stateProfileCount) 项长期状态更新")
                if let emotion = summary.journal?.dominantEmotion, !emotion.isEmpty {
                    Text(emotion)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
