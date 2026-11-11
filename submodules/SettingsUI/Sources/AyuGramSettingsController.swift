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
    case showPeerId
    case hideAds
    case showSeconds
}

private enum AyuGramSettingsSection: Int32 {
    case messages
    case ghost
    case general
}

private func ayuSection(for key: AyuGramSettingsKey) -> AyuGramSettingsSection {
    switch key {
    case .saveDeleted, .keepSelfDestruct, .markKeptViewed:
        return .messages
    case .ghostRead, .ghostTyping, .ghostOnline, .ghostStories:
        return .ghost
    case .showPeerId, .hideAds, .showSeconds:
        return .general
    }
}

private func ayuToggleSortIndex(for key: AyuGramSettingsKey) -> Int32 {
    switch key {
    case .saveDeleted:
        return 10
    case .keepSelfDestruct:
        return 11
    case .markKeptViewed:
        return 12
    case .ghostRead:
        return 31
    case .ghostTyping:
        return 32
    case .ghostOnline:
        return 33
    case .ghostStories:
        return 34
    case .showPeerId:
        return 51
    case .hideAds:
        return 52
    case .showSeconds:
        return 53
    }
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case header(AyuGramSettingsSection, String)
    case toggle(AyuGramSettingsKey, String, Bool)
    case footer(AyuGramSettingsSection, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _):
            return section.rawValue
        case let .footer(section, _):
            return section.rawValue
        case let .toggle(key, _, _):
            return ayuSection(for: key).rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            switch section {
            case .messages:
                return 0
            case .ghost:
                return 30
            case .general:
                return 50
            }
        case let .footer(section, _):
            switch section {
            case .messages:
                return 20
            case .ghost:
                return 40
            case .general:
                return 60
            }
        case let .toggle(key, _, _):
            return ayuToggleSortIndex(for: key)
        }
    }

    static func ==(lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        switch lhs {
        case let .header(lhsSection, lhsText):
            if case let .header(rhsSection, rhsText) = rhs {
                return lhsSection == rhsSection && lhsText == rhsText
            }
            return false
        case let .toggle(lhsKey, lhsTitle, lhsValue):
            if case let .toggle(rhsKey, rhsTitle, rhsValue) = rhs {
                return lhsKey == rhsKey && lhsTitle == rhsTitle && lhsValue == rhsValue
            }
            return false
        case let .footer(lhsSection, lhsText):
            if case let .footer(rhsSection, rhsText) = rhs {
                return lhsSection == rhsSection && lhsText == rhsText
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
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(key, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func ayuGramSettingsEntries() -> [AyuGramSettingsEntry] {
    let settings = AyuSettings.shared
    var entries: [AyuGramSettingsEntry] = []

    entries.append(.header(.messages, "MESSAGES"))
    entries.append(.toggle(.saveDeleted, "Save deleted messages", settings.saveDeletedMessages))
    entries.append(.toggle(.keepSelfDestruct, "Keep self-destructing media", settings.keepSelfDestructMedia))
    entries.append(.toggle(.markKeptViewed, "Mark kept media as viewed", settings.markKeptMediaAsViewed))
    entries.append(.footer(.messages, "Deleted messages stay in the chat with a trash mark next to the time and a darker bubble. Self-destructing and view-once photos, videos and voice messages are shown as ordinary media that you can open, hold and screenshot at any time. When you open one, the sender sees it as viewed."))

    entries.append(.header(.ghost, "GHOST MODE"))
    entries.append(.toggle(.ghostRead, "Don't send read receipts", settings.ghostRead))
    entries.append(.toggle(.ghostTyping, "Don't send typing status", settings.ghostTyping))
    entries.append(.toggle(.ghostOnline, "Don't appear online", settings.ghostOnline))
    entries.append(.toggle(.ghostStories, "Don't send story views", settings.ghostStories))
    entries.append(.footer(.ghost, "Ghost mode only changes what your device tells the server. Messages are still received as usual."))

    entries.append(.header(.general, "GENERAL"))
    entries.append(.toggle(.showPeerId, "Show user ID in profile", settings.showPeerId))
    entries.append(.toggle(.hideAds, "Hide sponsored messages", settings.hideAds))
    entries.append(.toggle(.showSeconds, "Show seconds in message time", settings.showSeconds))
    entries.append(.footer(.general, "The ID in a profile is copied when you tap it. Hiding sponsored messages and the seconds apply after reopening the chat."))

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
        case .showPeerId:
            settings.showPeerId = value
        case .hideAds:
            settings.hideAds = value
        case .showSeconds:
            settings.showSeconds = value
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
