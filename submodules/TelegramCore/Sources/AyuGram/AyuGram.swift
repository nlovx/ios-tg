import Foundation
import Postbox
import SwiftSignalKit

/// Local-only feature switches of the AyuGram patch set. Stored in UserDefaults, read from anywhere (any queue).
public final class AyuSettings {
    public static let shared = AyuSettings()

    private let defaults = UserDefaults.standard

    /// Sideloaded builds (free Apple ID) have no Siri / iCloud entitlements; touching those APIs aborts the process.
    public var siriUnavailable: Bool {
        return true
    }

    private func value(_ key: String, _ defaultValue: Bool) -> Bool {
        if self.defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return self.defaults.bool(forKey: key)
    }

    private func set(_ key: String, _ value: Bool) {
        self.defaults.set(value, forKey: key)
    }

    /// Keep messages locally when somebody deletes them on the server.
    public var saveDeletedMessages: Bool {
        get { return self.value("ayu.saveDeletedMessages", true) }
        set { self.set("ayu.saveDeletedMessages", newValue) }
    }

    /// Keep self-destructing / view-once media as ordinary, permanently viewable media.
    public var keepSelfDestructMedia: Bool {
        get { return self.value("ayu.keepSelfDestructMedia", true) }
        set { self.set("ayu.keepSelfDestructMedia", newValue) }
    }

    /// When a kept view-once message is opened, tell the sender that it was viewed.
    public var markKeptMediaAsViewed: Bool {
        get { return self.value("ayu.markKeptMediaAsViewed", true) }
        set { self.set("ayu.markKeptMediaAsViewed", newValue) }
    }

    /// Never send "read" receipts for chats.
    public var ghostRead: Bool {
        get { return self.value("ayu.ghostRead", false) }
        set { self.set("ayu.ghostRead", newValue) }
    }

    /// Never send "typing..." and other chat activities.
    public var ghostTyping: Bool {
        get { return self.value("ayu.ghostTyping", false) }
        set { self.set("ayu.ghostTyping", newValue) }
    }

    /// Never appear online.
    public var ghostOnline: Bool {
        get { return self.value("ayu.ghostOnline", false) }
        set { self.set("ayu.ghostOnline", newValue) }
    }

    /// Show the numeric id in a user's profile.
    public var showPeerId: Bool {
        get { return self.value("ayu.showPeerId", true) }
        set { self.set("ayu.showPeerId", newValue) }
    }

    /// Never fetch sponsored (ad) messages.
    public var hideAds: Bool {
        get { return self.value("ayu.hideAds", true) }
        set { self.set("ayu.hideAds", newValue) }
    }

    /// Show seconds in the time next to every message.
    public var showSeconds: Bool {
        get { return self.value("ayu.showSeconds", false) }
        set { self.set("ayu.showSeconds", newValue) }
    }

    /// Never send "story viewed".
    public var ghostStories: Bool {
        get { return self.value("ayu.ghostStories", false) }
        set { self.set("ayu.ghostStories", newValue) }
    }
}

/// Marks a message that was deleted on the server but is kept locally.
public final class AyuDeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public var associatedMessageIds: [MessageId] = []

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

/// Replaces the self-destruct timer of an incoming media message: the media stays and can be viewed any number of times.
public final class AyuKeptMediaMessageAttribute: MessageAttribute {
    public let timeout: Int32
    public let notified: Bool

    public var associatedMessageIds: [MessageId] = []

    public init(timeout: Int32, notified: Bool) {
        self.timeout = timeout
        self.notified = notified
    }

    required public init(decoder: PostboxDecoder) {
        self.timeout = decoder.decodeInt32ForKey("t", orElse: 0)
        self.notified = decoder.decodeInt32ForKey("n", orElse: 0) != 0
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timeout, forKey: "t")
        encoder.encodeInt32(self.notified ? 1 : 0, forKey: "n")
    }
}

public extension Message {
    var isAyuDeleted: Bool {
        for attribute in self.attributes {
            if attribute is AyuDeletedMessageAttribute {
                return true
            }
        }
        return false
    }

    var ayuKeptMediaAttribute: AyuKeptMediaMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? AyuKeptMediaMessageAttribute {
                return attribute
            }
        }
        return nil
    }
}

public extension EngineMessage {
    var isAyuDeleted: Bool {
        for attribute in self.attributes {
            if attribute is AyuDeletedMessageAttribute {
                return true
            }
        }
        return false
    }

    var isAyuKeptMedia: Bool {
        for attribute in self.attributes {
            if attribute is AyuKeptMediaMessageAttribute {
                return true
            }
        }
        return false
    }
}

private func ayuReplaceAttributes(transaction: Transaction, id: MessageId, update: @escaping ([MessageAttribute]) -> [MessageAttribute]?) {
    transaction.updateMessage(id, update: { currentMessage in
        guard let attributes = update(currentMessage.attributes) else {
            return .skip
        }
        var storeForwardInfo: StoreMessageForwardInfo?
        if let forwardInfo = currentMessage.forwardInfo {
            storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
        }
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
    })
}

/// Marks the given (already stored) messages as deleted instead of removing them. Returns the ids that were handled.
func ayuMarkMessagesDeleted(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    var handled: [MessageId] = []
    let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    for id in ids {
        if id.namespace != Namespaces.Message.Cloud {
            continue
        }
        guard let message = transaction.getMessage(id) else {
            continue
        }
        // Service messages are not worth keeping.
        var isService = false
        for media in message.media {
            if media is TelegramMediaAction {
                isService = true
            }
        }
        if isService {
            continue
        }
        handled.append(id)
        if message.isAyuDeleted {
            continue
        }
        ayuReplaceAttributes(transaction: transaction, id: id, update: { attributes in
            var attributes = attributes
            attributes.append(AyuDeletedMessageAttribute(date: timestamp))
            return attributes
        })
    }
    return handled
}

func _internal_ayuMarkKeptMediaViewed(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        guard let message = transaction.getMessage(messageId), let attribute = message.ayuKeptMediaAttribute, !attribute.notified else {
            return
        }
        ayuReplaceAttributes(transaction: transaction, id: messageId, update: { attributes in
            var attributes = attributes
            for i in 0 ..< attributes.count {
                if let current = attributes[i] as? AyuKeptMediaMessageAttribute {
                    attributes[i] = AyuKeptMediaMessageAttribute(timeout: current.timeout, notified: true)
                }
            }
            return attributes
        })
        if AyuSettings.shared.markKeptMediaAsViewed && message.flags.contains(.Incoming) {
            addSynchronizeConsumeMessageContentsOperation(transaction: transaction, messageIds: [messageId])
        }
    }
}
