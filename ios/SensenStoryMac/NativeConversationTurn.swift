import Foundation

struct NativeConversationTurn: Identifiable {
    let id: String
    let user: ChatMessage
    let replies: [ChatMessage]

    static func build(from messages: [ChatMessage]) -> [NativeConversationTurn] {
        var turns: [NativeConversationTurn] = []
        var currentUser: ChatMessage?
        var currentReplies: [ChatMessage] = []

        func flush() {
            if let currentUser {
                turns.append(
                    NativeConversationTurn(
                        id: currentUser.id,
                        user: currentUser,
                        replies: currentReplies
                    )
                )
            }
        }

        for message in messages {
            if message.role == .user {
                flush()
                currentUser = message
                currentReplies = []
            } else if message.role == .assistant, currentUser != nil {
                currentReplies.append(message)
            }
        }
        flush()
        return turns
    }
}
