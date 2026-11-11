import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class AyuGramSettingsArguments {
    let toggle: (AyuGramSettingsKey, Bool) -> Void

    init(toggle: @escaping (AyuGramSettingsKey, Bool) -> Void) {
        self.toggle = toggle
    }
}

private enum AyuGramSettingsKey: Int32 {
    case saveDeleted
    case keepSelfDestruct
    case markKeptViewed
    case ghostRead
    case ghostTyping
    case ghostOnline
    case ghostStories
}

private enum AyuGramSettingsSection: Int32 {
    case messages
    case ghost
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case messagesHeader
    case toggle(AyuGramSettingsKey, String, Bool)
    case messagesFooter(String)
    case ghostHeader
    case ghostFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .messagesHeader, .messagesFooter:
            return AyuGramSettingsSection.messages.rawValue
        case .ghostHeader, .ghostFooter:
            return AyuGramSettingsSection.ghost.rawValue
        case let .toggle(key, _, _):
            switch key {
            case .saveDeleted, .keepSelfDestruct, .markKeptViewed:
                return AyuGramSettingsSection.messages.rawValue
            default:
                return AyuGramSettingsSection.ghost.rawValue
            }
        }
    }

    var stableId: Int32 {
        switch self {
        case .messagesHeader:
            return 0
        case let .toggle(key, _, _):
            return 10 + key.rawValue
        case .messagesFooter:
            return 50
        case .ghostHeader:
            return 60
        case .ghostFooter:
            return 100
        }
    }

    static func ==(lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        switch lhs {
        case .messagesHeader:
            if case .messagesHeader = rhs {
                return true
            }
            return false
        case let .toggle(lhsKey, lhsTitle, lhsValue):
            if case let .toggle(rhsKey, rhsTitle, rhsValue) = rhs {
                return lhsKey == rhsKey && lhsTitle == rhsTitle && lhsValue == rhsValue
            }
            return false
        case let .messagesFooter(lhsText):
            if case let .messagesFooter(rhsText) = rhs {
                return lhsText == rhsText
            }
            return false
        case .ghostHeader:
            if case .ghostHeader = rhs {
                return true
            }
            return false
        case let .ghostFooter(lhsText):
            if case let .ghostFooter(rhsText) = rhs {
                return lhsText == rhsText
            }
            return false
        }
    }

    static func <(lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGramSettingsArguments
        switch self {
        case .messagesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "MESSAGES", sectionId: self.section)
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "GHOST MODE", sectionId: self.section)
        case let .toggle(key, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .messagesFooter(text), let .ghostFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func ayuGramSettingsEntries() -> [AyuGramSettingsEntry] {
    let settings = AyuSettings.shared
    var entries: [AyuGramSettingsEntry] = []

    entries.append(.messagesHeader)
    entries.append(.toggle(.saveDeleted, "Save deleted messages", settings.saveDeletedMessages))
    entries.append(.toggle(.keepSelfDestruct, "Keep self-destructing media", settings.keepSelfDestructMedia))
    entries.append(.toggle(.markKeptViewed, "Mark kept media as viewed", settings.markKeptMediaAsViewed))
    entries.append(.messagesFooter("Deleted messages stay in the chat with a trash mark next to the time and a darker bubble. Self-destructing and view-once photos, videos and voice messages are shown as ordinary media that you can open, hold and screenshot at any time. When you open one, the sender sees it as viewed."))

    entries.append(.ghostHeader)
    entries.append(.toggle(.ghostRead, "Don't send read receipts", settings.ghostRead))
    entries.append(.toggle(.ghostTyping, "Don't send typing status", settings.ghostTyping))
    entries.append(.toggle(.ghostOnline, "Don't appear online", settings.ghostOnline))
    entries.append(.toggle(.ghostStories, "Don't send story views", settings.ghostStories))
    entries.append(.ghostFooter("Ghost mode only changes what your device tells the server. Messages are still received as usual."))

    return entries
}

public func ayuGramSettingsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise<Int>(0, ignoreRepeated: false)
    let stateValue = Atomic<Int>(value: 0)

    let arguments = AyuGramSettingsArguments(toggle: { key, value in
        let settings = AyuSettings.shared
        switch key {
        case .saveDeleted:
            settings.saveDeletedMessages = value
        case .keepSelfDestruct:
            settings.keepSelfDestructMedia = value
        case .markKeptViewed:
            settings.markKeptMediaAsViewed = value
        case .ghostRead:
            settings.ghostRead = value
        case .ghostTyping:
            settings.ghostTyping = value
        case .ghostOnline:
            settings.ghostOnline = value
        case .ghostStories:
            settings.ghostStories = value
        }
        let updated = stateValue.modify { $0 + 1 }
        statePromise.set(updated)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuGramSettingsEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
