//
//  InputSourceManager.swift
//  Zest
//
//  Created by Peter Grigorian on 19.10.26.
//

import Foundation
import Carbon
import Combine


// MARK: - Input Source Model

struct ZestInputSource: Identifiable, Equatable {

    let id: String
    let name: String
    let languages: [String]
    let source: TISInputSource


    static func == (
        lhs: ZestInputSource,
        rhs: ZestInputSource
    ) -> Bool {

        lhs.id == rhs.id
    }


    // Short label that we can eventually
    // display inside the center of Zest.

    var shortLabel: String {

        if let language = languages.first {

            let code =
                language
                    .split(separator: "-")
                    .first
                    .map(String.init)
                    ?? language

            return code.uppercased()
        }


        let words =
            name.split(separator: " ")

        if words.count >= 2 {

            return words
                .prefix(2)
                .compactMap { $0.first }
                .map(String.init)
                .joined()
                .uppercased()
        }


        return String(
            name.prefix(2)
        )
        .uppercased()
    }
}


// MARK: - Input Source Manager

@MainActor
final class InputSourceManager: ObservableObject {


    // MARK: Published State

    @Published private(set)
    var sources: [ZestInputSource] = []


    @Published private(set)
    var currentSource: ZestInputSource?


    // MARK: Recent Source History

    //
    // This stores the SECOND-MOST-RECENT
    // keyboard source.
    //
    // Example:
    //
    // English -> German
    //
    // currentSource = German
    // previousSourceID = English
    //
    // Pressing the center swaps them.
    //

    private var previousSourceID: String?


    // Used so we can detect when macOS itself
    // changed the keyboard source.

    private var lastObservedSourceID: String?


    // MARK: Init

