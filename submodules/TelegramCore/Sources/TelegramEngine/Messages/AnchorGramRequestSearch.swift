import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

public enum AnchorGramRequestSearchError {
    case unavailable
    case network
}

public struct AnchorGramRequestSearchPage {
    public let texts: [String]
    public let nextOffset: Int32?
    public let completed: Bool
}

public extension TelegramEngine.Messages {
    func anchorgramSearchRequests(peerId: PeerId, query: String, offset: Int32 = 0) -> Signal<AnchorGramRequestSearchPage, AnchorGramRequestSearchError> {
        return self.account.postbox.transaction { transaction -> Api.InputPeer? in
            return transaction.getPeer(peerId).flatMap(apiInputPeer)
        }
        |> castError(AnchorGramRequestSearchError.self)
        |> mapToSignal { inputPeer -> Signal<AnchorGramRequestSearchPage, AnchorGramRequestSearchError> in
            guard let inputPeer else { return .fail(.unavailable) }
            return self.account.network.request(Api.functions.messages.search(flags: 0, peer: inputPeer, q: query, fromId: nil, savedPeerId: nil, savedReaction: nil, topMsgId: nil, filter: .inputMessagesFilterEmpty, minDate: 0, maxDate: Int32.max - 1, offsetId: offset, addOffset: 0, limit: 50, maxId: Int32.max - 1, minId: 0, hash: 0))
            |> mapError { _ in AnchorGramRequestSearchError.network }
            |> mapToSignal { result -> Signal<AnchorGramRequestSearchPage, AnchorGramRequestSearchError> in
                let messages: [Api.Message]
                let total: Int32
                switch result {
                case let .messages(data):
                    messages = data.messages
                    total = Int32(messages.count)
                case let .messagesSlice(data):
                    messages = data.messages
                    total = data.count
                case let .channelMessages(data):
                    messages = data.messages
                    total = data.count
                case .messagesNotModified:
                    return .fail(.unavailable)
                }
                var texts: [String] = []
                var ids: [Int32] = []
                for message in messages {
                    switch message {
                    case let .message(data):
                        texts.append(data.message)
                        ids.append(data.id)
                    case let .messageService(data):
                        ids.append(data.id)
                    case let .messageEmpty(data):
                        ids.append(data.id)
                    }
                }
                let next = ids.filter { $0 > 0 }.min()
                let completed = messages.count < 50 || total <= Int32(messages.count)
                if !completed && (next == nil || (offset != 0 && next! >= offset)) {
                    return .fail(.unavailable)
                }
                return .single(AnchorGramRequestSearchPage(texts: texts, nextOffset: next, completed: completed))
            }
        }
    }
}
