import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ChatPresentationInterfaceState
import TelegramStringFormatting

private final class AnchorQuickStore {
    static let shared = AnchorQuickStore()
    private var cache: [Int64: [AnchorQuickTarget]] = [:]
    private var recent: [String: TimeInterval] = [:]
    var operations: [String: AnchorQuickSend] = [:]

    func targets(_ account: Int64) -> [AnchorQuickTarget] {
        if let value = self.cache[account] { return value }
        let data = UserDefaults.standard.data(forKey: "anchorgram.quick-forward.\(account)")
        let decoded = data.flatMap { $0.count <= 65536 ? try? JSONDecoder().decode([AnchorQuickTarget].self, from: $0) : nil } ?? []
        let result = Array(decoded.filter { !$0.id.isEmpty && $0.id.count <= 64 && !$0.label.isEmpty && $0.label.count <= 64 && $0.destination.count <= 256 }.prefix(20))
        self.cache[account] = result
        return result
    }

    func save(_ targets: [AnchorQuickTarget], account: Int64) {
        let targets = Array(targets.prefix(20))
        guard let data = try? JSONEncoder().encode(targets) else { return }
        self.cache[account] = targets
        UserDefaults.standard.set(data, forKey: "anchorgram.quick-forward.\(account)")
    }

    func pendingIds(_ ids: [String], key: String) -> [String] {
        let now = ProcessInfo.processInfo.systemUptime
        self.recent = self.recent.filter { now - $0.value < 300 }
        return ids.filter { self.recent[key + ":" + $0] != nil }
    }

    func remember(_ ids: [String], key: String) {
        let now = ProcessInfo.processInfo.systemUptime
        for id in ids { self.recent[key + ":" + id] = now }
        while self.recent.count > 1024, let oldest = self.recent.min(by: { $0.value < $1.value })?.key {
            self.recent.removeValue(forKey: oldest)
        }
    }
}

extension ChatControllerImpl {
    func anchorgramQuickSaved(_ message: EngineRawMessage) {
        let target = AnchorQuickTarget(id: "__saved", label: "Избранное", destination: "Избранное", peer: self.context.account.peerId.toInt64(), thread: nil, requestsOnly: false)
        self.anchorgramQuickSend(message.id, target: target)
    }