    init() {

        let initialSources =
            availableKeyboardSources()

        let initialCurrent =
            selectedKeyboardSource()

        sources =
            initialSources

        currentSource =
            initialCurrent

        lastObservedSourceID =
            initialCurrent?.id


        NotificationCenter.default.addObserver(
            self,
            selector:
                #selector(
                    inputSourceChanged
                ),
            name:
                NSNotification.Name(
                    kTISNotifySelectedKeyboardInputSourceChanged
                        as String
                ),
            object: nil
        )
    }


    deinit {

        NotificationCenter.default.removeObserver(
            self
        )
    }


    // MARK: - Refresh

    func refresh() {

        sources =
            availableKeyboardSources()

        let newlySelected =
            selectedKeyboardSource()


        guard let newlySelected else {

            currentSource = nil

            return
        }


        // Detect a real change of input source.
        //
        // This is important because the change
        // may have happened OUTSIDE Zest.

        if
            let oldID =
                lastObservedSourceID,

            oldID != newlySelected.id
        {

            previousSourceID =
                oldID
        }


        currentSource =
            newlySelected

        lastObservedSourceID =
            newlySelected.id
    }


    // MARK: - Previous In Ordered Source List

    func selectPrevious() {

        refresh()


        guard
            !sources.isEmpty,

            let currentSource,

            let currentIndex =
                sources.firstIndex(
                    of: currentSource
                )
        else {

            return
        }


        let previousIndex =
            (
                currentIndex
                - 1
                + sources.count
            )
            % sources.count


        select(
            sources[
                previousIndex
            ]
        )
    }


    // MARK: - Next In Ordered Source List

    func selectNext() {

        refresh()


        guard
            !sources.isEmpty,

            let currentSource,

            let currentIndex =
                sources.firstIndex(
                    of: currentSource
                )
        else {

            return
        }


        let nextIndex =
            (
                currentIndex
                + 1
            )
            % sources.count


        select(
            sources[
                nextIndex
            ]
        )
    }


    // MARK: - Quick Switch

    //
    // Switch to the second-most-recent input source.
    //
    // Example:
    //
    // EN -> DE
    //
    // Center:
    // DE -> EN
    //
    // Center again:
    // EN -> DE
    //

    func selectMostRecentPrevious() {

        refresh()


        guard
            let previousSourceID,

            let previousSource =
                sources.first(
                    where: {
                        $0.id
                        == previousSourceID
                    }
                )
        else {

            // There isn't any history yet.
            //
            // On a fresh launch, falling back
            // to the previous enabled keyboard
            // gives the center control useful
            // behavior immediately.

            selectPrevious()

            return
        }


        select(
            previousSource
        )
    }


    // MARK: - Select Specific Source

    func source(withID id: String) -> ZestInputSource? {
        refresh()
        return sources.first(where: { $0.id == id })
    }

    func select(
        _ source: ZestInputSource
    ) {

        guard
            currentSource?.id
            != source.id
        else {

            return
        }


        // Remember what we're leaving.
        //
        // We do this BEFORE asking macOS to
        // switch so center-click can immediately
        // swap back again.

        let sourceWeAreLeaving =
            currentSource?.id


        let status =
            TISSelectInputSource(
                source.source
            )


        guard status == noErr else {

            print(
                "Zest: Could not select input source. OSStatus:",
                status
            )

            return
        }


        if let sourceWeAreLeaving {

            previousSourceID =
                sourceWeAreLeaving
        }


        // Update immediately.
        //
        // We don't wait for macOS's notification,
        // so Zest feels instantaneous.

        currentSource =
            source

        lastObservedSourceID =
            source.id
    }


    // MARK: - Current Source

    private func selectedKeyboardSource()
        -> ZestInputSource? {

        guard
            let source =
                TISCopyCurrentKeyboardInputSource()?
                    .takeRetainedValue()
        else {

            return nil
        }


        return makeSource(
            from: source
        )
    }


    // MARK: - Enabled Keyboard Sources

    private func availableKeyboardSources()
        -> [ZestInputSource] {

        guard let keyboardCategory =
            kTISCategoryKeyboardInputSource
        else {

            return []
        }


        let properties: [String: Any] = [

            kTISPropertyInputSourceCategory
                as String:
                keyboardCategory,

            kTISPropertyInputSourceIsEnabled
                as String:
                true
        ]


        guard
            let sourceList =
                TISCreateInputSourceList(
                    properties as CFDictionary,
                    false
                )?
                .takeRetainedValue()
                as? [TISInputSource]
        else {

            return []
        }


        return sourceList
            .compactMap {
                makeSource(
                    from: $0
                )
            }
            .filter {
                !$0.id.isEmpty
            }
    }


    // MARK: - Convert Carbon Source

    private func makeSource(
        from source: TISInputSource
    ) -> ZestInputSource? {

        guard
            let id =
                stringProperty(
                    source,
                    key:
                        kTISPropertyInputSourceID
                )
        else {

            return nil
        }


        let name =
            stringProperty(
                source,
                key:
                    kTISPropertyLocalizedName
            )
            ?? id


        let languages =
            stringArrayProperty(
                source,
                key:
                    kTISPropertyInputSourceLanguages
            )


        return ZestInputSource(
            id: id,
            name: name,
            languages: languages,
            source: source
        )
    }


    // MARK: - Carbon Property Helpers

    private func stringProperty(
        _ source: TISInputSource,
        key: CFString
    ) -> String? {

        guard
            let pointer =
                TISGetInputSourceProperty(
                    source,
                    key
                )
        else {

            return nil
        }


        let value =
            Unmanaged<CFString>
                .fromOpaque(pointer)
                .takeUnretainedValue()


        return value as String
    }


    private func stringArrayProperty(
        _ source: TISInputSource,
        key: CFString
    ) -> [String] {

        guard
            let pointer =
                TISGetInputSourceProperty(
                    source,
                    key
                )
        else {

            return []
        }


        let value =
            Unmanaged<CFArray>
                .fromOpaque(pointer)
                .takeUnretainedValue()


        return value as? [String]
            ?? []
    }


    // MARK: - macOS Change Notification

    @objc
    private func inputSourceChanged() {

        Task { @MainActor in

            refresh()
        }
    }
}
