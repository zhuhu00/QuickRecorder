//
//  WindowAccessor.swift
//  xHistory
//
//  Created by apple on 2024/11/7.
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    var onWindowOpen: ((NSWindow?) -> Void)?
    var onWindowActive: ((NSWindow?) -> Void)?
    var onWindowDeactivate: ((NSWindow?) -> Void)?
    var onWindowClose: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = context.coordinator
                context.coordinator.window = window
                self.onWindowOpen?(window)
            } else {
                self.onWindowOpen?(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onWindowOpen: onWindowOpen,
            onWindowActive: onWindowActive,
            onWindowDeactivate: onWindowDeactivate,
            onWindowClose: onWindowClose
        )
    }

    class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow? // 使用 weak 避免循环引用
        var onWindowOpen: ((NSWindow?) -> Void)?
        var onWindowActive: ((NSWindow?) -> Void)?
        var onWindowDeactivate: ((NSWindow?) -> Void)?
        var onWindowClose: (() -> Void)?

        init(onWindowOpen: ((NSWindow?) -> Void)? = nil,
             onWindowActive: ((NSWindow?) -> Void)? = nil,
             onWindowDeactivate: ((NSWindow?) -> Void)? = nil,
             onWindowClose: (() -> Void)? = nil) {
            self.onWindowOpen = onWindowOpen
            self.onWindowClose = onWindowClose
            self.onWindowActive = onWindowActive
            self.onWindowDeactivate = onWindowDeactivate
        }

        func windowWillClose(_ notification: Notification) {
            onWindowClose?()
        }
        
        func windowDidBecomeKey(_ notification: Notification) {
            onWindowActive?(window)
        }

        func windowDidResignKey(_ notification: Notification) {
            onWindowDeactivate?(window)
        }
    }
}

// Resolve control exclusions into window coordinates. The panel receives the
// mouse event before SwiftUI, so empty hosting content cannot swallow dragging.
struct RecorderDragSurface: NSViewRepresentable {
    var excludedRects: [CGRect] = []
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.excludedRects = excludedRects
        nsView.updateDragRegion()
    }

    final class DragView: NSView {
        var excludedRects: [CGRect] = []
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateDragRegion()
        }
        override func layout() {
            super.layout()
            updateDragRegion()
        }
        func updateDragRegion() {
            guard let panel = window as? RecorderFloatingPanel else { return }
            panel.dragSurface = self
        }
    }
}

class RecorderFloatingPanel: NSPanel {
    weak var dragSurface: RecorderDragSurface.DragView?
    var dragRegion = NSRect.zero
    var dragExclusions: [NSRect] = []

    func shouldDrag(at point: NSPoint) -> Bool {
        let inset: CGFloat = styleMask.contains(.resizable) ? 8 : 1
        let region = dragSurface.map { $0.convert($0.bounds, to: nil) } ?? dragRegion
        let exclusions = dragSurface.map { surface in
            surface.excludedRects.map { surface.convert($0, to: nil) }
        } ?? dragExclusions
        return region.insetBy(dx: inset, dy: inset).contains(point)
            && !exclusions.contains { $0.contains(point) }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && shouldDrag(at: event.locationInWindow) {
            let before = frame
            performDrag(with: event)
            NSLog("Recorder window drag %@: %@ -> %@", title, NSStringFromRect(before), NSStringFromRect(frame))
            return
        }
        super.sendEvent(event)
    }
}