    func anchorgramQuickMenu(_ message: EngineRawMessage) {
        let account = self.context.account.peerId.toInt64()
        let alert = UIAlertController(title: "Быстрая отправка", message: "Выбери, куда отправить это сообщение", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "В Избранное · оригинал", style: .default, handler: { [weak self] _ in self?.anchorgramQuickSaved(message) }))
        for target in AnchorQuickStore.shared.targets(account) {
            let mode = target.requestsOnly ? "фото + заявки" : "оригинал"
            alert.addAction(UIAlertAction(title: target.label + " · " + mode, style: .default, handler: { [weak self] _ in
                self?.anchorgramQuickSend(message.id, target: target)
            }))
        }
        alert.addAction(UIAlertAction(title: "Добавить группу…", style: .default, handler: { [weak self] _ in self?.anchorgramQuickChooseGroup(existing: nil) }))
        alert.addAction(UIAlertAction(title: "Редактировать кнопки…", style: .default, handler: { [weak self] _ in self?.anchorgramQuickManage() }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.anchorgramPresent(alert)
    }

    private func anchorgramQuickManage() {
        let targets = AnchorQuickStore.shared.targets(self.context.account.peerId.toInt64())
        if targets.isEmpty { self.anchorgramQuickChooseGroup(existing: nil); return }
        let alert = UIAlertController(title: "Редактировать кнопки", message: nil, preferredStyle: .actionSheet)
        for target in targets {
            alert.addAction(UIAlertAction(title: target.label, style: .default, handler: { [weak self] _ in self?.anchorgramQuickEdit(target) }))
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.anchorgramPresent(alert)
    }

    private func anchorgramQuickChooseGroup(existing: AnchorQuickTarget?) {
        let account = self.context.account.peerId.toInt64()
        if existing == nil && AnchorQuickStore.shared.targets(account).count >= 20 {
            self.anchorgramToast("Можно сохранить не больше 20 кнопок."); return
        }
        let picker = self.context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: self.context, updatedPresentationData: self.updatedPresentationData, filter: [.onlyGroupsAndChannels, .excludeChannels, .onlyWriteable, .excludeDisabled, .doNotSearchMessages], multipleSelection: false, selectForumThreads: true))
        picker.peerSelected = { [weak self, weak picker] peer, thread in
            guard let self else { return }
            if case let .channel(channel) = peer, channel.flags.contains(.isForum), thread == nil {
                self.anchorgramToast("Для форума выбери конкретную тему."); return
            }
            let destination = String(peer.displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder).prefix(200))
            let target = AnchorQuickTarget(id: existing?.id ?? UUID().uuidString, label: existing?.label ?? String(destination.prefix(64)), destination: destination + (thread == nil ? "" : " · тема \(thread!)"), peer: peer.id.toInt64(), thread: thread, requestsOnly: existing?.requestsOnly ?? true)
            picker?.dismiss()
            self.anchorgramQuickEdit(target)
        }
        self.chatDisplayNode.dismissInput()
        self.effectiveNavigationController?.pushViewController(picker)
    }

    private func anchorgramQuickEdit(_ target: AnchorQuickTarget) {
        let account = self.context.account.peerId.toInt64()
        let alert = UIAlertController(title: "Настроить кнопку", message: target.destination + "\nВыбери, что отправлять", preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "Название кнопки"; field.text = target.label }
        for requestsOnly in [true, false] {
            alert.addAction(UIAlertAction(title: requestsOnly ? "Сохранить: фото + заявки" : "Сохранить: оригинал", style: .default, handler: { [weak self, weak alert] _ in
                guard let self else { return }
                let label = String((alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
                guard !label.isEmpty else { self.anchorgramToast("Название не должно быть пустым."); return }
                var updated = target
                updated.label = label
                updated.requestsOnly = requestsOnly
                var targets = AnchorQuickStore.shared.targets(account)
                if let index = targets.firstIndex(where: { $0.id == updated.id }) { targets[index] = updated }
                else if targets.count < 20 { targets.append(updated) }
                else { self.anchorgramToast("Достигнут предел кнопок."); return }
                AnchorQuickStore.shared.save(targets, account: account)
                self.anchorgramToast("Кнопка сохранена")
            }))
        }
        alert.addAction(UIAlertAction(title: "Выбрать другую группу…", style: .default, handler: { [weak self] _ in self?.anchorgramQuickChooseGroup(existing: target) }))
        if AnchorQuickStore.shared.targets(account).contains(where: { $0.id == target.id }) {
            alert.addAction(UIAlertAction(title: "Удалить кнопку", style: .destructive, handler: { [weak self] _ in
                AnchorQuickStore.shared.save(AnchorQuickStore.shared.targets(account).filter { $0.id != target.id }, account: account)
                self?.anchorgramToast("Кнопка удалена")
            }))
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.anchorgramPresent(alert)
    }

    private func anchorgramQuickSend(_ id: MessageId, target: AnchorQuickTarget) {
        let key = "\(self.context.account.peerId.toInt64()):\(target.peer)"
        let store = AnchorQuickStore.shared
        guard store.operations[key] == nil, store.operations.count < 8 else {
            self.anchorgramToast("Отправка уже проверяется. Дождись результата."); return
        }
        let operation = AnchorQuickSend(controller: self, source: id, target: target, key: key)
        store.operations[key] = operation
        operation.start()
    }

    fileprivate func anchorgramPresent(_ alert: UIAlertController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isViewLoaded, self.view.window != nil else { return }
            if let popover = alert.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            }
            self.present(alert, animated: true)
        }
    }

    fileprivate func anchorgramToast(_ text: String) {
        guard self.isViewLoaded, self.view.window != nil else { return }
        let tag = 1095192902
        self.view.viewWithTag(tag)?.removeFromSuperview()
        let label = UILabel()
        label.tag = tag
        label.text = text
        label.numberOfLines = 4
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0.1, alpha: 0.96)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        let width = max(100, min(self.view.bounds.width - 32, 360))
        let height = min(120, label.sizeThatFits(CGSize(width: width - 24, height: 100)).height + 24)
        label.frame = CGRect(x: (self.view.bounds.width - width) / 2, y: self.view.safeAreaInsets.top + 60, width: width, height: height)
        self.view.addSubview(label)
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak label] in label?.removeFromSuperview() }
    }
}

