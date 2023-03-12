//
//  AppDelegate.swift
//  ElevationPlotMac
//
//  Created by Steve Wainwright on 18/01/2023.
//

import Cocoa

struct ContourManagerMenuItem {
    var plottitle: String = ""
    var id:Int = NSNotFound
}


@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet var contourManagerMenuItem: NSMenuItem?
    @IBOutlet var contourRedrawMenuItem: NSMenuItem?
    @IBOutlet var contourFillMenuItem: NSMenuItem?
    @IBOutlet var contourExtrapolateMenuItem: NSMenuItem?
    @IBOutlet var contourSurfaceInterpolateMenuItem: NSMenuItem?
    @IBOutlet var configurationMenuItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        setupSandbox()
        
        if let _ = self.configurationMenuItem {

            if let window = NSApplication.shared.windows.first,
               let viewController = window.contentViewController as? ViewController,
               let contourManagerRecords = viewController.contourManagerRecordsMenuItems() {
                if let _currentContour = viewController.currentContour {
                    if _currentContour.fillContours {
                        self.contourFillMenuItem?.title = "Unfill"
                    }
                    else {
                        self.contourFillMenuItem?.title = "Fill"
                    }
                    
                    if _currentContour.extrapolateToARectangleOfLimits {
                        self.contourExtrapolateMenuItem?.title = "No Extrapolation to Corners"
                    }
                    else {
                        self.contourExtrapolateMenuItem?.title = "Extrapolate to Corners"
                    }
                }
                if viewController.contourManagerCounter < 5 {
                    self.contourExtrapolateMenuItem?.isEnabled = false
                    self.contourSurfaceInterpolateMenuItem?.isEnabled = false
                }
                else {
                    self.contourExtrapolateMenuItem?.isEnabled = true
                    self.contourSurfaceInterpolateMenuItem?.isEnabled = true
                    if let _currentContour = viewController.currentContour,
                       let subMenuItems = self.contourSurfaceInterpolateMenuItem?.submenu?.items {
                        if _currentContour.krigingSurfaceInterpolation {
                            subMenuItems[0].state = .off
                            subMenuItems[1].state = .on
                            if let subSubMenuItems = subMenuItems[1].submenu?.items {
                                for subSubMenuItem in subSubMenuItems {
                                    subSubMenuItem.state = .off
                                }
                                subSubMenuItems[Int(_currentContour.krigingSurfaceModel.rawValue)].state = .on
                            }
                        }
                        else {
                            subMenuItems[0].state = .on
                            subMenuItems[1].state = .off
                        }
                    }
                }
                self.contourManagerMenuItem?.submenu = NSMenu()
                var countOuter: Int = 0
                var countInner: Int = 0
                for records in contourManagerRecords {
                    for record in records {
                        let menuItem = NSMenuItem(title: record.plottitle, action: #selector(tappedContourManagerMenuItem(_ :)), keyEquivalent: "")
                        menuItem.target = self
                        menuItem.tag = countInner
                        if countInner == viewController.contourManagerCounter {
                            menuItem.state = .on
                        }
                        else {
                            menuItem.state = .off
                        }
                        self.contourManagerMenuItem?.submenu?.addItem(menuItem)
                        countInner += 1
                    }
                    if countOuter == 0 {
                        self.contourManagerMenuItem?.submenu?.addItem(NSMenuItem.separator())
                    }
                    countOuter += 1
                }
                viewController.setupConfigurationMenuItems()
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: -
    // MARK: NSMenuItem actions
    
    @IBAction func tappedContourManagerMenuItem(_ sender: Any?) {
        if let window = NSApplication.shared.mainWindow,
           let viewController = window.contentViewController as? ViewController {
            viewController.tappedContourManagerMenuItem(sender)
            if let submenu = self.contourManagerMenuItem?.submenu,
               let tappedMenuItem = sender as? NSMenuItem {
                for menuItem in submenu.items {
                    menuItem.state = .off
                }
                tappedMenuItem.state = .on
            }
        }
    }
    
    @IBAction func toggleRedrawContoursMenuItem(_ sender: Any?) {
        if let window = NSApplication.shared.mainWindow,
           let viewController = window.contentViewController as? ViewController {
            viewController.toggleRedrawContoursMenuItem(sender)
        }
    }
    
    @IBAction func toggleFillContoursMenuItem(_ sender: Any?) {
        if let window = NSApplication.shared.mainWindow,
           let viewController = window.contentViewController as? ViewController {
            viewController.toggleFillContoursMenuItem(sender)
        }
    }
    
    @IBAction func toggleExtrapolateContoursToLimitsRectangleMenuItem(_ sender: Any?) {
        if let window = NSApplication.shared.mainWindow,
           let viewController = window.contentViewController as? ViewController {
            viewController.toggleExtrapolateContoursToLimitsRectangleMenuItem(sender)
        }
    }
    
    @IBAction func tappedInstructionsMenuItem(_ sender: Any?) {
        if let window = NSApplication.shared.mainWindow,
           let viewController = window.contentViewController as? ViewController {
            viewController.tappedInstructionsMenuItem(sender)
        }
    }
    
    @IBAction func toggleSurfaceInterpolationContoursMethodMenuItem(_ sender: Any?) {
        if let window = NSApplication.shared.mainWindow,
           let viewController = window.contentViewController as? ViewController {
            viewController.toggleSurfaceInterpolationContoursMethodMenuItem(sender)
        }
    }
    
    @IBAction func changeKrigingContoursModelMenuItem(_ sender: Any?) {
        if let window = NSApplication.shared.mainWindow,
           let viewController = window.contentViewController as? ViewController {
            viewController.changeKrigingContoursModelMenuItem(sender)
        }
    }

    // MARK: -
    // MARK: Setup SandBox Initial Contents
    
    private func setupSandbox() {
        
        let dirPaths: [String]  = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        // Get the documents directory
        var docsDirURL: URL = URL(fileURLWithPath:dirPaths[0])
        docsDirURL = docsDirURL.appendingPathComponent("GMMCluster")
        if !FileManager.default.changeCurrentDirectoryPath(docsDirURL.absoluteString) {
            do {
                try FileManager.default.createDirectory(at: docsDirURL, withIntermediateDirectories: true, attributes: nil)
            }
            catch let error as NSError {
                print("Can't create the Documents/GMMCluster folder\n\(error.localizedFailureReason ?? "unknown")")
                exit(-1)
                // Failed to create directory
            }
        }
        
        if let path = Bundle.main.resourcePath {
            let files = ["info_file1", "info_file2", "info_file3", "data1", "TrainingData21", "TrainingData22", "TestingData2", "data3"]
            var url: URL;
            var saved_url: URL
            for filename: String in files {
                url = URL(fileURLWithPath: path).appendingPathComponent(filename)
                saved_url = docsDirURL.appendingPathComponent(filename)
                do {
                    try FileManager.default.copyItem(at: url, to: saved_url)
                }
                catch let error as NSError  {
                    if error.code != NSFileWriteFileExistsError {
                        print("Can't copy resource to the Documents/GMMCluster folder\n\(error.localizedFailureReason ?? "unknown")")
                    }
                }
            }
        }
    }
    
}

