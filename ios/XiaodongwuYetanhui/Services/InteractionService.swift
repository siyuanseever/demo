import Foundation

struct MonsterCareCompletion {
    let careMoment: CareMoment
    let prompt: String
    let fallbackReply: String
}

struct ChatCheckInCompletion {
    let checkIn: EmotionCheckIn
    let careMoment: CareMoment
    let response: String
    let prompt: String
}

struct InteractionService {
    func checkIn(monster: EmotionMonster, intensity: Double, note: String) -> ChatCheckInCompletion {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkIn = EmotionCheckIn(
            monster: monster,
            intensity: intensity,
            note: trimmedNote,
            createdAt: Date()
        )
        let response = Self.response(for: checkIn)
        let notePart = trimmedNote.isEmpty ? "" : "，备注：\(trimmedNote)"
        return ChatCheckInCompletion(
            checkIn: checkIn,
            careMoment: CareMoment(
                id: UUID().uuidString,
                title: "\(monster.name) \(checkIn.intensityLabel)",
                detail: trimmedNote.isEmpty ? monster.prompt : trimmedNote,
                systemImageName: monster.systemImageName,
                tintHex: monster.colorHex,
                createdAt: Date()
            ),
            response: response,
            prompt: "我刚刚做了一个情绪小怪兽 check-in：\(monster.name)，强度是\(checkIn.intensityLabel)\(notePart)。请根据这个 check-in 温柔地回应我。"
        )
    }

    func monsterCare(
        monster: EmotionMonster,
        action: MonsterCareAction,
        safePlace: MonsterSafePlace,
        customName: String,
        note: String
    ) -> MonsterCareCompletion {
        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? monster.name : trimmedName
        let notePart = trimmedNote.isEmpty ? "" : " 我还留了一句话：\(trimmedNote)。"
        let detail = "\(safePlace.detail) \(action.message)"
        return MonsterCareCompletion(
            careMoment: CareMoment(
                id: UUID().uuidString,
                title: "\(displayName) · \(safePlace.title)",
                detail: trimmedNote.isEmpty ? detail : trimmedNote,
                systemImageName: action.systemImageName,
                tintHex: monster.colorHex,
                createdAt: Date()
            ),
            prompt: "我刚刚玩了一个情绪小怪兽照顾游戏。我选择的是\(monster.name)，给它的小名是“\(displayName)”，把它安置在“\(safePlace.title)”，动作是“\(action.title)”。\(safePlace.detail)\(action.message)\(notePart) \(safePlace.reflectionHint) \(action.reflectionPrompt)",
            fallbackReply: "我看到你把\(displayName)安置在“\(safePlace.title)”，也选择了“\(action.title)”。\(safePlace.detail)\(action.message) 这个动作已经在表达一种需要：它不一定要被解释清楚，但它需要被温柔地对待。"
        )
    }

    func offers(
        latestCheckIn: EmotionCheckIn?,
        journals: [JournalEntry],
        messages: [ChatMessage]
    ) -> [CompanionInteractionOffer] {
        let base = CompanionFixtures.interactionOffers
        let recentText = (
            messages.suffix(6).map(\.content).joined(separator: " ") + " " +
            journals.prefix(3).map { "\($0.dominantEmotion) \($0.summary) \($0.suggestedNextStep)" }.joined(separator: " ")
        )

        let preferredID: String
        if let latestCheckIn {
            switch latestCheckIn.monster.id {
            case "anxious":
                preferredID = "room-anchor"
            case "angry":
                preferredID = "boundary-card"
            case "sad", "tired":
                preferredID = "monster-care"
            default:
                preferredID = "monster-check-in"
            }
        } else if Self.shouldSuggestEmotionCheckIn(from: recentText) {
            preferredID = "monster-check-in"
        } else if recentText.localizedCaseInsensitiveContains("边界") || recentText.localizedCaseInsensitiveContains("愤怒") {
            preferredID = "boundary-card"
        } else {
            preferredID = "room-anchor"
        }

        return base.sorted { first, second in
            if first.id == preferredID { return true }
            if second.id == preferredID { return false }
            return first.title < second.title
        }
    }

    func shouldSuggestEmotionCheckIn(from text: String) -> Bool {
        Self.shouldSuggestEmotionCheckIn(from: text)
    }

    private static func shouldSuggestEmotionCheckIn(from text: String) -> Bool {
        let keywords = [
            "累", "疲惫", "撑不住", "难过", "伤心", "焦虑", "心慌", "慌",
            "生气", "愤怒", "边界", "害怕", "紧张", "tired", "anxious", "sad",
        ]
        return keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func response(for checkIn: EmotionCheckIn) -> String {
        let notePart = checkIn.note.isEmpty ? "" : "你还给它留了一句话：“\(checkIn.note)”。"
        switch checkIn.monster.id {
        case "tired":
            return "我看到一只\(checkIn.intensityLabel) \(checkIn.monster.name)。今晚可以先把“继续努力”放远一点，给身体一个更小的任务。\(notePart)"
        case "sad":
            return "\(checkIn.monster.name)来了，说明难过可能需要一点位置。先不用解释它，允许它在旁边坐一会儿。\(notePart)"
        case "anxious":
            return "\(checkIn.monster.name)绕得有点快。我们先找一个能确认现实安全的小锚点，比如脚底、杯子、房间里的光。\(notePart)"
        case "angry":
            return "\(checkIn.monster.name)在保护你。它不一定要立刻行动，但它提醒你：这里也许有一个边界需要被看见。\(notePart)"
        case "clear":
            return "\(checkIn.monster.name)带来一点清亮。可以只保留一个很小的下一步，不用把整条路都想完。\(notePart)"
        default:
            return "这只\(checkIn.monster.name)被你看见了。先让它待在这里，我们不急着把它变成结论。\(notePart)"
        }
    }
}