private final class AnchorQuickSend {
    private weak var controller: ChatControllerImpl?
    private let source: MessageId
    private let target: AnchorQuickTarget
    private let key: String
    private let disposable = MetaDisposable()
    private var deadline: DispatchWorkItem?
    private var snapshot: EngineRawMessage?
    private var payload: EnqueueMessage?
    private var ids: [String] = []
    private var index = 0
    private var pages = 0
    private var active = true
    private var enqueuing = false
    private var confirmation: UIAlertController?

    init(controller: ChatControllerImpl, source: MessageId, target: AnchorQuickTarget, key: String) {
        self.controller = controller
        self.source = source
        self.target = target
        self.key = key
    }

    deinit { self.disposable.dispose(); self.deadline?.cancel() }

    func start() {
        self.armTimeout(20)
        self.prepare(approved: false)
    }

    private func armTimeout(_ seconds: Double) {
        self.deadline?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fail(self.enqueuing ? "Статус отправки не подтверждён. Проверь группу перед повтором." : "Проверка отменена по таймауту. Ничего не отправлено.")
        }
        self.deadline = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func configured(_ controller: ChatControllerImpl) -> Bool {
        return self.target.id == "__saved" || AnchorQuickStore.shared.targets(controller.context.account.peerId.toInt64()).contains(self.target)
    }

    private func prepare(approved: Bool) {
        guard self.active, let controller = self.controller else { self.finish(); return }
        guard self.configured(controller) else { self.fail("Настройки кнопки изменились. Повтори отправку."); return }
        let peerId = PeerId(self.target.peer)
        self.disposable.set((controller.context.engine.data.get(
            TelegramEngine.EngineData.Item.Messages.Message(id: self.source),
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
            TelegramEngine.EngineData.Item.Peer.Peer(id: self.source.peerId),
            TelegramEngine.EngineData.Item.Peer.SendPaidMessageStars(id: peerId)
        ) |> deliverOnMainQueue).start(next: { [weak self] message, peer, sourcePeer, paid in
            guard let self, self.active else { return }
            guard let controller = self.controller else { self.finish(); return }
            guard let message = message?._asMessage(), let peer, let sourcePeer else { self.fail("Сообщение или группа больше недоступны."); return }
            guard !message.isCopyProtected(), !message.containsSecretMedia, !self.copyProtected(sourcePeer), self.source.peerId.namespace != Namespaces.Peer.SecretChat,
                message.flags.intersection([.Unsent, .Sending, .Failed]).isEmpty else {
                self.fail("Это сообщение нельзя переслать."); return
            }
            if paid != nil { self.fail("Для платного чата используй обычную пересылку с подтверждением оплаты."); return }
            guard canSendMessagesToPeer(peer) else { self.fail("Нет права отправлять сообщения в этот чат."); return }
            if let error = self.permissionError(peer) { self.fail(error); return }
            if approved, let snapshot = self.snapshot, snapshot.stableVersion != message.stableVersion || snapshot.text != message.text {
                self.fail("Исходное сообщение изменилось. Повтори отправку."); return
            }
            if self.target.requestsOnly {
                guard let caption = AnchorQuickRules.latestRequests(message.text),
                    let photo = message.media.compactMap({ $0 as? TelegramMediaImage }).first,
                    message.groupingKey == nil else {
                    self.fail("Нужны одно фото и распознаваемый блок «Последние заявки». Ничего не отправлено."); return
                }
                self.payload = .message(text: caption, attributes: [], inlineStickers: [:], mediaReference: .message(message: MessageReference(message), media: photo), threadId: self.target.thread, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                self.ids = AnchorQuickRules.requestIds(caption)
            } else {
                self.payload = .forward(source: message.id, threadId: self.target.thread, grouping: .auto, attributes: [], correlationId: nil)
                self.ids = AnchorQuickRules.requestIds(message.text)
            }
            guard self.ids.count <= 20 else { self.fail("Слишком много заявок для быстрой проверки. Ничего не отправлено."); return }
            self.snapshot = message
            if approved || self.ids.isEmpty || self.target.id == "__saved" { self.enqueue(); return }
            let pending = AnchorQuickStore.shared.pendingIds(self.ids, key: self.key)
            if !pending.isEmpty { self.askDuplicate(pending, pending: true); return }
            controller.anchorgramToast("Проверяю заявки в группе…")
            self.search(offset: 0)
        }))
    }

    private func copyProtected(_ peer: EnginePeer) -> Bool {
        switch peer {
        case let .channel(channel): return channel.flags.contains(.copyProtectionEnabled)
        case let .legacyGroup(group): return group.flags.contains(.copyProtectionEnabled)
        default: return false
        }
    }

    private func permissionError(_ peer: EnginePeer) -> String? {
        switch peer {
        case let .channel(channel):
            if channel.isRestrictedBySlowmode { return "Для группы с медленным режимом используй обычную пересылку." }
            if channel.hasBannedPermission(.banSendText) != nil || (self.target.requestsOnly && channel.hasBannedPermission(.banSendPhotos) != nil) { return "В группе запрещён этот тип сообщений." }
        case let .legacyGroup(group):
            if group.hasBannedPermission(.banSendText) || (self.target.requestsOnly && group.hasBannedPermission(.banSendPhotos)) { return "В группе запрещён этот тип сообщений." }
        default: break
        }
        return nil
    }

    private func search(offset: Int32) {
        guard self.active, let controller = self.controller else { self.finish(); return }
        guard self.index < self.ids.count else { self.prepare(approved: true); return }
        let id = self.ids[self.index]
        let query = id.contains("_") ? id : String(id.prefix(8))
        self.disposable.set((controller.context.engine.messages.anchorgramSearchRequests(peerId: PeerId(self.target.peer), query: query, offset: offset)
        |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.active else { return }
            let wanted = Set(self.ids)
            let found = Set(page.texts.flatMap(AnchorQuickRules.requestIds)).intersection(wanted)
            if !found.isEmpty { self.askDuplicate(Array(found).sorted(), pending: false); return }
            self.pages += 1
            if page.completed {
                self.index += 1
                self.pages = 0
                self.search(offset: 0)
            } else if self.pages < 4, let next = page.nextOffset {
                self.search(offset: next)
            } else {
                self.fail("Не удалось полностью проверить заявки. Ничего не отправлено.")
            }
        }, error: { [weak self] _ in self?.fail("Поиск недоступен. Ничего не отправлено — попробуй позже.") }))
    }

