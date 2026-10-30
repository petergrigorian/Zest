//
//  ZestSettingsWindow.swift
//  Zest
//

import SwiftUI
import AppKit
import ObjectiveC


extension Notification.Name {
    static let zestSettingsCloseRequested =
        Notification.Name("zest.settings.closeRequested")

    static let zestSettingsForceClose =
        Notification.Name("zest.settings.forceClose")

    static let zestLayoutDragStateChanged =
        Notification.Name("zest.settings.layoutDragStateChanged")
}


private final class ZestSettingsCloseDelegate: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    var allowNextClose = false
    private var forceCloseObserver: NSObjectProtocol?

    init(window: NSWindow) {
        self.window = window
        super.init()

        forceCloseObserver = NotificationCenter.default.addObserver(
            forName: .zestSettingsForceClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window else { return }
            self.allowNextClose = true
            window.performClose(nil)
        }
    }

    deinit {
        if let forceCloseObserver {
            NotificationCenter.default.removeObserver(forceCloseObserver)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowNextClose {
            allowNextClose = false
            return true
        }

        NotificationCenter.default.post(
            name: .zestSettingsCloseRequested,
            object: nil
        )
        return false
    }
}


private var zestCloseDelegateAssociationKey: UInt8 = 0



struct ZestSettingsWindowConfigurator:
    NSViewRepresentable {

    func makeNSView(
        context: Context
    ) -> NSView {

        let view = NSView()

        DispatchQueue.main.async {
            configure(
                view.window
            )
        }

        return view
    }


    func updateNSView(
        _ nsView: NSView,
        context: Context
    ) {

        DispatchQueue.main.async {
            configure(
                nsView.window
            )
        }
    }


    private func configure(
        _ window: NSWindow?
    ) {

        guard let window else {
            return
        }


        // MARK: Seamless Title Area

        window.title =
            ""

        window.titleVisibility =
            .hidden

        window.titlebarAppearsTransparent =
            true

        window.titlebarSeparatorStyle =
            .none

        window.styleMask.insert(
            .fullSizeContentView
        )

        window.isMovableByWindowBackground =
            true

        // The SwiftUI settings surface owns the complete full-size content area.
        // Prevent AppKit's native background from peeking through as a white
        // strip when the window is resized.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor


        // MARK: Window Behaviour

        window.isReleasedWhenClosed =
            false

        if objc_getAssociatedObject(
            window,
            &zestCloseDelegateAssociationKey
        ) == nil {
            let closeDelegate =
                ZestSettingsCloseDelegate(
                    window: window
                )

            objc_setAssociatedObject(
                window,
                &zestCloseDelegateAssociationKey,
                closeDelegate,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            window.delegate =
                closeDelegate
        }

        window.standardWindowButton(
            .closeButton
        )?
        .isHidden = false

        window.standardWindowButton(
            .closeButton
        )?
        .isEnabled = true


        window.standardWindowButton(
            .miniaturizeButton
        )?
        .isHidden = false

        window.standardWindowButton(
            .miniaturizeButton
        )?
        .isEnabled = true


        // No green maximize / zoom button.

        window.standardWindowButton(
            .zoomButton
        )?
        .isHidden = true

        window.standardWindowButton(
            .zoomButton
        )?
        .isEnabled = false


        window.collectionBehavior.remove(
            .fullScreenPrimary
        )

        window.collectionBehavior.insert(
            .fullScreenAuxiliary
        )
    }
}
