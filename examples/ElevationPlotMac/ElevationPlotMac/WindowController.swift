//
//  WindowController.swift
//  ElevationPlotMac
//
//  Created by Steve Wainwright on 23/01/2023.
//

import Cocoa

class WindowController: NSWindowController, NSWindowDelegate {
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        if let window = self.window, let screen = NSScreen.main {
            let _/*screenRect*/ = screen.visibleFrame
            window.delegate = self
            DispatchQueue.main.async {
//                window.setFrame(NSRect(x: screenRect.origin.x, y: screenRect.origin.y, width: screenRect.width, height: screenRect.height), display: true, animate: true)
                window.setFrameAutosaveName("CustomSizeWindow")
            }
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let window = self.window,
           let viewController = window.contentViewController as? ViewController {
            viewController.resizePlotWindow(window.frame.size)
        }
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
//        menuItem.state = workspaceIndex == menuItem.tag ? NSOnState : NSOffState
        return true
    }
}
