import Foundation

struct RecommendationCompletion {
    let recommendation: CompanionRecommendation
    let prompt: String
    let fallbackReply: String
}

struct RecommendationService {
    func recommendation(
        preferredMedium: RecommendationMedium?,
        latestCheckIn: EmotionCheckIn?,
        journals: [JournalEntry],
        messages: [ChatMessage],
        excluding existingIDs: Set<String>
    ) -> RecommendationCompletion {
        let context = contextText(journals: journals, messages: messages, latestCheckIn: latestCheckIn)
        let candidates = Self.candidates.filter { candidate in
            preferredMedium.map { candidate.medium == $0 } ?? true
        }
        let pool = candidates.isEmpty ? Self.candidates : candidates
        let available = pool.filter { !existingIDs.contains($0.id) }
        let selected = refreshed(bestCandidate(from: available.isEmpty ? pool : available, context: context, latestCheckIn: latestCheckIn))
        return completion(for: selected)
    }

    func completion(for recommendation: CompanionRecommendation) -> RecommendationCompletion {
        let reason = recommendation.reason.trimmingCharacters(in: CharacterSet(charactersIn: "。.!！ "))
        return RecommendationCompletion(
            recommendation: recommendation,
            prompt: "我想把这个今晚推荐带进对话：\(recommendation.medium.displayName)《\(recommendation.title)》\(recommendation.creator.isEmpty ? "" : "，\(recommendation.creator)")。它适合我的原因是：\(reason)。请结合我刚才的状态，告诉我可以怎样轻轻地靠近它，不要给太多任务。",
            fallbackReply: "今晚可以先靠近《\(recommendation.title)》。不用完整读完或听完，只取一小段，让它成为一个柔软的支点。\(recommendation.practice)"
        )
    }

    private func contextText(
        journals: [JournalEntry],
        messages: [ChatMessage],
        latestCheckIn: EmotionCheckIn?
    ) -> String {
        let recent = messages.suffix(8).map(\.content).joined(separator: " ")
        let journalText = journals.prefix(3)
            .map { "\($0.dominantEmotion) \($0.summary) \($0.suggestedNextStep)" }
            .joined(separator: " ")
        let monsterText = latestCheckIn.map { "\($0.monster.id) \($0.monster.name) \($0.note)" } ?? ""
        return "\(recent) \(journalText) \(monsterText)"
    }

    private func bestCandidate(
        from candidates: [CompanionRecommendation],
        context: String,
        latestCheckIn: EmotionCheckIn?
    ) -> CompanionRecommendation {
        let preferredTone = tone(from: context, latestCheckIn: latestCheckIn)
        return candidates.max { first, second in
            score(first, tone: preferredTone, context: context) < score(second, tone: preferredTone, context: context)
        } ?? Self.candidates[0]
    }

    private func tone(from context: String, latestCheckIn: EmotionCheckIn?) -> String {
        if let latestCheckIn {
            switch latestCheckIn.monster.id {
            case "tired":
                return "rest"
            case "sad":
                return "softness"
            case "anxious":
                return "grounding"
            case "angry":
                return "boundary"
            default:
                return "clarity"
            }
        }
        if context.localizedCaseInsensitiveContains("累") || context.localizedCaseInsensitiveContains("疲惫") {
            return "rest"
        }
        if context.localizedCaseInsensitiveContains("焦虑") || context.localizedCaseInsensitiveContains("慌") {
            return "grounding"
        }
        if context.localizedCaseInsensitiveContains("边界") || context.localizedCaseInsensitiveContains("生气") {
            return "boundary"
        }
        if context.localizedCaseInsensitiveContains("难过") || context.localizedCaseInsensitiveContains("伤心") {
            return "softness"
        }
        return "clarity"
    }

    private func score(_ recommendation: CompanionRecommendation, tone: String, context: String) -> Int {
        var value = 0
        let searchable = "\(recommendation.reason) \(recommendation.practice)"
        if searchable.localizedCaseInsensitiveContains(tone) {
            value += 10
        }
        if tone == "rest" && (searchable.contains("休息") || searchable.contains("慢")) {
            value += 8
        }
        if tone == "grounding" && (searchable.contains("安定") || searchable.contains("现实")) {
            value += 8
        }
        if tone == "boundary" && (searchable.contains("边界") || searchable.contains("力量")) {
            value += 8
        }
        if tone == "softness" && (searchable.contains("柔软") || searchable.contains("允许")) {
            value += 8
        }
        if context.localizedCaseInsensitiveContains(recommendation.title) {
            value -= 6
        }
        return value
    }

    private func refreshed(_ recommendation: CompanionRecommendation) -> CompanionRecommendation {
        CompanionRecommendation(
            id: recommendation.id,
            medium: recommendation.medium,
            title: recommendation.title,
            creator: recommendation.creator,
            reason: recommendation.reason,
            practice: recommendation.practice,
            tintHex: recommendation.tintHex,
            createdAt: Date()
        )
    }

    private static let candidates: [CompanionRecommendation] = [
        CompanionRecommendation(
            id: "book-the-little-prince",
            medium: .book,
            title: "小王子",
            creator: "圣埃克苏佩里",
            reason: "适合在需要柔软和距离感的时候读一点点，它不要求你马上变强。",
            practice: "只读一小段，把最像今晚的一句话留下来。",
            tintHex: 0xf6dda2,
            createdAt: Date()
        ),
        CompanionRecommendation(
            id: "book-the-art-of-stillness",
            medium: .book,
            title: "静止的艺术",
            creator: "皮科·艾尔",
            reason: "适合疲惫、想从外界评价里退出来的时候，给休息一点合法性。",
            practice: "只读目录或一页，让身体知道今晚可以慢下来。",
            tintHex: 0xcfe2ec,
            createdAt: Date()
        ),
        CompanionRecommendation(
            id: "music-gymnopedie",
            medium: .music,
            title: "Gymnopedie No.1",
            creator: "Erik Satie",
            reason: "节奏很慢，适合把焦虑从脑子带回房间和身体。",
            practice: "听前 90 秒，注意一个真实的声音和一次呼气。",
            tintHex: 0xded7ef,
            createdAt: Date()
        ),
        CompanionRecommendation(
            id: "music-weightless",
            medium: .music,
            title: "Weightless",
            creator: "Marconi Union",
            reason: "适合想要安定下来但不想被歌词打扰的时候。",
            practice: "把音量调低，只让它像一盏背景小灯。",
            tintHex: 0xcfe6bf,
            createdAt: Date()
        ),
        CompanionRecommendation(
            id: "movie-perfect-days",
            medium: .movie,
            title: "Perfect Days",
            creator: "Wim Wenders",
            reason: "适合需要从小事里重新找一点秩序和掌控感的时候。",
            practice: "不必看完，只看一段日常动作，把一个能复制的小动作带回今晚。",
            tintHex: 0xe8f3de,
            createdAt: Date()
        ),
        CompanionRecommendation(
            id: "movie-kikis-delivery-service",
            medium: .movie,
            title: "魔女宅急便",
            creator: "宫崎骏",
            reason: "适合自我怀疑、觉得能力突然消失的时候，它保留了温柔和重新开始的空间。",
            practice: "看一小段低落后的日常，不急着找答案。",
            tintHex: 0xf0b18f,
            createdAt: Date()
        ),
    ]
}