    private func askDuplicate(_ ids: [String], pending: Bool) {
        guard let controller = self.controller else { self.finish(); return }
        self.armTimeout(120)
        let detail = pending ? "Недавно добавлены в отправку с этого телефона:" : "В группе уже найдены заявки — у тебя или коллег:"
        let preview = self.target.requestsOnly ? AnchorQuickRules.latestRequests(self.snapshot?.text ?? "") ?? "" : self.snapshot?.text ?? ""
        let alert = UIAlertController(title: "Возможный дубль", message: self.target.destination + "\n\n" + detail + "\n" + ids.prefix(4).joined(separator: "\n") + "\n\n" + String(preview.prefix(240)) + "\n\nЕсли чек другой, можно отправить повторно.", preferredStyle: .alert)
        let cancel = UIAlertAction(title: "Отмена", style: .cancel, handler: { [weak self] _ in self?.finish() })
        alert.addAction(cancel)
        alert.addAction(UIAlertAction(title: "Отправить всё равно", style: .default, handler: { [weak self] _ in
            guard let self, self.active else { return }
            self.confirmation = nil
            self.armTimeout(20)
            self.prepare(approved: true)
        }))
        alert.preferredAction = cancel
        self.confirmation = alert
        controller.anchorgramPresent(alert)
    }

    private func enqueue() {
        guard self.active, let controller = self.controller, let payload = self.payload else { self.finish(); return }
        guard self.configured(controller) else { self.fail("Кнопка изменилась. Повтори отправку."); return }
        self.enqueuing = true
        self.disposable.set((enqueueMessages(account: controller.context.account, peerId: PeerId(self.target.peer), messages: [payload])
        |> deliverOnMainQueue).start(next: { [weak self] messages in
            guard let self, self.active else { return }
            guard messages.count == 1, messages.first! != nil else { self.fail("Не удалось добавить сообщение в отправку."); return }
            AnchorQuickStore.shared.remember(self.ids, key: self.key)
            self.controller?.anchorgramToast("Добавлено в отправку: " + self.target.label)
            self.finish()
        }))
    }

    private func fail(_ message: String) { self.controller?.anchorgramToast(message); self.finish() }

    private func finish() {
        guard self.active else { return }
        self.active = false
        self.deadline?.cancel()
        self.disposable.dispose()
        if self.confirmation?.presentingViewController != nil { self.confirmation?.dismiss(animated: true) }
        self.confirmation = nil
        AnchorQuickStore.shared.operations.removeValue(forKey: self.key)
    }
}
