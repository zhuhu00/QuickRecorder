//
//  ContentView.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/16.
//

import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct ContentView: View {
    var body: some View {
        ContentViewNew(fromStatusBar: false)
    }
}

struct SelectorView: View {
    var title = "No Title".local
    var symbol = "app"
    var symbolSize: CGFloat = 36
    var overlayer = ""
    @State private var backgroundOpacity = 0.0001
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .opacity(0.95)
                .font(.system(size: 12))
                .offset(y: title == "System Audio".local ? -3.5 : 0)
            ZStack {
                if title == "System Audio".local {
                    Image(systemName: symbol)
                        .opacity(0.95)
                        .offset(y: -9.5)
                        .font(.system(size: 26, weight: .bold))
                } else {
                    Image(systemName: symbol)
                        .opacity(0.95)
                        .font(.system(size: symbolSize))
                        .frame(height: 40)
                }
                Text(overlayer)
                    .fontWeight(.bold)
                    .opacity(0.95)
                    .font(.system(size: 11))
            }
        }
        .frame(width: 110, height: 80)
        .onHover{ hovering in
            backgroundOpacity = hovering ? 0.2 : 0.0001
        }
        .background( .primary.opacity(backgroundOpacity) )
    }
}

struct CountdownView: View {
    @State var countdownValue: Int = 00
    @State private var timer: Timer?
    var atEnd: () -> Void

    var body: some View {
        ZStack {
            Color.mypurple.environment(\.colorScheme, .dark)
            Text("\(countdownValue)")
                .font(.system(size: 72))
                .foregroundColor(.white)
                .offset(y: -10)
            Button(action: {
                timer?.invalidate()
                for w in NSApp.windows.filter({
                    $0.title == "Countdown Panel".local ||
                    $0.title == "Area Overlayer".local
                }) { w.close() }
            }, label: {
                ZStack {
                    Color.white.opacity(0.2)
                    Text("Cancel").foregroundColor(.white)
                }.frame(width: 120, height: 24)
            })
            .buttonStyle(.plain)
            .padding(.top, 96)
        }
        .frame(width: 120, height: 120)
        .cornerRadius(10)
        .onAppear{
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if countdownValue > 1 {
                    countdownValue -= 1
                } else {
                    timer.invalidate()
                    if let w = NSApp.windows.first(where: { $0.title == "Countdown Panel".local }) { w.close() }
                    atEnd()
                }
            }
        }
    }
}


extension AppDelegate {
    func showAreaSelector(size: NSSize, noPanel: Bool = false) {
        guard let scDisplay = SCContext.getSCDisplayWithMouse() else { return }
        guard let screen = scDisplay.nsScreen else { return }
        let screenshotWindow = ScreenshotWindow(contentRect: screen.frame, backing: .buffered, defer: false, size: size, force: noPanel)
        screenshotWindow.title = "Area Selector".local
        //screenshotWindow.orderFront(self)
        screenshotWindow.orderFrontRegardless()
        if !noPanel {
            let wX = (screen.frame.width - 790) / 2 + screen.frame.minX
            let wY = screen.visibleFrame.minY + 80
            let contentView = NSHostingView(rootView: AreaSelector(screen: scDisplay))
            contentView.frame = NSRect(x: wX, y: wY, width: 790, height: 90)
            contentView.focusRingType = .none
            let areaPanel = NSPanel(contentRect: contentView.frame, styleMask: [.fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            areaPanel.collectionBehavior = [.canJoinAllSpaces]
            areaPanel.setFrame(contentView.frame, display: true)
            areaPanel.level = .screenSaver
            areaPanel.title = "Start Recording".local
            areaPanel.contentView = contentView
            areaPanel.backgroundColor = .clear
            areaPanel.titleVisibility = .hidden
            areaPanel.isReleasedWhenClosed = false
            areaPanel.titlebarAppearsTransparent = true
            areaPanel.isMovableByWindowBackground = true
            //areaPanel.setFrameOrigin(NSPoint(x: wX, y: wY))
            areaPanel.orderFront(self)
        }
    }
    
    func createCountdownPanel(screen: SCDisplay, action: @escaping () -> Void) {
        guard let screen = screen.nsScreen else { return }
        let countdown = ud.integer(forKey: "countdown")
        if countdown == 0 {
            action()
        } else {
            let wX = (screen.frame.width - 120) / 2 + screen.frame.minX
            let wY = (screen.frame.height - 120) / 2 + screen.frame.minY
            let frame =  NSRect(x: wX, y: wY, width: 120, height: 120)
            let contentView = NSHostingView(rootView: CountdownView(countdownValue: countdown, atEnd: action))
            contentView.frame = frame
            countdownPanel.contentView = contentView
            countdownPanel.setFrame(frame, display: true)
            countdownPanel.makeKeyAndOrderFront(self)
        }
    }
    
    func createNewWindow(view: some View, title: String, random: Bool = false, only: Bool = true) {
        guard let screen = SCContext.getScreenWithMouse() else { return }
        if only { closeAllWindow() }
        var seed = 0.0
        if random { seed = CGFloat(Int(arc4random_uniform(401)) - 200) }
        let wX = (screen.frame.width - 780) / 2 + seed + screen.frame.minX
        let wY = (screen.frame.height - 555) / 2 + 100 + seed + screen.frame.minY
        let contentView = NSHostingView(rootView: view)
        contentView.frame = NSRect(x: wX, y: wY, width: 780, height: 555)
        let window = NSWindow(contentRect: contentView.frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = contentView
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(self)
        window.orderFrontRegardless()
    }
}

extension View {
    func needScale() -> some View {
        scaleEffect(0.8).padding(.leading, -4)
    }
}


/*#Preview {
    ContentView()
}
*/
