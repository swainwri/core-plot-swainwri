//
//  ViewController.swift
//  ElevationPlot
//
//  Created by Steve Wainwright on 27/01/2022.
//

//see https://mathematica.stackexchange.com/questions/11765/data-interpolation-and-listcontourplot

import UIKit
import CorePlot
import KDTree

struct DataStructure: Equatable {
    var x: Double
    var y: Double
    var z: Double
}

struct ConvexHullPoint: Equatable {
    var point: CGPoint
    var index: Int
    
    static func == (lhs: ConvexHullPoint, rhs: ConvexHullPoint) -> Bool {
        return __CGPointEqualToPoint(lhs.point, rhs.point)
    }
}

struct ContourManagerRecord {
    var fillContours: Bool = false
    var extrapolateToARectangleOfLimits: Bool = true
    var krigingSurfaceInterpolation: Bool = true
    var krigingSurfaceModel : SWKrigingMode = .exponential
    var trig: Bool = false
    var functionLimits:[Double]?
    var firstResolution: UInt = 64
    var secondaryResolution: UInt = 512
    var plottitle: String = ""
    var functionExpression : ((Double, Double) -> Double)?
    var data: [DataStructure]?
}


class ViewController: UIViewController, CPTPlotDataSource, CPTAxisDelegate, CPTPlotSpaceDelegate,  CPTContourPlotDataSource, CPTContourPlotDelegate, CPTLegendDelegate, CPTAnimationDelegate, UIGestureRecognizerDelegate, ContourManagerViewControllerDelegate, SurfaceInterpolationManagerViewControllerDelegate, UIPopoverPresentationControllerDelegate {
    
    @IBOutlet var hostingView: CPTGraphHostingView?
    
    @IBOutlet var toggleRedrawButton: UIButton?
    @IBOutlet var toggleFillButton: UIButton?
    @IBOutlet var toggleExtrapolateToLimitsRectangleButton: UIButton?
    @IBOutlet var chooseSurfaceInterpolationMethodButton: UIButton?
    @IBOutlet var tappedContourManagerButton: UIButton?
    @IBOutlet var tappedInstructionsButton: UIButton?
    
    private var spinner: SpinnerView?
    private var message: String = "Generating the contour plot, please wait..."

    private var contourManagerViewController: ContourManagerViewController?
    private var surfaceInterpolationManagerViewController: SurfaceInterpolationManagerViewController?
    
    private var graph: CPTXYGraph = CPTXYGraph()
    
    private var plotdata: [DataStructure] = []
    private var discontinuousData: [DataStructure] = []
    private var dataBlockSources: [CPTFieldFunctionDataSource]?
    
    private var hull = Hull()
    
    private var minX = 0.0
    private var maxX = 0.0
    private var minY = 0.0
    private var maxY = 0.0
    private var minFunctionValue = 0.0
    private var maxFunctionValue = 0.0
    
    private var colourCodeAnnotation: CPTAnnotation?
    private var pointTextAnnotation: CPTPlotSpaceAnnotation?
    
    private var contourManagerCounter: Int = 0
    private var currentContour: ContourManagerRecord?
    private var contourManagerRecords: [ContourManagerRecord] = []
        
    private var longPressGestureForLegend: UILongPressGestureRecognizer?
    private var isLegendShowing = false
    
    // MARK: -
    // MARK: Screen Orientation
    
    func shouldAutorotate() -> Bool {
        return true
    }
    
    func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        //return UIInterfaceOrientationMask.All;
        // Return YES for supported orientations
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        }
        else {
            return .all
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: { (context) in
                if self.hostingView != nil {
                    self.hostingView?.frame = self.view.frame
                    if let _hostingView = self.hostingView,
                       _hostingView.frame.origin.y != 0.0 {
                        self.hostingView?.frame = CGRect(x: _hostingView.frame.origin.x, y: 0.0, width: _hostingView.frame.size.width, height: _hostingView.frame.size.height + _hostingView.frame.origin.y)
                    }
                    if let _currentContour = self.currentContour,
                        let contourPlot = self.graph.allPlots().first(where: { $0.identifier as? String == (self.currentContour?.functionExpression == nil ? "data" : "function") } ) as? CPTContourPlot {
                        if let _ = self.colourCodeAnnotation {
                            self.isLegendShowing = true
                            self.removeColourCodeAnnotation()
                        }
                        self.graph.remove(contourPlot)
                        self.graph.legend?.remove(contourPlot)
                        if let newContourPlot = self.setupPlot(self.graph, noIsoCurves: contourPlot.noIsoCurves) {
                            if let _ /*spinner*/ = self.spinner {
                                self.showSpinner() { _ in
                                    newContourPlot.fillIsoCurves = _currentContour.fillContours;
                                    self.graph.add(newContourPlot)
                                    self.graph.legend?.add(newContourPlot)
                                    self.setupConfigurationButtons()
                                }
                            }
                            else {
                                newContourPlot.fillIsoCurves = _currentContour.fillContours;
                                self.graph.add(newContourPlot)
                                self.graph.legend?.add(newContourPlot)
                                self.setupConfigurationButtons()
                            }
                        }
                    }
                }
            }) { (context) in
                if self.isLegendShowing,
                   let contourPlot = self.graph.allPlots().first(where: { $0.identifier as? String == (self.currentContour?.functionExpression == nil ? "data" : "function") } ) as? CPTContourPlot {
                    self.showColourCodeAnnotation(contourPlot)
                }
            }
    }
    
    // MARK: -
    // MARK: Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        contourManagerRecords.append(ContourManagerRecord(fillContours: true, trig: true, functionLimits: [-.pi, .pi, -.pi, .pi], firstResolution: 128, secondaryResolution: 2048, plottitle: "0.5(sin(x+π/4) + cos(y+π/4)", functionExpression: { (x: Double, y: Double) -> Double in return 0.5 * (cos(x + .pi / 4.0) + sin(y + .pi / 4.0)) }, data: nil))
        contourManagerRecords.append(ContourManagerRecord(fillContours: false, trig: false, functionLimits: [-3, 3, -3, 3], firstResolution: 128, secondaryResolution: 2048, plottitle: "log(2xy + x + y + 1)", functionExpression: { (x: Double, y: Double) -> Double in return log(2 * x * y + x + y + 1) }, data: nil))
        contourManagerRecords.append(ContourManagerRecord(fillContours: true, trig: false, functionLimits: [-3, 3, -3, 3], plottitle: "sin(√(x² + y²)) + 1 / √((x - 5)² + y²)", functionExpression: { (x: Double, y: Double) -> Double in return sin(sqrt(x * x + y * y)) + 1 / sqrt(pow(x - 5, 2.0) + y * y) }, data: nil))
        contourManagerRecords.append(ContourManagerRecord(fillContours: false, trig: false, functionLimits:  [-3, 3, -3, 3], plottitle: "xy/(x² + y²)", functionExpression: { (x: Double, y: Double) -> Double in return x * y / ( x * x + y * y) }, data: nil))
        contourManagerRecords.append(ContourManagerRecord(fillContours: false, trig: false, functionLimits:  [-1, 1, -1, 1], firstResolution: 64, secondaryResolution: 1024, plottitle: "(x³ - x²y + 9xy²) / (5x²y + 7y³)", functionExpression: { (x: Double, y: Double) -> Double in return (x * x * x - x * x * y + 9 * x * y * y) / (5 * x * x * y + 7 * y * y * y) }, data: nil))
        contourManagerRecords.append(ContourManagerRecord(fillContours: false, extrapolateToARectangleOfLimits: true, krigingSurfaceInterpolation: false, krigingSurfaceModel: .exponential, trig: false, functionLimits: [500, 500], plottitle: "Barametric Contours", functionExpression: nil, data:[
                            DataStructure(x: 875.0, y: 3375.0, z: 632.0),
                            DataStructure(x: 500.0, y: 4000.0, z: 634.0),
                            DataStructure(x: 2250.0, y: 1250.0, z: 654.2),
                            DataStructure(x: 3000.0, y: 875.0, z: 646.4),
                            DataStructure(x: 2560.0, y: 1187.0, z: 641.5),
                            DataStructure(x: 1000.0, y: 750.0, z: 650.0),
                            DataStructure(x: 2060.0, y: 1560.0, z: 634.0),
                            DataStructure(x: 3000.0, y: 1750.0, z: 643.3),
                            DataStructure(x: 2750.0, y: 2560.0, z: 639.4),
                            DataStructure(x: 1125.0, y: 2500.0, z: 630.1),
                            DataStructure(x: 875.0, y: 3125.0, z: 638.0),
                            DataStructure(x: 1000.0, y: 3375.0, z: 632.3),
                            DataStructure(x: 1060.0, y: 3500.0, z: 630.8),
                            DataStructure(x: 1250.0, y: 3625.0, z: 635.8),
                            DataStructure(x: 750.0, y: 3375.0, z: 625.6),
                            DataStructure(x: 560.0, y: 4125.0, z: 632.0),
                            DataStructure(x: 185.0, y: 3625.0, z: 624.2)]))
        contourManagerRecords.append(ContourManagerRecord(fillContours: false, extrapolateToARectangleOfLimits: false, krigingSurfaceInterpolation: false, krigingSurfaceModel: .exponential, trig: false, functionLimits:  [10000, 10000], plottitle: "Elevation Contours", functionExpression: nil, data:[
                                DataStructure(x: 1772721, y: 582282, z: -3547),
                                DataStructure(x: 1781139, y: 585845, z: -3663),
                                DataStructure(x: 1761209, y: 581803, z: -3469),
                                DataStructure(x: 1761897, y: 586146, z: -3511),
                                DataStructure(x: 1757824, y: 586542, z: -3474),
                                DataStructure(x: 1759248, y: 593855, z: -3513),
                                DataStructure(x: 1751962, y: 595979, z: -3488),
                                DataStructure(x: 1748562, y: 600461, z: -3495),
                                DataStructure(x: 1749475, y: 601824, z: -3545),
                                DataStructure(x: 1748429, y: 612332, z: -3656),
                                DataStructure(x: 1747542, y: 610708, z: -3631),
                                DataStructure(x: 1752576, y: 610150, z: -3650),
                                DataStructure(x: 1749236, y: 605604, z: -3612),
                                DataStructure(x: 1777262, y: 614320, z: -3984),
                                DataStructure(x: 1783097, y: 614590, z: -3928),
                                DataStructure(x: 1788724, y: 614569, z: -3922),
                                DataStructure(x: 1788779, y: 602482, z: -3928),
                                DataStructure(x: 1783525, y: 602816, z: -3827),
                                DataStructure(x: 1782876, y: 595479, z: -3805),
                                DataStructure(x: 1790263, y: 601620, z: -3956),
                                DataStructure(x: 1786390, y: 587821, z: -3748),
                                DataStructure(x: 1772472, y: 591331, z: -3549),
                                DataStructure(x: 1774055, y: 585498, z: -3580),
                                DataStructure(x: 1771047, y: 582144, z: -3528),
                                DataStructure(x: 1769765, y: 592200, z: -3586),
                                DataStructure(x: 1784676, y: 602478, z: -3866),
                                DataStructure(x: 1769118, y: 593814, z: -3606),
                                DataStructure(x: 1774711, y: 589327, z: -3632),
                                DataStructure(x: 1762207, y: 601476, z: -3666),
                                DataStructure(x: 1767705, y: 611207, z: -3781),
                                DataStructure(x: 1760792, y: 601961, z: -3653),
                                DataStructure(x: 1768391, y: 602228, z: -3758),
                                DataStructure(x: 1760453, y: 592626, z: -3441),
                                DataStructure(x: 1786913, y: 605529, z: -3748),
                                DataStructure(x: 1746521, y: 614853, z: -3654)]))
        contourManagerRecords.append(ContourManagerRecord(fillContours: true, extrapolateToARectangleOfLimits: true, krigingSurfaceInterpolation: true, krigingSurfaceModel: .exponential, trig: false, functionLimits:  [10, 10], firstResolution: 64, secondaryResolution: 1024, plottitle: "Kriging Contours", functionExpression: nil, data:[
            DataStructure(x: 134.170, y: 96.720, z:3.1),
            DataStructure(x: 131.430, y: 92.280, z:4.5),
            DataStructure(x: 116.900, y: 91.720, z:4.5),
            DataStructure(x: 133.280, y: 92.280, z:3.5),
            DataStructure(x: 127.720, y: 93.390, z:10.5),
            DataStructure(x: 123.810, y: 97.170, z:3.3),
            DataStructure(x: 125.870, y: 93.390, z:11.5),
            DataStructure(x: 128.180, y: 93.390, z:9.5),
            DataStructure(x: 132.400, y: 91.170, z:4.0),
            DataStructure(x: 127.720, y: 92.280, z:9.0),
            DataStructure(x: 133.210, y: 102.280, z:7.0),
            DataStructure(x: 131.440, y: 90.050, z:5.75),
            DataStructure(x: 133.280, y: 92.390, z:2.1),
            DataStructure(x: 120.590, y: 93.950, z:5.5),
            DataStructure(x: 132.360, y: 91.170, z:5.0),
            DataStructure(x: 115.220, y: 93.060, z:4.0),
            DataStructure(x: 143.860, y: 100.390, z:3.6),
            DataStructure(x: 112.210, y: 102.280, z:8.0),
            DataStructure(x: 141.590, y: 94.500, z:4.2),
            DataStructure(x: 119.210, y: 92.610, z:5.3),
            DataStructure(x: 119.110, y: 92.610, z:3.0),
            DataStructure(x: 116.900, y: 91.830, z:3.7),
            DataStructure(x: 111.920, y: 103.400, z:5.6),
            DataStructure(x: 112.180, y: 106.510, z:26),
            DataStructure(x: 128.370, y: 92.610, z:7.3),
            DataStructure(x: 121.460, y: 101.950, z:4.0),
            DataStructure(x: 116.810, y: 91.830, z:5.2),
            DataStructure(x: 128.460, y: 93.390, z:5.1),
            DataStructure(x: 128.600, y: 98.950, z:3.0),
            DataStructure(x: 132.550, y: 63.370, z:2.5),
            DataStructure(x: 133.520, y: 57.810, z:1.4),
            DataStructure(x: 130.470, y: 96.720, z:5.5),
            DataStructure(x: 129.570, y: 93.390, z:7.6),
            DataStructure(x: 120.120, y: 80.600, z:4.5),
            DataStructure(x: 112.490, y: 102.280, z:12.0),
            DataStructure(x: 124.900, y: 98.950, z:4.0),
            DataStructure(x: 120.680, y: 93.390, z:7.0),
            DataStructure(x: 133.240, y: 97.840, z:3.8),
            DataStructure(x: 131.420, y: 93.390, z:4.5),
            DataStructure(x: 124.640, y: 96.720, z:4.0),
            DataStructure(x: 124.730, y: 96.720, z:4.0),
            DataStructure(x: 116.990, y: 91.720, z:4.25),
            DataStructure(x: 131.420, y: 93.170, z:5.4),
            DataStructure(x: 122.720, y: 93.390, z:6.8),
            DataStructure(x: 129.790, y: 87.940, z:5.2),
            DataStructure(x: 128.270, y: 93.390, z:10.5)]))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        currentContour = contourManagerRecords[contourManagerCounter]
        
        createNavigationButtons(view, target: self, actions: [#selector(scrollUpButton(_:)), #selector(scrollDownButton(_:)), #selector(scrollLeftButton(_:)), #selector(scrollRightButton(_:)), #selector(zoomInButton(_:)), #selector(zoomOutButton(_:))])
        setupConfigurationButtons()
        
        if self.spinner == nil {
            self.spinner = SpinnerView(frame: CGRect(x: self.view.frame.width / 2 - 100, y: self.view.frame.height / 2 - 100, width: 200, height: 200))
            if let _spinner = self.spinner {
                _spinner.translatesAutoresizingMaskIntoConstraints = false
                self.view.addSubview(_spinner)
                self.view.addConstraints([
                        NSLayoutConstraint(item: _spinner, attribute: .centerX, relatedBy: .equal, toItem: self.view, attribute: .centerX, multiplier: 1.0, constant: 0.0),
                        NSLayoutConstraint(item: _spinner, attribute: .centerY, relatedBy: .equal, toItem: self.view, attribute: .centerY, multiplier: 1.0, constant: 0.0),
                        NSLayoutConstraint(item: _spinner, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: _spinner.bounds.size.width),
                        NSLayoutConstraint(item: _spinner, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: _spinner.bounds.size.height)])
                showSpinner(completion: nil)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let _hostingView = self.hostingView {
            let newGraph = CPTXYGraph(frame: _hostingView.bounds);
            newGraph.plotAreaFrame?.masksToBorder = false
            self.graph = newGraph
            _hostingView.hostedGraph = self.graph

            self.graph.titleDisplacement = CGPoint(x:0, y:-40)

            if let contourPlot = setupPlot(newGraph) {
                self.graph.add(contourPlot)
                self.graph.legend?.add(contourPlot)
            }
            longPressGestureForLegend = UILongPressGestureRecognizer(target: self, action: #selector(self.toggleContourLegend(_ :)))
            longPressGestureForLegend?.minimumPressDuration = 2.5
            longPressGestureForLegend?.delegate = self

            // Add legend
            let legendTextStyle = CPTMutableTextStyle()
            legendTextStyle.color =  CPTColor.black()
            legendTextStyle.fontSize = UIDevice.current.userInterfaceIdiom == .phone ? 9.0 : 14.0
            legendTextStyle.fontName = "Helvetica"

            let legendLineStyle = CPTMutableLineStyle()
            // for banding effect dont want to see the plot just the band
            legendLineStyle.lineWidth = 1.5
            legendLineStyle.lineColor = CPTColor.blue()

            self.graph.legend                    = CPTLegend(graph: newGraph)
            self.graph.legend?.textStyle          = legendTextStyle
            self.graph.legend?.fill               = CPTFill(color: CPTColor.clear())
            self.graph.legend?.borderLineStyle    = legendLineStyle
            self.graph.legend?.cornerRadius       = 5.0
            self.graph.legend?.swatchCornerRadius = 3.0
            self.graph.legendAnchor              = .top
            self.graph.legendDisplacement        = CGPoint(x: 0.0, y: -120.0);
            self.graph.legend?.delegate = self

            // Add title
            let titleTextStyle = CPTMutableTextStyle()
            titleTextStyle.color =  CPTColor.black()
            titleTextStyle.fontSize = UIDevice.current.userInterfaceIdiom == .phone ? 12.0 : 16.0
            titleTextStyle.fontName = "Helvetica-Bold"
            self.graph.titleTextStyle = titleTextStyle
            self.graph.title = "Contour Example"
            self.graph.titleDisplacement = CGPoint(x: 0, y: -40)
            
            // Note
            if let _plotArea = self.graph.plotAreaFrame?.plotArea {
                // Instructions
                let textStyle = CPTMutableTextStyle()
                textStyle.color    = CPTColor.darkGray()
                textStyle.fontSize = 16.0
                textStyle.fontName = "Helvetica"
                let explanationLayer = CPTTextLayer(text: "Tap on legend to increase no isocurves.\nLong press toggles showing legend for contours.\nUse Configure menu for changing contour examples,\n for swap beteen Delaunay & Kriging interpolation for raw data,\n for toggling extrapolating to corners for raw data\n and for toggle between filling contours", style: textStyle)
                let explanationAnnotation = CPTLayerAnnotation(anchorLayer: _plotArea)
                explanationAnnotation.rectAnchor         = .bottomLeft
                explanationAnnotation.contentLayer       = explanationLayer
                explanationAnnotation.contentAnchorPoint = CGPoint(x: 0.0, y: 0.0)
                explanationAnnotation.displacement = CGPoint(x: 50.0, y: 50.0)
                _plotArea.addAnnotation(explanationAnnotation)
            }
//            if let thePlotSpace = self.graph.allPlotSpaces().first as? CPTXYPlotSpace {
//                let ratio = graph.bounds.size.width / graph.bounds.size.height
//                if ratio > 1 {
//                    thePlotSpace.yRange = CPTPlotRange(location: NSNumber(value: -Double.pi), length:  NSNumber(value: Double.pi * 1.5))
//                    let xRange = CPTMutablePlotRange(location:NSNumber(value: -Double.pi), length:  NSNumber(value: Double.pi * 1.5))
//                    xRange.expand(byFactor: NSNumber(value: ratio))
//                    thePlotSpace.xRange = xRange
//                }
//                else {
//                    thePlotSpace.xRange = CPTPlotRange(location: NSNumber(value: -Double.pi), length:  NSNumber(value: Double.pi * 1.5))
//                    let yRange = CPTMutablePlotRange(location: NSNumber(value: -Double.pi), length:  NSNumber(value: Double.pi * 1.5))
//                    yRange.expand(byFactor: NSNumber(value: 1 / ratio))
//                    thePlotSpace.yRange = yRange
//                }
//            }
            self.graph.allowTracking = true;
        }
        
        if let _longPressGestureForLegend = longPressGestureForLegend {
            self.hostingView?.addGestureRecognizer(_longPressGestureForLegend)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let _longPressGestureForLegend = longPressGestureForLegend {
            self.hostingView?.removeGestureRecognizer(_longPressGestureForLegend)
        }
        longPressGestureForLegend = nil
    }
    
    private func setupPlot(_ graph: CPTXYGraph, noIsoCurves: UInt = 9) -> CPTContourPlot? {
        if let _currentContour = currentContour {
            createData()
            searchForLimits()
            var deltaX = (maxX - minX) / 20.0
            var deltaY = (maxY - minY) / 20.0
            if !_currentContour.extrapolateToARectangleOfLimits && _currentContour.functionExpression == nil {
                if _currentContour.krigingSurfaceInterpolation { // in order to prevent any borders make extra 25% on all 4 sides
                    deltaX = (maxX - minX) / 4.0
                    deltaY = (maxY - minY) / 4.0
                }
                else {
                    deltaX = (maxX - minX) / 10.0
                    deltaY = (maxY - minY) / 10.0
                }
            }
            minX -= deltaX
            maxX += deltaX
            minY -= deltaY
            maxY += deltaY
//            self.plotdata.sort { (a: DataStructure, b: DataStructure) -> Bool in
//                return a.x < b.x
//            }
//            hull = Hull(concavity: .infinity)
//            let _ = hull.hull(self.discontinuousData.map({ [$0.x, $0.y] }), nil)
//            print(hull.hull)
//
//            let _/*continuousData*/ = self.plotdata.filter( {
//                var have = true
//                for i in 0..<discontinuousData.count {
//                    if ( $0.x == discontinuousData[i].x && $0.y == discontinuousData[i].y ) {
//                        have = false
//                        break
//                    }
//                }
//                return have
//            })
            
            
//            self.discontinuousData.sort { (a: DataStructure, b: DataStructure) -> Bool in
//                return a.x < b.x
//            }
//            hull.concavity = 1.0
//            let _ = hull.hull(self.discontinuousData.map({ [$0.x, $0.y] }), nil)
//            let _ = hull.hull(continuousData.map({ [$0.x, $0.y] }), nil)
//            for pt in hull.hull {
//                if let _pt = pt as? [Double] {
//                    print(_pt[0], ",", _pt[1])
//                }
//            }
            
          //  print(hull.hull)
            
//            let _ = hull.hull(data.map({ [$0.x, $0.y]  }), nil)
//            print("hull")
//            for pt in hull.hull {
//                if let _pt = pt as? [Double] {
//                    print("\(_pt[0]), \(_pt[1])")
//                }
//            }
            
//            let objcHull = _CPTHull(concavity: 5.0)
//            var cgPoints = /*self.discontinuousData*/data.map({ CGPoint(x: $0.x, y: $0.y) })
//
//            let p = withUnsafeMutablePointer(to: &cgPoints[0]) { (p) -> UnsafeMutablePointer<CGPoint> in
//                return p
//            }
//            objcHull.quickConvexHull(onViewPoints: p, dataCount:  UInt(/*self.discontinuousData*/data.count))
//            print("convex")
//            for point in UnsafeBufferPointer(start: objcHull.hullpointsArray(), count: Int(objcHull.hullpointsCount())) {
//                print("\(point.point.x), \(point.point.y)")
//            }
            
//            objcHull.concaveHull(onViewPoints: p, dataCount: UInt(self.discontinuousData.count))
//            for point in UnsafeBufferPointer(start: objcHull.hullpointsArray(), count: Int(objcHull.hullpointsCount())) {
//                print(point)
//            }
//            objcHull.concavity = 2.0
//            objcHull.concaveHull(onViewPoints: p, dataCount: UInt(/*self.discontinuousData*/data.count))
//            print("objc")
//            for point in UnsafeBufferPointer(start: objcHull.hullpointsArray(), count: Int(objcHull.hullpointsCount())) {
////                print(point)
//                print("\(point.point.x), \(point.point.y)")
//            }
            
//            let boundaryPoints = quickHullOnPlotData(plotdata: self.plotdata)
//            if !boundaryPoints.isEmpty {
//                print(boundaryPoints)
//            }
//        }
            let ratio = graph.bounds.size.width / graph.bounds.size.height
             // Setup plot space
            if let plotSpace = graph.defaultPlotSpace as? CPTXYPlotSpace {
                graph.remove(plotSpace)
                if let plot = graph.allPlots().first as? CPTContourPlot {
                    if let legend = graph.legend {
                        legend.remove(plot)
                    }
                    graph.remove(plot)
                }
            }
  
            let newPlotSpace = setupPlotSpace(self.graph, deltaX: deltaX, deltaY: deltaY)
            graph.add(newPlotSpace)
            if let plotSpace = graph.defaultPlotSpace as? CPTXYPlotSpace {
                plotSpace.allowsMomentum = false
                plotSpace.allowsUserInteraction = true
                plotSpace.delegate              = self
                
                if let xRange = plotSpace.xRange.mutableCopy() as? CPTMutablePlotRange,
                   let yRange = plotSpace.yRange.mutableCopy() as? CPTMutablePlotRange {
                    // Expand the ranges to put some space around the plot
                    xRange.expand(byFactor: NSNumber(value: 1.025))
                    xRange.location = plotSpace.xRange.location
                    yRange.expand(byFactor:NSNumber(value: 1.025))
                    
                    xRange.expand(byFactor:NSNumber(value:2.0))
                    yRange.expand(byFactor:NSNumber(value:2.0))
                    plotSpace.globalXRange = xRange
                    plotSpace.globalYRange = yRange
                    
                    var labelFormatter: NumberFormatter?
                    if ( _currentContour.trig ) {
                        labelFormatter = PiNumberFormatter()
                        labelFormatter?.multiplier = NSNumber(value: 16)
                    }
                    else {
                        labelFormatter = NumberFormatter()
                        labelFormatter?.maximumFractionDigits = 2
                    }
                    
                    // Axes
                    if let axisSet = graph.axisSet as? CPTXYAxisSet {
                        let textStyles = CPTMutableTextStyle()
                        textStyles.color    = CPTColor.blue()
                        textStyles.fontName = "Helvetica"
                        textStyles.fontSize = 12.0
                        let gridLineStyleMajor = CPTMutableLineStyle()
                        gridLineStyleMajor.lineWidth = 1.0
                        gridLineStyleMajor.lineColor = CPTColor.darkGray()
                        let gridLineStyleMinor = CPTMutableLineStyle()
                        gridLineStyleMinor.lineWidth = 0.5
                        gridLineStyleMinor.lineColor = CPTColor.gray()
                        var x2: CPTXYAxis?
                        var y2: CPTXYAxis?
                        if let x = axisSet.xAxis {
                            x.plotSpace = newPlotSpace
                            x.labelingPolicy = .fixedInterval
                            if _currentContour.functionExpression != nil,
                               let functionLimits = _currentContour.functionLimits,
                               functionLimits.count == 4 {
                                x.majorIntervalLength   = NSNumber(value: (functionLimits[1] - functionLimits[0]) / 8.0 )
                            }
                            else {
                                x.majorIntervalLength   = NSNumber(value: _currentContour.functionLimits?[0] ?? 500.0)
                            }
                            
                            x.axisConstraints = CPTConstraints.constraint(withLowerOffset: 0.0)
                            x.titleDirection = CPTSign.positive
                            x.labelAlignment = CPTAlignment.center
                            x.title = "X"
                            x.titleOffset = 30.0
                            x.tickLabelDirection = CPTSign.positive
                            x.labelTextStyle = textStyles
                            x.labelFormatter = labelFormatter
                        
                   //         x.orthogonalPosition    = NSNumber(value: minX)
                            x.visibleAxisRange = xRange
                            x.minorTicksPerInterval = 4;
                            x.majorGridLineStyle = gridLineStyleMajor
                            x.minorGridLineStyle = gridLineStyleMinor
                            x.labelRotation = .pi / 4
                            
                            
                            x2 = CPTXYAxis()
                            if let _x2 = x2 {
                                _x2.coordinate = CPTCoordinate.X
                                _x2.plotSpace = newPlotSpace
                                _x2.title = x.title
                                _x2.titleTextStyle = x.titleTextStyle
                                _x2.titleDirection = CPTSign.negative
                                _x2.titleOffset = 30.0
                                _x2.axisConstraints = CPTConstraints.constraint(withUpperOffset: 0.0)
                                _x2.majorIntervalLength = x.majorIntervalLength
                                _x2.labelingPolicy = CPTAxisLabelingPolicy.fixedInterval
                                _x2.separateLayers = false
                                _x2.minorTicksPerInterval = 9
                                _x2.tickDirection = CPTSign.none
                                _x2.tickLabelDirection = CPTSign.negative
                                _x2.labelTextStyle = x.labelTextStyle
                                _x2.labelAlignment = CPTAlignment.center
                                _x2.axisLineStyle = x.axisLineStyle
                                _x2.majorTickLength = x.majorTickLength
                                _x2.majorTickLineStyle = x.axisLineStyle
                                _x2.minorTickLength = x.minorTickLength
                                _x2.labelFormatter = labelFormatter
                                _x2.labelRotation = .pi / 4
                                _x2.delegate = self
                            }
                        }
                        if let y = axisSet.yAxis {
                            y.plotSpace = newPlotSpace
                            y.labelingPolicy = .fixedInterval
                            if _currentContour.functionExpression != nil,
                               let functionLimits = _currentContour.functionLimits,
                               functionLimits.count == 4 {
                                y.majorIntervalLength   = NSNumber(value: (functionLimits[3] - functionLimits[2]) / 8.0 )
                            }
                            else {
                                y.majorIntervalLength   = NSNumber(value: _currentContour.functionLimits?[1] ?? 500.0)
                            }
                            y.minorTicksPerInterval = UInt(4)
                            y.visibleAxisRange = yRange
                            
                            y.axisConstraints = CPTConstraints.constraint(withLowerOffset: 0.0)
                            y.labelAlignment = CPTAlignment.center
                            y.title = "Y"
                            y.titleDirection = CPTSign.positive
                            y.tickLabelDirection = CPTSign.positive
                            y.titleOffset = 30.0
                            y.titleDirection = CPTSign.positive
                            y.labelTextStyle = textStyles
                            
                            //y.orthogonalPosition    = NSNumber(value: minY)
                            y.majorGridLineStyle = gridLineStyleMajor
                            y.minorGridLineStyle = gridLineStyleMinor
                            y.labelFormatter = labelFormatter
                            y.labelRotation = .pi / 4
                            
                            y2 = CPTXYAxis()
                            if let _y2 = y2 {
                                _y2.coordinate = CPTCoordinate.Y
                                _y2.plotSpace = newPlotSpace
                                _y2.title = y.title
                                _y2.titleTextStyle = y.titleTextStyle
                                _y2.titleOffset = 30.0
                                _y2.titleDirection = CPTSign.negative
                                _y2.axisConstraints = CPTConstraints.constraint(withUpperOffset: 0.0)
                                _y2.majorIntervalLength = y.majorIntervalLength
                                _y2.labelingPolicy = CPTAxisLabelingPolicy.fixedInterval
                                _y2.separateLayers = false
                                _y2.minorTicksPerInterval = 9
                                _y2.tickDirection = CPTSign.none
                                _y2.tickLabelDirection = CPTSign.negative
                                _y2.labelTextStyle = y.labelTextStyle
                                _y2.labelAlignment = CPTAlignment.center
                                _y2.axisLineStyle = y.axisLineStyle
                                _y2.majorTickLength = y.majorTickLength
                                _y2.majorTickLineStyle = y.axisLineStyle
                                _y2.minorTickLength = y.minorTickLength
                                _y2.labelFormatter = labelFormatter
                                _y2.labelRotation = .pi / 4
                                _y2.delegate = self
                            }
                        }
                        if let x = axisSet.xAxis,
                           let y = axisSet.yAxis,
                           let _x2 = x2,
                           let _y2 = y2 {
                            graph.axisSet?.axes =  [x, y, _x2, _y2]
                        }
                    }
                    
                    plotSpace.scale(toFit: graph.allPlots())
                }
            }
        
            // Contour properties
            let contourPlot = CPTContourPlot()
            contourPlot.setFirstGridColumns(_currentContour.firstResolution, rows: _currentContour.firstResolution)
            contourPlot.setSecondaryGridColumns(_currentContour.secondaryResolution, rows: _currentContour.secondaryResolution)
            if _currentContour.functionExpression != nil {
                contourPlot.identifier = "function" as NSCoding & NSCopying & NSObjectProtocol
            }
            else {
                contourPlot.identifier = "data" as NSCoding & NSCopying & NSObjectProtocol
            }
            contourPlot.title = _currentContour.plottitle
            contourPlot.interpolation = .curved
            contourPlot.curvedInterpolationOption = .normal
            
            let lineStyle = CPTMutableLineStyle()
            // for banding effect dont want to see the plot just the band
            lineStyle.lineWidth = 3.0
            lineStyle.lineColor = CPTColor.blue()
            
            // isoCurve label appearance
            let labelTextstyle = CPTMutableTextStyle()
            labelTextstyle.fontName = "Helvetica"
            labelTextstyle.fontSize = UIDevice.current.userInterfaceIdiom == .phone ? 10.0 : 14.0
            labelTextstyle.textAlignment = .center
            labelTextstyle.color = CPTColor.black()
            contourPlot.isoCurvesLabelTextStyle = labelTextstyle
            let labelFormatter = NumberFormatter()
    //        labelFormatter.minimumSignificantDigits = 0
    //        labelFormatter.maximumSignificantDigits = 2
    //        labelFormatter.usesSignificantDigits = true
            labelFormatter.maximumFractionDigits = 2
            contourPlot.isoCurvesLabelFormatter = labelFormatter;
            
            contourPlot.isoCurveLineStyle = lineStyle
            contourPlot.alignsPointsToPixels = true
            
            contourPlot.noIsoCurves = noIsoCurves
            contourPlot.functionPlot = _currentContour.functionExpression != nil
            contourPlot.minFunctionValue = minFunctionValue;
            contourPlot.maxFunctionValue = maxFunctionValue;
            contourPlot.limits = [NSNumber(value: minX), NSNumber(value: maxX), NSNumber(value: minY), NSNumber(value: maxY)]
            contourPlot.extrapolateToLimits = _currentContour.extrapolateToARectangleOfLimits
            contourPlot.fillIsoCurves = _currentContour.fillContours
            
            if let identifier = contourPlot.identifier as? String,
               identifier == "data" {
                currentContour?.functionLimits = [minX , maxX, minY, maxY];
                contourPlot.easyOnTheEye = true
            }
            
            var resolution: CGFloat = 1.0
            if let plotArea = self.graph.plotAreaFrame?.plotArea {
                if(ratio < 1.0) {
                    resolution = plotArea.bounds.size.height * 0.02
                }
                else {
                    resolution = plotArea.bounds.size.width * 0.02
                }
            }
            
            if _currentContour.functionExpression != nil,
               let functionLimits = _currentContour.functionLimits {
                contourPlot.limits = [NSNumber(value: functionLimits[0]), NSNumber(value: functionLimits[1]), NSNumber(value: functionLimits[2]), NSNumber(value: functionLimits[3])]
                contourPlot.easyOnTheEye = true
                do {
                    if let plotDataSource = try generateFunctionDataForContours(dataSourceContourPlot: contourPlot) {
                        plotDataSource.resolutionX = resolution
                        plotDataSource.resolutionY = resolution
                        self.dataBlockSources?.append(plotDataSource)
                        contourPlot.dataSourceBlock = plotDataSource.dataSourceBlock
                        if functionLimits[0] == -Double.greatestFiniteMagnitude || functionLimits[1] == Double.greatestFiniteMagnitude || functionLimits[2] == -Double.greatestFiniteMagnitude || functionLimits[3] == Double.greatestFiniteMagnitude {
                            contourPlot.dataSource = plotDataSource
                        }
                        else {
                            contourPlot.dataSource = self
                            contourPlot.dataSourceBlock = plotDataSource.dataSourceBlock
                            contourPlot.minFunctionValue = minFunctionValue
                            contourPlot.maxFunctionValue = maxFunctionValue
                        }
                        contourPlot.functionPlot = true
                        contourPlot.plotSymbol = nil
    //                    let plotSymbol = CPTPlotSymbol()
    //                    plotSymbol.symbolType = .ellipse
    //                    plotSymbol.fill = CPTFill(color: .black())
    //        //            plotSymbol.lineStyle = lineStyle
    //                    plotSymbol.size = CGSize(width: 3, height: 3)
    //                    contourPlot.plotSymbol = plotSymbol
                    }
                }
                catch let error as NSError {
                    print("Error: \(error.localizedDescription)")
                    print("Error: \(String(describing: error.localizedFailureReason))")
                }
            }
            else {
                if let plotDataSource = setupContoursDataSource(plot: contourPlot, minX: minX, maxX: maxX, minY: minY, maxY: maxY) {
                    plotDataSource.resolutionX = resolution
                    plotDataSource.resolutionY = resolution
                    self.dataBlockSources?.append(plotDataSource)
                    contourPlot.dataSourceBlock = plotDataSource.dataSourceBlock
                }
                contourPlot.functionPlot =  false
                if ( /*self.krigingSurfaceInterpolation &&*/ !_currentContour.extrapolateToARectangleOfLimits ) {
                    contourPlot.joinContourLineStartToEnd = false
                }
                let plotSymbol = CPTPlotSymbol()
                plotSymbol.symbolType = .diamond
                plotSymbol.fill = CPTFill(color: .white())
    //            plotSymbol.lineStyle = lineStyle
                plotSymbol.size = CGSize(width: 10, height: 10)
                contourPlot.plotSymbol = plotSymbol
            }
            contourPlot.dataSource = self
            contourPlot.appearanceDataSource = self
            contourPlot.delegate     = self
            contourPlot.showLabels = true
            contourPlot.showIsoCurvesLabels = true
            
            if let _ = _currentContour.functionExpression {
                self.toggleExtrapolateToLimitsRectangleButton?.isEnabled = false
                self.chooseSurfaceInterpolationMethodButton?.isEnabled = false
            }
            else {
                self.toggleExtrapolateToLimitsRectangleButton?.isEnabled = true
                self.chooseSurfaceInterpolationMethodButton?.isEnabled = true
            }
            
            return contourPlot
        }
        else {
            return nil
        }
    }
    
    private func setupPlotSpace(_ graph: CPTXYGraph, deltaX: CGFloat, deltaY: CGFloat) -> CPTXYPlotSpace {
        let ratio = graph.bounds.size.width / graph.bounds.size.height
        let newPlotSpace = CPTXYPlotSpace()
        if ratio > 1 {
            let lengthRatio = (maxY - minY) / (maxX - minX)
            newPlotSpace.yRange = CPTPlotRange(location: NSNumber(value: minY - 2.0 * deltaY), length:  NSNumber(value: maxY - minY + 2.0 * deltaY))
            let xRange = CPTMutablePlotRange(location: NSNumber(value: minX - 2.0 * deltaX), length: NSNumber(value: (maxX - minX) * ratio * lengthRatio + 2.0 * deltaX))
//                xRange.expand(byFactor: NSNumber(value: ratio))
            newPlotSpace.xRange = xRange
        }
        else {
            let lengthRatio = (maxX - minX) / (maxY - minY)
            newPlotSpace.xRange = CPTPlotRange(location:  NSNumber(value: minX - 2.0 * deltaX), length: NSNumber(value: maxX - minX + 2.0 * deltaX))
            let yRange = CPTMutablePlotRange(location: NSNumber(value: minY - 2.0 * deltaY), length:  NSNumber(value: (maxY - minY) / ratio * lengthRatio + 2.0 * deltaY))
//                yRange.expand(byFactor: NSNumber(value: 1 / ratio))
            newPlotSpace.yRange = yRange
        }
        return newPlotSpace
    }
    
    private func createData() {
        // clean up old data
        if self.plotdata.count > 0 {
            self.plotdata.removeAll()
        }
        if let _currentContour = currentContour {
            if let _ = _currentContour.functionExpression {
                do {
                    try generateInitialFunctionData()
                    if !discontinuousData.isEmpty {
                        let outerDiscontinuousPoints = quickHullOnPlotData(plotdata: discontinuousData)
                        print(outerDiscontinuousPoints)
                    }
                }
                catch let error as NSError {
                    print("Error: \(error.localizedDescription)")
                    print("Error: \(String(describing: error.localizedFailureReason))")
                }
            }
            else if let _data = _currentContour.data {
                for i in 0..<_data.count {
                    self.plotdata.append(_data[i])
                }
            }
        }
    }
    
    private func searchForLimits() {
        if let _currentContour = currentContour,
           _currentContour.functionExpression != nil,
           let _functionLimits = _currentContour.functionLimits {
            minX = _functionLimits[0]
            maxX = _functionLimits[1]
            minY = _functionLimits[2]
            maxY = _functionLimits[3]
        }
        else {
            if let _minX = self.plotdata.map({ $0.x }).min() {
                minX = _minX
            }
            if let _maxX = self.plotdata.map({ $0.x }).max() {
                maxX = _maxX
            }
            if let _minY = self.plotdata.map({ $0.y }).min() {
                minY = _minY
            }
            if let _maxY = self.plotdata.map({ $0.y }).max() {
                maxY = _maxY
            }
        }
        if let _minFunctionValue = self.plotdata.map({ $0.z }).min() {
            minFunctionValue = _minFunctionValue
        }
        if let _maxFunctionValue = self.plotdata.map({ $0.z }).max() {
            maxFunctionValue = _maxFunctionValue
        }
    }
    
    private func setupContoursDataSource(plot: CPTContourPlot, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CPTFieldFunctionDataSource? {
        var plotFieldFunctionDataSource: CPTFieldFunctionDataSource?
        if var _currentContour = currentContour {
            // use delaunay triangles to extrapolate to rectangle limits
            var vertices: [Point] = []
            var index = 0
            for data in self.plotdata {
                var point = Point(x: data.x, y: data.y)
                point.value = data.z
                point.index = index
                vertices.append(point)
                index += 1
            }
            
            let tree: KDTree<Point> = KDTree(values: vertices)
            if _currentContour.extrapolateToARectangleOfLimits {
                let edgePoints = [Point(x: minX, y: minY), Point(x: minX, y: (minY + maxY) / 3.0), Point(x: minX, y: (minY + maxY) * 2.0 / 3.0), Point(x: minX, y: maxY), Point(x: (minX + maxX) / 3.0, y: maxY), Point(x: (minX + maxX) * 2.0 / 3.0, y: maxY), Point(x: maxX, y: minY), Point(x: maxX, y: (minY + maxY) / 3.0), Point(x: maxX, y: (minY + maxY) * 2.0 / 3.0), Point(x: maxX, y: maxY), Point(x: (minX + maxX) / 3.0, y: minY), Point(x: (minX + maxX) * 2.0 / 3.0, y: minY)]

                for var point in edgePoints {
                    if !vertices.contains(point) {
                        let nearestPoints: [Point] = tree.nearestK(2, to: point)
                        point.value = TriangleInterpolation.triangle_extrapolate_linear_singleton( p1: [nearestPoints[0].x, nearestPoints[0].y], p2: [nearestPoints[1].x, nearestPoints[1].y], p: [point.x, point.y], v1: nearestPoints[0].value, v2: nearestPoints[1].value)
                        point.index = index
                        vertices.append(point)
                        index += 1
                    }
                }
            }
            
            if _currentContour.krigingSurfaceInterpolation {
                var knownXPositions: [Double] = self.plotdata.map({ $0.x })
                var knownYPositions: [Double] = self.plotdata.map({ $0.y })
                var knownValues: [Double] = self.plotdata.map({ $0.z })
                // include edges
                knownXPositions += vertices[self.plotdata.count..<vertices.count].map({ $0.x })
                knownYPositions += vertices[self.plotdata.count..<vertices.count].map({ $0.y })
                knownValues += vertices[self.plotdata.count..<vertices.count].map({ $0.value })
                let kriging: Kriging = Kriging()
                kriging.train(t: knownValues, x: knownXPositions, y: knownYPositions, model: _currentContour.krigingSurfaceModel, sigma2: 1.0, alpha: 10.0)
                if kriging.error == KrigingError.none {
                    plotFieldFunctionDataSource = generateInterpolatedDataForContoursUsingKriging(plot, kriging: kriging)
                }
                else {
                    _currentContour.krigingSurfaceInterpolation = false
                }
            }
            if !_currentContour.krigingSurfaceInterpolation {
                let triangles = Delaunay().triangulate(vertices) // Delauney uses clockwise ordered nodes
                plotFieldFunctionDataSource = generateInterpolatedDataForContoursUsingDelaunay(plot, triangles: triangles)
            }
        }
        return plotFieldFunctionDataSource
    }

    private func generateInterpolatedDataForContoursUsingDelaunay(_ dataSourceContourPlot: CPTContourPlot, triangles:[Triangle]) -> CPTFieldFunctionDataSource? {
        let plotDataSource = CPTFieldFunctionDataSource(for: dataSourceContourPlot, withBlock: { xValue, yValue in
            var functionValue: Double = 0 // Double.nan // such that if x,y outside triangle returns nonsnese
            let point = Point(x: xValue, y: yValue)
            for triangle in triangles {
                if triangle.contain(point) {
                    let v = TriangleInterpolation.triangle_interpolate_linear( m: 1, n: 1, p1: [triangle.point1.x, triangle.point1.y], p2: [triangle.point2.x, triangle.point2.y], p3: [triangle.point3.x, triangle.point3.y], p: [xValue, yValue], v1: [triangle.point1.value], v2: [triangle.point2.value], v3: [triangle.point3.value])
                    functionValue = v[0]
                    break;
                }
            }
            return functionValue
        } as CPTContourDataSourceBlock)
        
        return plotDataSource
    }
    
    private func generateInterpolatedDataForContoursUsingKriging(_ dataSourceContourPlot: CPTContourPlot, kriging: Kriging) -> CPTFieldFunctionDataSource? {
        let plotDataSource = CPTFieldFunctionDataSource(for: dataSourceContourPlot, withBlock: { xValue, yValue in
            return kriging.predict(x: xValue, y: yValue)
        } as CPTContourDataSourceBlock)
        
        return plotDataSource
    }
    
    private func generateFunctionDataForContours(dataSourceContourPlot: CPTContourPlot) throws -> CPTFieldFunctionDataSource? {
        let plotDataSource: CPTFieldFunctionDataSource = CPTFieldFunctionDataSource(for: dataSourceContourPlot, withBlock: { xValue, yValue in
            var functionValue: Double = Double.greatestFiniteMagnitude
            do {
                functionValue = try self.calculateFunctionValueAtXY(xValue, y: yValue)
            }
            catch let exception as NSError {
                print("An exception occurred: \(exception.localizedDescription)")
                print("Here are some details: \(String(describing: exception.localizedFailureReason))")
            }
            return functionValue
            
        } as CPTContourDataSourceBlock)
        
        return plotDataSource
    }
    
    private func generateInitialFunctionData() throws -> Void {
        if let _currentContour = self.currentContour,
           let functionLimits = _currentContour.functionLimits,
           functionLimits.count == 4 && functionLimits[0] < functionLimits[1] && functionLimits[2] < functionLimits[3] {
            var _y: Double = functionLimits[2]
            let increment: Double = (functionLimits[1] - functionLimits[0]) / 32.0
            while _y < functionLimits[3] + increment - 0.000001 {
                var _x: Double = functionLimits[0]
                while _x < functionLimits[1] + increment - 0.000001 {
                    do {
                        let _z = try calculateFunctionValueAtXY(_x, y: _y)
                        let data = DataStructure(x: _x, y: _y, z: _z)
                        if _z.isNaN || _z.isInfinite /*_z == Double.greatestFiniteMagnitude || _z == -Double.greatestFiniteMagnitude*/ {
                            self.discontinuousData.append(data)
                        }
                        self.plotdata.append(data)
                        _x += increment
                    }
                    catch let error as NSError {
                        print("An exception occurred: \(error.domain)")
                        print("Here are some details: \(String(describing: error.code)), \(error.localizedDescription)")
                        throw error
                    }
                }
                _y += increment
            }
        }
    }
    
    private func calculateFunctionValueAtXY(_ x: Double, y: Double) throws -> Double {
        if let _currentContour = self.currentContour,
           let functionExpression = _currentContour.functionExpression {
            return functionExpression(x, y)
//            var functionValue: Double = functionExpression(x, y)
//            if (-functionValue).isInfinite {
//                functionValue = Double.greatestFiniteMagnitude
//            }
//            else if functionValue.isInfinite {
//                functionValue = -Double.greatestFiniteMagnitude
//            }
    //        else if functionValue.isNaN {
    //            functionValue = -0.0
    //            let errString = "Result is not a number(nan)"
    //            let error = NSError(domain: Bundle.main.bundleIdentifier! + ".MathParserError", code: 222, userInfo: [NSLocalizedDescriptionKey: errString, NSLocalizedFailureReasonErrorKey: "It is possible there is a solution in your function that has turned complex, unfortunatley the DDMathParser used in this app cannot handle complex numbers. Please recheck your limits nb. stopped at x = \(x), y = \(y)."])
    //            throw error
    //        }
//            return functionValue
        }
        else {
            return -0
        }
    }
    
    
    // MARK: -
    // MARK: Plot Data Source Methods
    
    func numberOfRecords(for plot: CPTPlot) -> UInt {
        return UInt(self.plotdata.count)
    }

    func number(for plot: CPTPlot, field fieldEnum: UInt, record idx: UInt) -> Any? {
        switch Int(fieldEnum) {
            case CPTContourPlotField.X.rawValue:
                return self.plotdata[Int(idx)].x
            case CPTContourPlotField.Y.rawValue:
                return self.plotdata[Int(idx)].y
            default:
                return self.plotdata[Int(idx)].z
        }
    }
    
    func dataLabel(for plot: CPTPlot, record idx: UInt) -> CPTLayer? {
        var newLayer: CPTTextLayer? = nil
        
        if let contourPlot = plot as? CPTContourPlot,
           !contourPlot.functionPlot {
            let dataPoint: DataStructure = self.plotdata[Int(idx)]
            let annotationString: String  = String(format: "%0.1f", dataPoint.z)
            newLayer = CPTTextLayer(text: annotationString)
            let textStyle = CPTMutableTextStyle(style: newLayer?.textStyle)
            textStyle.textAlignment = .center
            newLayer?.textStyle = textStyle
        }
        return newLayer
    }

    // MARK: -
    // MARK: Plot Delegate Methods
    
    func didFinishDrawing(_ plot: CPTPlot) {
        if let _spinner = self.spinner {
            DispatchQueue.main.async {
                _spinner.isHidden = true
            }
        }
        
        if self.isLegendShowing,
            let contourPlot = plot as? CPTContourPlot {
            showColourCodeAnnotation(contourPlot)
        }
    }
    
//    func contourPlot(_ plot: CPTContourPlot, plotSymbolWasSelectedAtRecord idx: UInt) {
//        print(idx)
//    }
    
    // MARK: -
    // MARK:  Plot Space Delegate Methods
    
    func plotSpace(_ space: CPTPlotSpace, shouldHandlePointingDeviceDownEvent event: UIEvent, at point: CGPoint) -> Bool {
        if let _ = self.pointTextAnnotation {
            removePointTextAnnotation()
            return false
        }
        else if let plotSpace = space as? CPTXYPlotSpace,
           let contourPlot = self.graph.allPlots().first as? CPTContourPlot,
            let _hostingView = self.hostingView,
            let plotArea = self.graph.plotAreaFrame?.plotArea,
                let _currentContour = self.currentContour {
           
            let diffX = (_hostingView.bounds.width - plotArea.bounds.width) / 2.0
            let diffY = (_hostingView.bounds.height - plotArea.bounds.height) / 2.0
            
            let x = Double((point.x - diffX) / contourPlot.scaleX + plotSpace.xRange.locationDouble)
            let y = Double((point.y - diffY) / contourPlot.scaleY + plotSpace.yRange.locationDouble)
//            let x = Double(point.x / contourPlot.scaleX + plotSpace.xRange.locationDouble)
//            let y = Double(point.y / contourPlot.scaleY + plotSpace.yRange.locationDouble)
            let fieldValue = contourPlot.dataSourceBlock?(x,y) ?? 0.0
            
            let anchorPoint: [Double] = [x, y]
            var plotPoint: [Decimal] =  [Decimal(), Decimal()]
            plotPoint[CPTCoordinate.X.rawValue] = Decimal(x)
            plotPoint[CPTCoordinate.Y.rawValue] = Decimal(y)
            
            var annotationString: String = ""
            let labelFormatter: NumberFormatter = NumberFormatter()
            if ( _currentContour.trig ) {
                let piLabelFormatter = PiNumberFormatter()
                piLabelFormatter.multiplier = NSNumber(value: 32)
                annotationString += "\t\(piLabelFormatter.string(from: NSNumber(value: x)) ?? String(format:"%8.3f", x))\n"
                annotationString += "\t\(piLabelFormatter.string(from: NSNumber(value: y)) ?? String(format:"%8.3f", y))\n"
            }
            else {
                labelFormatter.maximumFractionDigits = 3
                annotationString += "\t\(labelFormatter.string(from: NSNumber(value: x)) ?? String(format:"%8.3f", x))\n"
                annotationString += "\t\(labelFormatter.string(from: NSNumber(value: y)) ?? String(format:"%8.3f", y))\n"
//                annotationString = "\t\(String(format:"%8.3f", x))\n"
//                annotationString += "\t\(String(format:"%8.3f", y))\n"
//
            }
            labelFormatter.maximumFractionDigits = 3
//            "annotationString += "\tf(x,y):\t\(String(format:"%8.3f", fieldValue))"
            annotationString += "\tf(x,y):\t\(labelFormatter.string(from: NSNumber(value: fieldValue)) ?? String(format:"%8.3f", fieldValue))"
            
            let tableParagraphStyle: NSMutableParagraphStyle? = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle
            var annotationFont: UIFont?
            if UIDevice.current.userInterfaceIdiom == .phone {
                annotationFont = UIFont(name: "Helvetica", size: 9.0)
                tableParagraphStyle?.tabStops = [NSTextTab(textAlignment: .left, location: 5.0, options: [:]), NSTextTab(textAlignment: .right, location: 50.0, options: [:])]
            }
            else {
                annotationFont = UIFont(name: "Helvetica", size: 12.0)
                tableParagraphStyle?.tabStops = [NSTextTab(textAlignment: .left, location: 5.0, options: [:]), NSTextTab(textAlignment: .right, location: 65.0, options: [:])]
            }
            let annotationMutableAttribString: NSMutableAttributedString = NSMutableAttributedString(string: annotationString, attributes: [NSAttributedString.Key.font: annotationFont!, NSAttributedString.Key.foregroundColor: UIColor.blue, NSAttributedString.Key.paragraphStyle: tableParagraphStyle!])
            
            // Now add the annotation to the plot area
            let textLayer = CPTTextLayer(attributedText: annotationMutableAttribString)
            textLayer.fill = CPTFill(color: CPTColor(componentRed: 1.0, green: 1.0, blue: 0.762, alpha: 0.6))
            let lineStyleBorder = CPTMutableLineStyle()
            lineStyleBorder.lineColor = CPTColor.gray()
            lineStyleBorder.lineWidth = 1.0
            textLayer.borderLineStyle = lineStyleBorder
            textLayer.cornerRadius = 5.0
            textLayer.paddingLeft = 10
            textLayer.paddingRight = 10
            
            self.pointTextAnnotation = CPTPlotSpaceAnnotation(plotSpace: plotSpace, anchorPlotPoint: anchorPoint as [NSNumber])
            
            let outerBorderPath = CGMutablePath()
            
            var minx = CGRectGetMinX(textLayer.bounds)
            let midx = CGRectGetMidX(textLayer.bounds)
            var maxx = CGRectGetMaxX(textLayer.bounds)
            let miny = CGRectGetMinY(textLayer.bounds)
            let midy = CGRectGetMidY(textLayer.bounds)
            let maxy = CGRectGetMaxY(textLayer.bounds);
            
            if Double((point.x + maxx - diffX) / contourPlot.scaleX) + plotSpace.xRange.locationDouble < plotSpace.xRange.endDouble {
                minx += 5
                outerBorderPath.move(to: CGPoint(x: midx, y: miny))
                outerBorderPath.addArc(tangent1End: CGPoint(x: maxx, y: miny), tangent2End: CGPoint(x: maxx, y: midy), radius: textLayer.cornerRadius)
                outerBorderPath.addArc(tangent1End: CGPoint(x: maxx, y: maxy), tangent2End: CGPoint(x: midx, y: maxy), radius: textLayer.cornerRadius)
                outerBorderPath.addArc(tangent1End: CGPoint(x: minx, y: maxy), tangent2End: CGPoint(x: minx, y: midy), radius: textLayer.cornerRadius)
                outerBorderPath.addLine(to: CGPoint(x: minx, y: miny + midy + 5))
                outerBorderPath.addLine(to: CGPoint(x: minx - 5, y: miny + midy))
                outerBorderPath.addLine(to: CGPoint(x: minx, y: miny + midy - 5))
                outerBorderPath.addArc(tangent1End: CGPoint(x: minx, y: miny), tangent2End: CGPoint(x: midx, y: miny), radius: textLayer.cornerRadius)
                self.pointTextAnnotation?.contentAnchorPoint = CGPoint(x: 0, y: 0.5)
            }
            else {
                maxx -= 5
                outerBorderPath.move(to: CGPoint(x: midx, y: miny))
                outerBorderPath.addArc(tangent1End: CGPoint(x: minx, y: miny), tangent2End: CGPoint(x: minx, y: midy), radius: textLayer.cornerRadius)
                outerBorderPath.addArc(tangent1End: CGPoint(x: minx, y: maxy), tangent2End: CGPoint(x: midx, y: maxy), radius: textLayer.cornerRadius)
                outerBorderPath.addArc(tangent1End: CGPoint(x: maxx, y: maxy), tangent2End: CGPoint(x: maxx, y: midy), radius: textLayer.cornerRadius)
                outerBorderPath.addLine(to: CGPoint(x: maxx, y: miny + midy + 5))
                outerBorderPath.addLine(to: CGPoint(x: maxx + 5, y: miny + midy))
                outerBorderPath.addLine(to: CGPoint(x: maxx, y: miny + midy - 5))
                outerBorderPath.addArc(tangent1End: CGPoint(x: maxx, y: miny), tangent2End: CGPoint(x: midx, y: miny), radius: textLayer.cornerRadius)
                self.pointTextAnnotation?.contentAnchorPoint = CGPoint(x: 1.0, y: 0.5)
            }
            outerBorderPath.closeSubpath()

            textLayer.outerBorderPath = outerBorderPath
            self.pointTextAnnotation?.contentLayer = textLayer
            if let _pointTextAnnotation = self.pointTextAnnotation {
                graph.plotAreaFrame?.plotArea?.addAnnotation(_pointTextAnnotation)
            }
            return true
        }
        return false
    }
    
//    func plotSpace(_ space: CPTPlotSpace, shouldHandlePointingDeviceUp event: UIEvent, at point: CGPoint) -> Bool {
//        return false
//    }
    
    func plotSpace(_ space: CPTPlotSpace, didChangePlotRangeFor coordinate: CPTCoordinate) {
        
        if let axes = graph.axisSet?.axes as? [CPTXYAxis],
           let plotspace = space as? CPTXYPlotSpace {
            for axis in axes {
                if let constraints = axis.axisConstraints,
                   constraints.isEqual(toConstraint:  CPTConstraints.constraint(withUpperOffset: 0.0)) || constraints.isEqual(toConstraint:  CPTConstraints.constraint(withLowerOffset: 0.0)) {
                    if axis.coordinate == .X {
                        axis.titleLocation = plotspace.xRange.midPoint;
                    }
                    else {
                        axis.titleLocation = plotspace.yRange.midPoint;
                    }
                }
            }
        }
    }
    
    private func removePointTextAnnotation() -> Void {
        if let _pointTextAnnotation = self.pointTextAnnotation {
            if let plotArea = self.graph.plotAreaFrame?.plotArea, plotArea.annotations.contains(_pointTextAnnotation) {
                self.graph.plotAreaFrame?.plotArea?.removeAnnotation(_pointTextAnnotation)
            }
            self.pointTextAnnotation = nil
        }
    }
    
    // MARK: -
    // MARK: CPTContourPlot Appearance Source Methods
    
    func lineStyle(for plot: CPTContourPlot, isoCurve idx: UInt) -> CPTLineStyle? {
        let linestyle = CPTMutableLineStyle(style: plot.isoCurveLineStyle)
        if let noIsoCurveValues = plot.getIsoCurveValues()?.count {
            var red:CGFloat = 0
            var green:CGFloat = 0
            var blue:CGFloat = 0
            let alpha:CGFloat = 1.0
            
            let value = CGFloat(idx) / CGFloat(noIsoCurveValues)
            blue = min(max(1.5 - 4.0 * abs(value - 0.25), 0.0), 1.0)
            green = min(max(1.5 - 4.0 * abs(value - 0.5), 0.0), 1.0)
            red  = min(max(1.5 - 4.0 * abs(value - 0.75), 0.0), 1.0)
            let colour = CPTColor(componentRed: red, green: green, blue: blue, alpha: alpha)
            linestyle.lineColor = colour
            return linestyle
        }
        else {
            return linestyle
        }
    }
    
    func fill(for plot: CPTContourPlot, isoCurve idx: UInt) -> CPTFill? {
//        if let _currentContour = self.currentContour,
//           _currentContour.fillContours,
//            let noIsoCurveValues = plot.getIsoCurveFills()?.count {
//            var red:CGFloat = 0
//            var green:CGFloat = 0
//            var blue:CGFloat = 0
//            let alpha:CGFloat = 0.8
//            let value: CGFloat = CGFloat(idx) / CGFloat(noIsoCurveValues + 1)
//            blue = min(max(1.5 - 4.0 * abs(value - 0.25), 0.0), 1.0)
//            green = min(max(1.5 - 4.0 * abs(value - 0.5), 0.0), 1.0)
//            red  = min(max(1.5 - 4.0 * abs(value - 0.75), 0.0), 1.0)
//            let colour = CPTColor(componentRed: red, green: green, blue: blue, alpha: alpha)
//            let fill = CPTFill(color: colour)
//            return fill
//        }
//        else {
            return nil
//        }
    }
    
    func isoCurveLabel(for plot: CPTContourPlot, isoCurveValueIndex idx: UInt) -> CPTLayer? {
        var newLayer: CPTTextLayer?
        if let isoCurveValues  = plot.getIsoCurveValues(),
            idx < isoCurveValues.count,
            let formatter = plot.isoCurvesLabelFormatter {
            let labelString = formatter.string(for: isoCurveValues[Int(idx)])
            if let isoCurvesLabelTextStyle = plot.isoCurvesLabelTextStyle {
                if let _ = isoCurvesLabelTextStyle.color {
                    newLayer = CPTTextLayer(text: labelString, style: plot.isoCurvesLabelTextStyle)
                }
                else {
                    let mutLabelTextStyle = CPTMutableTextStyle(style: plot.isoCurvesLabelTextStyle)
                    var red:CGFloat = 0
                    var green:CGFloat = 0
                    var blue:CGFloat = 0
                    let alpha:CGFloat = 0.8
                    let value:CGFloat = CGFloat(idx+1) / CGFloat(isoCurveValues.count+1)
                    blue = min(max(1.5 - 4.0 * abs(value - 0.25), 0.0), 1.0)
                    green = min(max(1.5 - 4.0 * abs(value - 0.5), 0.0), 1.0)
                    red  = min(max(1.5 - 4.0 * abs(value - 0.75), 0.0), 1.0)
                        let color = CPTColor(componentRed: red, green: green, blue: blue, alpha: alpha)
                    mutLabelTextStyle.color = color
                    newLayer = CPTTextLayer(text: labelString, style: mutLabelTextStyle)
                }
            }
            else {
                let lightGrayText = CPTMutableTextStyle()
                lightGrayText.color = CPTColor.lightGray()
                lightGrayText.fontName = "Helvetica"
                lightGrayText.fontSize = self.graph.titleTextStyle?.font?.pointSize ?? 10.0
                newLayer = CPTTextLayer(text: labelString, style: lightGrayText)
            }
        }
        return newLayer
    }

    // MARK: -
    // MARK: CPTLegendDelegate method
    
    func legend(_ legend: CPTLegend, legendEntryFor plot: CPTPlot, wasSelectedAt idx: UInt, with event: UIEvent) {
        if let contourPlot = plot as? CPTContourPlot {
            if let _ = colourCodeAnnotation {
                isLegendShowing = true
                removeColourCodeAnnotation()
            }
            showSpinner() { _ in
                if( contourPlot.noIsoCurves + 1 > 21 ) {
                    contourPlot.noIsoCurves = 4
                }
                else {
                    contourPlot.noIsoCurves += 1
                }
            }
//            DispatchQueue.global(qos: .userInitiated).async {
//                if( contourPlot.noIsoCurves + 1 > 21 ) {
//                    contourPlot.noIsoCurves = 4
//                }
//                else {
//                    contourPlot.noIsoCurves += 1
//                }
//                DispatchQueue.global(qos: .background).async {
//                    DispatchQueue.main.async {
////                        if let _spinner = self.spinner {
////                            _spinner.isHidden = false
////                        }
//                        SwiftSpinner.show(self.message)
//                    }
//                }
//            }
        }
    }

    
    func legend(_ legend: CPTLegend, lineStyleForEntryAt idx: UInt, for plot: CPTPlot?) -> CPTLineStyle? {
        if let contourPlot = plot as? CPTContourPlot {
            if let entries = legend.getEntries() as? [CPTLegendEntry],
               let index = entries.firstIndex(where: { $0.indexCustomised == idx }),
               let _ = entries[index].plotCustomised,
               let _isoCurveLineStyles = contourPlot.getIsoCurveLineStyles(),
               let _isoCurveIndices = contourPlot.getIsoCurveIndices(),
               _isoCurveIndices.count > 0 && idx < _isoCurveIndices.count {
                return _isoCurveLineStyles[Int(truncating: _isoCurveIndices[Int(idx)])]
            }
            else {
                return nil;
            }
        }
        else {
            return nil;
        }
    }
    
    func legend(_ legend: CPTLegend, fillForSwatchAt idx: UInt, for plot: CPTPlot?) -> CPTFill? {
        if let _currentContour = self.currentContour,
           _currentContour.fillContours,
           let entries = legend.getEntries() as? [CPTLegendEntry],
           let index = entries.firstIndex(where: { $0.indexCustomised == idx }),
           let contourPlot = plot as? CPTContourPlot,
           entries[index].plotCustomised == contourPlot,
           let _isoCurveFills = contourPlot.getIsoCurveFills(),
           _isoCurveFills.count > 0 && idx < _isoCurveFills.count,
           let _fill = _isoCurveFills[Int(idx)] as? CPTFill {
            return _fill
        }
        else  {
            return nil;
        }
    }
    

    // MARK: -
    // MARK: Manage Colour Code Annotations
    
    private func showColourCodeAnnotation(_ plot: CPTContourPlot) {
        colourCodeAnnotation = CPTAnnotation()
        if let _isoCurveValues = plot.getIsoCurveValues(),
           let _isoCurveIndices = plot.getIsoCurveIndices() {
            let borderLineStyle = CPTMutableLineStyle()
            borderLineStyle.lineColor = CPTColor.black()
            borderLineStyle.lineWidth = 0.5
            let textStyle = CPTMutableTextStyle()
            textStyle.fontName = "Helvetica"
            textStyle.fontSize = UIDevice.current.userInterfaceIdiom == .phone ? 8.0 : 12.0
            let colorCodeLegend = CPTLegend()
//            colorCodeLegend.fill = CPTFill(color: CPTColor(genericGray: 0.95).withAlphaComponent(0.6))
            colorCodeLegend.fill = CPTFill(color: CPTColor(componentRed: 1.0, green: 1.0, blue: 0.762, alpha: 0.6))
            colorCodeLegend.borderLineStyle = borderLineStyle
            colorCodeLegend.swatchSize = CGSize(width: 25.0, height: 16.0)
            var legendEntries:[CPTLegendEntry] = []
            if let _currentContour = self.currentContour,
               _currentContour.fillContours {
                if let _fillings = plot.getIsoCurveFillings() as? [CPTContourFill] {
                    let noContourFillColours = _fillings.count
                    colorCodeLegend.numberOfRows = UInt(noContourFillColours) / (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4)
                    if UInt(noContourFillColours) % (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) > 0 {
                        colorCodeLegend.numberOfRows = colorCodeLegend.numberOfRows + 1
                    }
                    colorCodeLegend.numberOfColumns = UInt(noContourFillColours) > (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) ? (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) : UInt(noContourFillColours)
                    for i in 0..<noContourFillColours {
                        let legendEntry = CPTLegendEntry()
                        legendEntry.indexCustomised = UInt(i)
                        legendEntry.plotCustomised = plot
                        legendEntry.textStyle = textStyle
                        let filling = _fillings[i]
                        if filling.firstValue == nil,
                            let _secondValue = filling.secondValue {
                            legendEntry.titleCustomised = String(format:">%0.2f", _secondValue.doubleValue)
                        }
                        else if filling.secondValue == nil,
                            let _firstValue = filling.firstValue {
                            legendEntry.titleCustomised = String(format:"<%0.2f", _firstValue.doubleValue)
                        }
                        else {
                            if let _firstValue = filling.firstValue,
                               let _secondValue = filling.secondValue {
                                if _firstValue.doubleValue == _secondValue.doubleValue {
                                    legendEntry.titleCustomised = String(format:"%0.2f", _firstValue.doubleValue)
                                }
                                else if _firstValue.doubleValue > _secondValue.doubleValue {
                                    legendEntry.titleCustomised = String(format:"%0.2f - %0.2f", _secondValue.doubleValue, _firstValue.doubleValue)
                                }
                                else {
                                    legendEntry.titleCustomised = String(format:"%0.2f - %0.2f", _firstValue.doubleValue, _secondValue.doubleValue)
                                }
                            }
                        }
                        legendEntries.append(legendEntry)
                    }
                }
                else {
                    let noContourFillColours = _isoCurveIndices.count + 1
                    colorCodeLegend.numberOfRows = UInt(noContourFillColours) / (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4)
                    if UInt(noContourFillColours) % (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) > 0 {
                        colorCodeLegend.numberOfRows = colorCodeLegend.numberOfRows + 1
                    }
                    colorCodeLegend.numberOfColumns = UInt(noContourFillColours) > (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) ? (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) : UInt(noContourFillColours)
                    

                    var firstValue = _isoCurveValues[Int(truncating: _isoCurveIndices[0])].doubleValue
                    let legendEntry0 = CPTLegendEntry()
                    legendEntry0.indexCustomised = UInt(truncating: _isoCurveIndices[0])
                    legendEntry0.plotCustomised = plot
                    legendEntry0.textStyle = textStyle
                    if( firstValue == 1000.0 * _isoCurveValues[Int(truncating: _isoCurveIndices[1])].doubleValue ) {
                        legendEntry0.titleCustomised = "Discontinuous"
                    }
                    else {
                        legendEntry0.titleCustomised = String(format:"<%0.2f", _isoCurveValues[Int(truncating: _isoCurveIndices[0])].doubleValue)
                    }
                    legendEntries.append(legendEntry0)
                    for i in 1..<noContourFillColours - 1 {
                        let legendEntry = CPTLegendEntry()
                        legendEntry.indexCustomised = UInt(truncating: _isoCurveIndices[i])
                        legendEntry.plotCustomised = plot
                        legendEntry.textStyle = textStyle
                        legendEntry.titleCustomised = String(format:"%0.2f - %0.2f", firstValue, _isoCurveValues[Int(truncating: _isoCurveIndices[i])].doubleValue)
                        firstValue = _isoCurveValues[Int(truncating: _isoCurveIndices[i])].doubleValue
                        legendEntries.append(legendEntry)
                    }
                    let legendEntry1 = CPTLegendEntry()
                    legendEntry1.indexCustomised = UInt(truncating: _isoCurveIndices[_isoCurveIndices.count - 1])
                    legendEntry1.plotCustomised = plot
                    legendEntry1.textStyle = textStyle
                    if( _isoCurveValues[Int(truncating: _isoCurveIndices[_isoCurveIndices.count - 1])].doubleValue == 1000.0 * _isoCurveValues[Int(truncating: _isoCurveIndices[_isoCurveIndices.count - 2])].doubleValue ) {
                        legendEntry1.titleCustomised = "Discontinuous"
                    }
                    else {
                        legendEntry1.titleCustomised = String(format:">%0.2f", _isoCurveValues[Int(truncating: _isoCurveIndices[_isoCurveIndices.count - 1])].doubleValue)
                    }
                    legendEntries.append(legendEntry1)
                }
                
                colorCodeLegend.setNewLegendEntries(NSMutableArray(array: legendEntries))
            }
            else {
                if let _isoCurveLineStyles = plot.getIsoCurveLineStyles() {
                    colorCodeLegend.numberOfRows = UInt(_isoCurveIndices.count) / (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4)
                    if UInt(_isoCurveIndices.count) % (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) > 0 {
                        colorCodeLegend.numberOfRows = colorCodeLegend.numberOfRows + 1
                    }
                    colorCodeLegend.numberOfColumns = UInt(_isoCurveIndices.count) > (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) ? (UIDevice.current.userInterfaceIdiom == .phone ? 3 : 4) : UInt(_isoCurveIndices.count)

                    for i in 0..<_isoCurveIndices.count {
                        let legendEntry = CPTLegendEntry()
                        legendEntry.indexCustomised = UInt(truncating: _isoCurveIndices[i])
                        legendEntry.plotCustomised = plot
                        legendEntry.textStyle = textStyle
                        if( (i == 0 && _isoCurveValues[Int(truncating: _isoCurveIndices[i])].doubleValue == 1000.0 * _isoCurveValues[Int(truncating: _isoCurveIndices[i + 1])].doubleValue) || (i == _isoCurveIndices.count - 1 &&  _isoCurveValues[Int(truncating: _isoCurveIndices[i])].doubleValue == 1000 * _isoCurveValues[Int(truncating: _isoCurveIndices[i - 1])].doubleValue) ) {
                            legendEntry.titleCustomised = "Discontinuous"
                        }
                        else {
                            legendEntry.titleCustomised = String(format:"%0.2f", _isoCurveValues[Int(truncating: _isoCurveIndices[i])].doubleValue)
                        }
                        legendEntry.lineStyleCustomised = _isoCurveLineStyles[Int(truncating: _isoCurveIndices[i])]
                        legendEntries.append(legendEntry)
                    }
                    colorCodeLegend.setNewLegendEntries(NSMutableArray(array: legendEntries))
                }
            }
            colorCodeLegend.cornerRadius = 5.0
            colorCodeLegend.rowMargin = 5.0
            colorCodeLegend.paddingLeft = 6.0
            colorCodeLegend.paddingTop = 6.0
            colorCodeLegend.paddingRight = 6.0
            colorCodeLegend.paddingBottom = 6.0
            colorCodeLegend.delegate = self
            colourCodeAnnotation?.contentLayer = colorCodeLegend

            graph.plotAreaFrame?.plotArea?.addAnnotation(colourCodeAnnotation)
            colorCodeLegend.position = CGPoint(x: (graph.plotAreaFrame?.plotArea?.bounds.width ?? 150.0) * 0.5, y: 70.0)
        }
    }

    private func removeColourCodeAnnotation() {
        if let _colourCodeAnnotation = self.colourCodeAnnotation,
           let annotations = graph.plotAreaFrame?.plotArea?.annotations,
           annotations.contains(_colourCodeAnnotation) {
            graph.plotAreaFrame?.plotArea?.removeAnnotation(_colourCodeAnnotation)
        }
        self.colourCodeAnnotation = nil
    }
    
    // MARK: -
    // MARK: Segue
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "showContourManagerPopOver") || (segue.identifier == "showContourManager") {
            contourManagerViewController = (segue.destination as? ContourManagerViewController)
            contourManagerViewController?.contourManagerRecords = self.contourManagerRecords
            contourManagerViewController?.contourManagerCounter = self.contourManagerCounter
            contourManagerViewController?.delegate = self
            if (segue.identifier == "showContourManagerPopOver") {
                contourManagerViewController?.popoverPresentationController?.delegate = self
                if let _tappedContourManagerButton = tappedContourManagerButton {
                    contourManagerViewController?.popoverPresentationController?.sourceView = self.view
                    contourManagerViewController?.popoverPresentationController?.sourceRect = _tappedContourManagerButton.frame
                }
                contourManagerViewController?.popoverPresentationController?.permittedArrowDirections = .down
                contourManagerViewController?.popoverPresentationController?.backgroundColor = UIColor.init(red: 1.0, green: 0.75, blue: 0.793, alpha: 1.0)
            }
            shouldPerformSegue(withIdentifier: segue.identifier!, sender: self)
        }
        else if (segue.identifier == "showSurfaceInterpolationManagerPopOver") || (segue.identifier == "showSurfaceInterpolationManager") {
            surfaceInterpolationManagerViewController = (segue.destination as? SurfaceInterpolationManagerViewController)
            surfaceInterpolationManagerViewController?.currentContour = self.currentContour
            surfaceInterpolationManagerViewController?.delegate = self
            if (segue.identifier == "showSurfaceInterpolationManagerPopOver") {
                surfaceInterpolationManagerViewController?.popoverPresentationController?.delegate = self
                if let _chooseSurfaceInterpolationMethodButton = chooseSurfaceInterpolationMethodButton {
                    surfaceInterpolationManagerViewController?.popoverPresentationController?.sourceView = self.view
                    surfaceInterpolationManagerViewController?.popoverPresentationController?.sourceRect = _chooseSurfaceInterpolationMethodButton.frame
                }
                surfaceInterpolationManagerViewController?.popoverPresentationController?.permittedArrowDirections = .down
                surfaceInterpolationManagerViewController?.popoverPresentationController?.backgroundColor = UIColor.init(red: 1.0, green: 0.75, blue: 0.793, alpha: 1.0)
            }
            shouldPerformSegue(withIdentifier: segue.identifier!, sender: self)
        }
    }
    
    // MARK: -
    // MARK: Button Navigation of Plot
    
    func createNavigationButtons(_ view: UIView, target: Any, actions: [Selector]) {
        
        var navigationSize: CGSize
        var zoomSize: CGSize
        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationSize = CGSize(width: 32, height: 32)
            zoomSize = CGSize(width: 48, height: 48)
        }
        else {
            navigationSize = CGSize(width: 24, height: 24)
            zoomSize = CGSize(width: 32, height: 32)
        }
        
        let scrollUpButton = UIButton(frame: CGRect(x: 0.0, y: 0.0, width: navigationSize.width, height: navigationSize.width))
        scrollUpButton.setImage(UIImage(systemName: "arrowtriangle.up.fill")?.scale(to: navigationSize)?.tinted(with: .black), for: .normal)
        scrollUpButton.addTarget(target, action: actions[0], for: .touchUpInside)
        view.addSubview(scrollUpButton)
        let scrollDownButton = UIButton(frame: CGRect(x: 0.0, y: 0.0, width: navigationSize.width, height: navigationSize.height))
        scrollDownButton.setImage(UIImage(systemName: "arrowtriangle.down.fill")?.scale(to: navigationSize)?.tinted(with: .black), for: .normal)
        scrollDownButton.addTarget(target, action: actions[1], for: .touchUpInside)
        view.addSubview(scrollDownButton)
        let scrollLeftButton = UIButton(frame: CGRect(x: 0.0, y: 0.0, width: navigationSize.width, height: navigationSize.height))
        scrollLeftButton.setImage(UIImage(systemName: "arrowtriangle.left.fill")?.scale(to: navigationSize)?.tinted(with: .black), for: .normal)
        scrollLeftButton.addTarget(target, action: actions[2], for: .touchUpInside)
        view.addSubview(scrollLeftButton)
        let scrollRightButton = UIButton(frame: CGRect(x: 0.0, y: 0.0, width: navigationSize.width, height: navigationSize.height))
        scrollRightButton.setImage(UIImage(systemName: "arrowtriangle.right.fill")?.scale(to: navigationSize)?.tinted(with: .black), for: .normal)
        scrollRightButton.addTarget(target, action: actions[3], for: .touchUpInside)
        view.addSubview(scrollRightButton)
        
        scrollDownButton.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([
            NSLayoutConstraint(item: scrollDownButton, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: -navigationSize.height),
            NSLayoutConstraint(item: scrollDownButton, attribute: .trailing, relatedBy: .equal, toItem: view, attribute: .trailing, multiplier: 1.0, constant: -navigationSize.width),
            NSLayoutConstraint(item: scrollDownButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.width),
            NSLayoutConstraint(item: scrollDownButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.height)
        ])
        scrollUpButton.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([
            NSLayoutConstraint(item: scrollUpButton, attribute: .bottom, relatedBy: .equal, toItem: scrollDownButton, attribute: .top, multiplier: 1.0, constant: -navigationSize.height),
            NSLayoutConstraint(item: scrollUpButton, attribute: .centerX, relatedBy: .equal, toItem: scrollDownButton, attribute: .centerX, multiplier: 1.0, constant: 0.0),
            NSLayoutConstraint(item: scrollUpButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.width),
            NSLayoutConstraint(item: scrollUpButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.height)
        ])
        
        scrollRightButton.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([
            NSLayoutConstraint(item: scrollRightButton, attribute: .bottom, relatedBy: .equal, toItem: scrollDownButton, attribute: .top, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: scrollRightButton, attribute: .leading, relatedBy: .equal, toItem: scrollDownButton, attribute: .trailing, multiplier: 1.0, constant: -4.0),
            NSLayoutConstraint(item: scrollRightButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.width),
            NSLayoutConstraint(item: scrollRightButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.height)
        ])
        scrollLeftButton.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([
            NSLayoutConstraint(item: scrollLeftButton, attribute: .bottom, relatedBy: .equal, toItem: scrollDownButton, attribute: .top, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: scrollLeftButton, attribute: .trailing, relatedBy: .equal, toItem: scrollDownButton, attribute: .leading, multiplier: 1.0, constant: 4.0),
            NSLayoutConstraint(item: scrollLeftButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.width),
            NSLayoutConstraint(item: scrollLeftButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: navigationSize.height)
        ])
        
        let zoomInButton = UIButton(frame: CGRect(x: 0.0, y: 0.0, width: zoomSize.width, height: zoomSize.height))
        zoomInButton.setImage(UIImage(systemName: "plus.magnifyingglass")?.scale(to: zoomSize)?.tinted(with: .black), for: .normal)
        zoomInButton.addTarget(target, action: actions[4], for: .touchUpInside)
        view.addSubview(zoomInButton)
        let zoomOutButton = UIButton(frame: CGRect(x: 0.0, y: 0.0, width: zoomSize.width, height: zoomSize.height))
        zoomOutButton.setImage(UIImage(systemName: "minus.magnifyingglass")?.scale(to: zoomSize)?.tinted(with: .black), for: .normal)
        zoomOutButton.addTarget(target, action: actions[5], for: .touchUpInside)
        view.addSubview(zoomOutButton)
        
        zoomInButton.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([
            NSLayoutConstraint(item: zoomInButton, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: -navigationSize.height * 4),
            NSLayoutConstraint(item: zoomInButton, attribute: .trailing, relatedBy: .equal, toItem: view, attribute: .trailing, multiplier: 1.0, constant: -zoomSize.width / 2 + 2),
            NSLayoutConstraint(item: zoomInButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: zoomSize.width),
            NSLayoutConstraint(item: zoomInButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: zoomSize.height)
        ])
        zoomOutButton.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([
            NSLayoutConstraint(item: zoomOutButton, attribute: .bottom, relatedBy: .equal, toItem: zoomInButton, attribute: .top, multiplier: 1.0, constant: -4.0),
            NSLayoutConstraint(item: zoomOutButton, attribute: .centerX, relatedBy: .equal, toItem: zoomInButton, attribute: .centerX, multiplier: 1.0, constant: 0.0),
            NSLayoutConstraint(item: zoomOutButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: zoomSize.width),
            NSLayoutConstraint(item: zoomOutButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 0.0, constant: zoomSize.height)
        ])
    }
    
    @objc func scrollUpButton(_ sender: Any) {
        if let _plotSpace = self.graph.defaultPlotSpace as? CPTXYPlotSpace {
            let newYPlotRange = CPTPlotRange(location: NSNumber(value:_plotSpace.yRange.locationDouble + _plotSpace.yRange.lengthDouble / 16.0), length: _plotSpace.yRange.length)
//            if let _currentContour = self.currentContour,
//               _currentContour.functionExpression != nil {
//                showSpinner() { _ in
//                    _plotSpace.yRange = newYPlotRange
//                }
//            }
//            else {
                _plotSpace.yRange = newYPlotRange
//            }
        }
    }
    
    @objc func scrollDownButton(_ sender: Any) {
        if let _plotSpace = self.graph.defaultPlotSpace as? CPTXYPlotSpace {
            let newYPlotRange = CPTPlotRange(location: NSNumber(value:_plotSpace.yRange.locationDouble - _plotSpace.yRange.lengthDouble / 16.0), length: _plotSpace.yRange.length)
//            if let _currentContour = self.currentContour,
//               _currentContour.functionExpression != nil {
//                showSpinner() { _ in
//                    _plotSpace.yRange = newYPlotRange
//                }
//            }
//            else {
                _plotSpace.yRange = newYPlotRange
//            }
        }
    }
    
    @objc func scrollLeftButton(_ sender: Any) {
        if let _plotSpace = self.graph.defaultPlotSpace as? CPTXYPlotSpace {
            let newXPlotRange = CPTPlotRange(location: NSNumber(value:_plotSpace.xRange.locationDouble - _plotSpace.xRange.lengthDouble / 16.0), length: _plotSpace.xRange.length)
//            if let _currentContour = self.currentContour,
//               _currentContour.functionExpression != nil {
//                showSpinner() { _ in
//                    _plotSpace.xRange = newXPlotRange
//                }
//            }
//            else {
                _plotSpace.xRange = newXPlotRange
//            }
        }
    }
    
    @objc func scrollRightButton(_ sender: Any) {
        if let _plotSpace = self.graph.defaultPlotSpace as? CPTXYPlotSpace {
            let newXPlotRange = CPTPlotRange(location: NSNumber(value:_plotSpace.xRange.locationDouble + _plotSpace.xRange.lengthDouble / 16.0), length: _plotSpace.xRange.length)
//            if let _currentContour = self.currentContour,
//               _currentContour.functionExpression != nil {
//                showSpinner() { _ in
//                    _plotSpace.xRange = newXPlotRange
//                }
//            }
//            else {
                _plotSpace.xRange = newXPlotRange
//            }
        }
    }
    
    @objc func zoomInButton(_ sender: Any) {
        if let _plotSpace = self.graph.defaultPlotSpace as? CPTXYPlotSpace {
            if let _ = self.colourCodeAnnotation {
                self.isLegendShowing = true
                self.removeColourCodeAnnotation()
            }
            let newXPlotRange = CPTMutablePlotRange(location: _plotSpace.xRange.location, length: _plotSpace.xRange.length)
            let newYPlotRange = CPTMutablePlotRange(location: _plotSpace.yRange.location, length: _plotSpace.yRange.length)
            newXPlotRange.expand(byFactor: NSNumber(value: 2.0 / 3.0))
            newYPlotRange.expand(byFactor: NSNumber(value: 2.0 / 3.0))
            showSpinner() { _ in
                _plotSpace.xRange = newXPlotRange
                _plotSpace.yRange = newYPlotRange
            }
        }
    }
    @objc func zoomOutButton(_ sender: Any) {
        if let _plotSpace = self.graph.defaultPlotSpace as? CPTXYPlotSpace {
            if let _ = self.colourCodeAnnotation {
                self.isLegendShowing = true
                self.removeColourCodeAnnotation()
            }
            let newXPlotRange = CPTMutablePlotRange(location: _plotSpace.xRange.location, length: _plotSpace.xRange.length)
            let newYPlotRange = CPTMutablePlotRange(location: _plotSpace.yRange.location, length: _plotSpace.yRange.length)
            newXPlotRange.expand(byFactor: NSNumber(value: 1.5))
            newYPlotRange.expand(byFactor: NSNumber(value: 1.5))
            showSpinner() { _ in
                _plotSpace.xRange = newXPlotRange
                _plotSpace.yRange = newYPlotRange
            }
        }
    }
    
    func setupConfigurationButtons() {
        if let _currentContour = self.currentContour {
        
            if let _toggleFillButton = self.toggleFillButton {
                if _currentContour.fillContours {
                    _toggleFillButton.setImage(UIImage(systemName: "waveform.path.ecg.rectangle.fill"), for: .normal)
                }
                else {
                    _toggleFillButton.setImage(UIImage(systemName: "waveform.path.ecg.rectangle"), for: .normal)
                }
            }
            
            if let _toggleExtrapolateToLimitsRectangleButton = self.toggleExtrapolateToLimitsRectangleButton {
                if _currentContour.extrapolateToARectangleOfLimits {
                    _toggleExtrapolateToLimitsRectangleButton.setImage(UIImage(systemName: "arrow.down.forward.and.arrow.up.backward"), for: .normal)
                }
                else {
                    _toggleExtrapolateToLimitsRectangleButton.setImage(UIImage(systemName: "arrow.up.backward.and.arrow.down.forward"), for: .normal)
                }
            }
            
            if let _tappedContourManagerButton = self.tappedContourManagerButton {
                if _currentContour.functionExpression != nil {
                    _tappedContourManagerButton.setImage(UIImage(systemName: "f.square"), for: .normal)
                }
                else {
                    _tappedContourManagerButton.setImage(UIImage(systemName: "f.square.fill"), for: .normal)
                }
            }
        }
    }
    
    @IBAction func tappedContourManagerButton(_ sender: Any?) {
        removePointTextAnnotation()
        
        contourManagerViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ContourManager") as? ContourManagerViewController
        
        contourManagerViewController?.contourManagerRecords = self.contourManagerRecords
        contourManagerViewController?.contourManagerCounter = self.contourManagerCounter
        contourManagerViewController?.delegate = self
        if let popover = contourManagerViewController,
            let _sender = sender as? PopoverPresentationSourceView {
            present(popover: popover, from: _sender, size: CGSize(width: 320, height: 400), arrowDirection: .any)
        }
    }
    
    @IBAction func tappedRedrawContoursButton(_ sender: Any?) {
        removePointTextAnnotation()
        
        if let _ = self.currentContour,
           let plot = self.graph.allPlots().first as? CPTContourPlot {
            if let _ = self.colourCodeAnnotation {
                self.isLegendShowing = true
                self.removeColourCodeAnnotation()
            }
            self.graph.remove(plot)
            self.graph.legend?.remove(plot)
            self.graph.allowTracking = false
            showSpinner() { _ in
                if let contourPlot = self.setupPlot(self.graph) {
                    self.graph.add(contourPlot)
                    self.graph.legend?.add(contourPlot)
                    self.graph.allowTracking = true
                    if self.isLegendShowing {
                        self.showColourCodeAnnotation(contourPlot)
                    }
                }
            }
        }
    }
    
    @IBAction func toggleFillContoursButton(_ sender: Any?) {
        removePointTextAnnotation()
        if var _currentContour = self.currentContour,
           let plot = self.graph.allPlots().first as? CPTContourPlot{
            _currentContour.fillContours = !_currentContour.fillContours
            self.currentContour?.fillContours = _currentContour.fillContours
            if let _ = self.colourCodeAnnotation {
                self.isLegendShowing = true
                self.removeColourCodeAnnotation()
            }
            showSpinner() { _ in
                plot.fillIsoCurves = _currentContour.fillContours
                plot.reloadData()
                if let toggleFillButton = sender as? UIButton {
                    if _currentContour.fillContours {
                        toggleFillButton.setImage(UIImage(systemName: "waveform.path.ecg.rectangle.fill"), for: .normal)
                    }
                    else {
                        toggleFillButton.setImage(UIImage(systemName: "waveform.path.ecg.rectangle"), for: .normal)
                    }
                }
            }
            
//            DispatchQueue.global(qos: .userInitiated).async {
//                if let _ = self.colourCodeAnnotation {
//                    self.isLegendShowing = true
//                    self.removeColourCodeAnnotation()
//                }
//                plot.fillIsoCurves = _currentContour.fillContours
//                plot.reloadData()
//                DispatchQueue.global(qos: .background).async {
//                    DispatchQueue.main.async {
////                        if let _spinner = self.spinner {
////                            _spinner.isHidden = false
////                        }
//                        SwiftSpinner.show(self.message, animated: true)
//                        if let toggleFillButton = sender as? UIButton {
//                            if _currentContour.fillContours {
//                                toggleFillButton.setImage(UIImage(systemName: "waveform.path.ecg.rectangle.fill"), for: .normal)
//                            }
//                            else {
//                                toggleFillButton.setImage(UIImage(systemName: "waveform.path.ecg.rectangle"), for: .normal)
//                            }
//                        }
//                    }
//                }
//            }
        }
    }
    
    @IBAction func toggleExtrapolateContoursToLimitsRectangleButton(_ sender: Any?) {
        removePointTextAnnotation()
        if var _currentContour = self.currentContour,
           _currentContour.functionExpression == nil,
           let contourPlot = self.graph.allPlots().first(where: { $0.identifier as? String == "data" } ) as? CPTContourPlot  {
            _currentContour.extrapolateToARectangleOfLimits = !_currentContour.extrapolateToARectangleOfLimits
            self.currentContour?.extrapolateToARectangleOfLimits = _currentContour.extrapolateToARectangleOfLimits
            if let _ = self.colourCodeAnnotation {
                self.isLegendShowing = true
                self.removeColourCodeAnnotation()
            }
            showSpinner() { _ in
                self.dataBlockSources?.removeAll()
                self.searchForLimits()
                var deltaX = (self.maxX - self.minX) / 20.0
                var deltaY = (self.maxY - self.minY) / 20.0
                if !_currentContour.extrapolateToARectangleOfLimits && _currentContour.functionExpression == nil {
                    if _currentContour.krigingSurfaceInterpolation { // in order to prevent any borders make extra 25% on all 4 sides
                        deltaX = (self.maxX - self.minX) / 4.0
                        deltaY = (self.maxY - self.minY) / 4.0
                    }
                    else {
                        deltaX = (self.maxX - self.minX) / 10.0
                        deltaY = (self.maxY - self.minY) / 10.0
                    }
                }
                let minX = self.minX - deltaX
                let maxX = self.maxX + deltaX
                let minY = self.minY - deltaY
                let maxY = self.maxY + deltaY
                
                let _ = self.setupPlotSpace(self.graph, deltaX: deltaX, deltaY: deltaY)
                
                let plotDataSource = self.setupContoursDataSource(plot: contourPlot, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
                if let _plotDataSource = plotDataSource {
                    self.dataBlockSources?.append(_plotDataSource)
                }
                
                if let _dataSourceBlock = plotDataSource?.dataSourceBlock {
                    contourPlot.dataSource = self
                    contourPlot.updateDataSourceBlock(_dataSourceBlock)
                }
                contourPlot.extrapolateToLimits = _currentContour.extrapolateToARectangleOfLimits
                contourPlot.fillIsoCurves = _currentContour.fillContours
                contourPlot.reloadData()
                
                if let toggleExtrapolateToLimitsRectangleButton = sender as? UIButton {
                    if _currentContour.extrapolateToARectangleOfLimits {
                        toggleExtrapolateToLimitsRectangleButton.setImage(UIImage(systemName: "arrow.down.forward.and.arrow.up.backward"), for: .normal)
                    }
                    else {
                        toggleExtrapolateToLimitsRectangleButton.setImage(UIImage(systemName: "arrow.up.backward.and.arrow.down.forward"), for: .normal)
                    }
                }
            }
            
//            DispatchQueue.global(qos: .userInitiated).async {
//                if let _ = self.colourCodeAnnotation {
//                    self.isLegendShowing = true
//                    self.removeColourCodeAnnotation()
//                }
//                self.dataBlockSources?.removeAll()
//                self.searchForLimits()
//                var deltaX = (self.maxX - self.minX) / 20.0
//                var deltaY = (self.maxY - self.minY) / 20.0
//                if !_currentContour.extrapolateToARectangleOfLimits && _currentContour.functionExpression == nil {
//                    if _currentContour.krigingSurfaceInterpolation { // in order to prevent any borders make extra 25% on all 4 sides
//                        deltaX = (self.maxX - self.minX) / 4.0
//                        deltaY = (self.maxY - self.minY) / 4.0
//                    }
//                    else {
//                        deltaX = (self.maxX - self.minX) / 10.0
//                        deltaY = (self.maxY - self.minY) / 10.0
//                    }
//                }
//                self.minX -= deltaX
//                self.maxX += deltaX
//                self.minY -= deltaY
//                self.maxY += deltaY
//
//                let ratio = self.graph.bounds.size.width / self.graph.bounds.size.height
//                // Setup plot space
//                if let plotSpace = self.graph.defaultPlotSpace as? CPTXYPlotSpace {
//                    if ratio > 1 {
//                        plotSpace.yRange = CPTPlotRange(location: NSNumber(value: self.minY - deltaY), length:  NSNumber(value: self.maxY - self.minY + 2.0 * deltaY))
//                        let xRange = CPTMutablePlotRange(location: NSNumber(value: self.minX - deltaX), length: NSNumber(value: self.maxX - self.minX + 2.0 * deltaX))
//                        xRange.expand(byFactor: NSNumber(value: ratio))
//                        plotSpace.xRange = xRange
//                    }
//                    else {
//                        plotSpace.xRange = CPTPlotRange(location:  NSNumber(value: self.minX - deltaX), length: NSNumber(value: self.maxX - self.minX + 2.0 * deltaX))
//                        let yRange = CPTMutablePlotRange(location: NSNumber(value: self.minY - deltaY), length:  NSNumber(value: self.maxY - self.minY + 2.0 * deltaY))
//                        yRange.expand(byFactor: NSNumber(value: 1 / ratio))
//                        plotSpace.yRange = yRange
//                    }
//                }
//
//                let plotDataSource = self.setupContoursDataSource(plot: contourPlot, minX: self.minX, maxX: self.maxX, minY: self.minY, maxY: self.maxY)
//                if let _plotDataSource = plotDataSource {
//                    self.dataBlockSources?.append(_plotDataSource)
//                }
//
//                if let _dataSourceBlock = plotDataSource?.dataSourceBlock {
//                    contourPlot.dataSource = self
//                    contourPlot.updateDataSourceBlock(_dataSourceBlock)
//                }
//                contourPlot.extrapolateToLimits = _currentContour.extrapolateToARectangleOfLimits
//                contourPlot.fillIsoCurves = _currentContour.fillContours
//                contourPlot.reloadData()
//                DispatchQueue.global(qos: .background).async {
//                    DispatchQueue.main.async {
////                        if let _spinner = self.spinner {
////                            _spinner.isHidden = false
////                        }
//                        SwiftSpinner.show(self.message, animated: true)
//
//                        if let toggleExtrapolateToLimitsRectangleButton = sender as? UIButton {
//                            if _currentContour.extrapolateToARectangleOfLimits {
//                                toggleExtrapolateToLimitsRectangleButton.setImage(UIImage(systemName: "arrow.down.forward.and.arrow.up.backward"), for: .normal)
//                            }
//                            else {
//                                toggleExtrapolateToLimitsRectangleButton.setImage(UIImage(systemName: "arrow.up.backward.and.arrow.down.forward"), for: .normal)
//                            }
//                        }
//                    }
//                }
//            }
        }
    }
    
    @IBAction func chooseSurfaceInterpolationContoursMethodButton(_ sender: Any?) {
        removePointTextAnnotation()
        if let _currentContour = self.currentContour,
           _currentContour.functionExpression == nil,
           let _ = self.graph.allPlots().first as? CPTContourPlot {
            surfaceInterpolationManagerViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SurfaceInterpolationManager") as? SurfaceInterpolationManagerViewController
            
            surfaceInterpolationManagerViewController?.currentContour = _currentContour
            surfaceInterpolationManagerViewController?.delegate = self
            if let popover = surfaceInterpolationManagerViewController,
                let _sender = sender as? PopoverPresentationSourceView {
                present(popover: popover, from: _sender, size: CGSize(width: 320, height: 600), arrowDirection: .any)
            }
        }
    }
    
    @IBAction func tappedInstructionsButton(_ sender: Any?) {
        let message = "• Tap on legend to increase no isocurves.\n• Long press toggles showing legend for contours.\n• F button for changing contours.\n• M button for choosing Delaunay or Kriging interpolation for raw data.\n• ⤡ Button for toggling extrapolating to corners for raw data.\n• ⧈ Button for toggle between filling contours"
        self.presentAlert(withTitle: "Instructions", message: message)
    }
    
    
    
    // MARK: -
    // MARK: ContourManagerViewControllerDelegate methods
    
    func contourManagerViewControllerChoice(_ contourManagerViewController: ContourManagerViewController, userSelectedChoiceChanged changed: Bool, contourManagerCounter: Int) {
        self.contourManagerCounter = contourManagerCounter
        
        if let popoverPresentationController = contourManagerViewController.popoverPresentationController {
            popoverPresentationController.presentingViewController.dismiss(animated: true)
        }
        var oldContourPlot = self.graph.allPlots().first(where: { $0.identifier as? String == (self.currentContour?.functionExpression == nil ? "data" : "function") } ) as? CPTContourPlot
        currentContour = contourManagerRecords[contourManagerCounter]
        var noIsoCurves: UInt = 6
        if let _currentContour = self.currentContour,
            let _oldContourPlot = oldContourPlot {
//            SwiftSpinner.show(self.message, animated: true)
            noIsoCurves = _oldContourPlot.noIsoCurves
            if let _ = self.colourCodeAnnotation {
                self.isLegendShowing = true
                self.removeColourCodeAnnotation()
            }
            self.graph.remove(_oldContourPlot)
            self.graph.legend?.remove(_oldContourPlot)
            self.graph.allowTracking = false
            oldContourPlot = nil
            if let contourPlot = setupPlot(self.graph, noIsoCurves: noIsoCurves) {
                if let _ /*spinner*/ = self.spinner {
                    showSpinner() { _ in
                        contourPlot.fillIsoCurves = _currentContour.fillContours;
                        self.graph.add(contourPlot)
                        self.graph.legend?.add(contourPlot)
                        self.graph.allowTracking = true
                        self.setupConfigurationButtons()
                    }
//                    SwiftSpinner.show(self.message)
//                    let startFrame = CGRect(x: _spinner.bounds.midX, y: _spinner.bounds.midY, width: 0, height: 0)
//                    let endFrame = _spinner.bounds
//
//                    _spinner.frame = startFrame
//                    UIView.animate(withDuration: 1.5, delay: 0, options: .transitionFlipFromBottom) {
//                        _spinner.frame = endFrame
//                    } completion: { _ in
//                        contourPlot.fillIsoCurves = _currentContour.fillContours;
//                        self.graph.add(contourPlot)
//                        self.graph.legend?.add(contourPlot)
//                        self.setupConfigurationButtons()
//                    }
                }
                else {
                    contourPlot.fillIsoCurves = _currentContour.fillContours;
                    self.graph.add(contourPlot)
                    self.graph.legend?.add(contourPlot)
                    self.graph.allowTracking = true
                    self.setupConfigurationButtons()
                }
            }
            
        }
    }
    
    // MARK: -
    // MARK: SurfaceInterpolationManagerViewControllerDelegate methods
    
    func surfaceInterpolationManagerViewControllerChoice(_ surfaceInterpolationManagerViewController: SurfaceInterpolationManagerViewController, userSelectedChoiceChanged changed: Bool, krigingSurfaceInterpolation: Bool, krigingSurfaceModel: Int16) {
        
        if let popoverPresentationController = surfaceInterpolationManagerViewController.popoverPresentationController {
            popoverPresentationController.presentingViewController.dismiss(animated: true)
        }
        
        if let _currentContour = self.currentContour,
           _currentContour.functionExpression == nil,
           let plot = self.graph.allPlots().first as? CPTContourPlot {
            self.currentContour?.krigingSurfaceInterpolation = krigingSurfaceInterpolation
            self.currentContour?.krigingSurfaceModel = SWKrigingMode(rawValue: krigingSurfaceModel)!
            if let _ = self.colourCodeAnnotation {
                self.isLegendShowing = true
                self.removeColourCodeAnnotation()
            }
            showSpinner() { _ in
                self.dataBlockSources?.removeAll()
                self.searchForLimits()
                var deltaX = (self.maxX - self.minX) / 20.0
                var deltaY = (self.maxY - self.minY) / 20.0
                if !_currentContour.extrapolateToARectangleOfLimits && _currentContour.functionExpression == nil {
                    if _currentContour.krigingSurfaceInterpolation { // in order to prevent any borders make extra 25% on all 4 sides
                        deltaX = (self.maxX - self.minX) / 4.0
                        deltaY = (self.maxY - self.minY) / 4.0
                    }
                    else {
                        deltaX = (self.maxX - self.minX) / 10.0
                        deltaY = (self.maxY - self.minY) / 10.0
                    }
                }
                
                let minX = self.minX - deltaX
                let maxX = self.maxX + deltaX
                let minY = self.minY - deltaY
                let maxY = self.maxY + deltaY
                
                plot.limits = [NSNumber(value: minX), NSNumber(value: maxX), NSNumber(value: minY), NSNumber(value: maxY)]
                
                let _ = self.setupPlotSpace(self.graph, deltaX: deltaX, deltaY: deltaY)
                
                let plotDataSource = self.setupContoursDataSource(plot: plot, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
                if let _plotDataSource = plotDataSource {
                    self.dataBlockSources?.append(_plotDataSource)
                }
                
                if let _dataSourceBlock = plotDataSource?.dataSourceBlock {
                    plot.dataSource = self
                    plot.updateDataSourceBlock(_dataSourceBlock)
                }
                
                plot.fillIsoCurves = _currentContour.fillContours;
                plot.reloadData()
            }
        }
    }
    
    // MARK: -
    // MARK: UIPopoverPresentationControllerDelegate methods
    
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        contourManagerViewController = nil
    }
    
    // MARK: -
    // MARK: Gesture Delegates
    
//    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
//        return true
//    }
    
//    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//        return true
//    }
    
    // MARK: -
    // MARK: UILongPressGestureRecognizer
    
    @objc func toggleContourLegend(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began && gestureRecognizer.view == hostingView {
//            let tapPoint: CGPoint = gestureRecognizer.location(in: hostingView)
            if let _ = colourCodeAnnotation {
                removeColourCodeAnnotation()
            }
            else {
                if let plot = self.graph.allPlots().first as? CPTContourPlot {
                    showColourCodeAnnotation(plot)
                }
            }
        }
    }
    
    // MARK: -
    // MARK: Spinner
    
    private func showSpinner(completion: ((Bool) -> Void)?) { //@escaping(Bool) -> Void) {
        if let _spinner = self.spinner {
            _spinner.isHidden = false
            _spinner.message = self.message
//            let startFrame = CGRect(x: _spinner.bounds.midX, y: _spinner.bounds.midY, width: 0, height: 0)
            let startFrame = CGRect(x: _spinner.bounds.midX, y: _spinner.bounds.midY, width: 0, height: 0)
            let endFrame = _spinner.bounds
            _spinner.frame = startFrame
            
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveLinear, animations: {
                _spinner.frame = endFrame
            }, completion: { _ in completion?(true)
                _spinner.isHidden = true } )
        }
    }
    
    // MARK: -
    // MARK:  Hull Convex Points methods
    
    
    private func quickHullOnPlotData(plotdata: [DataStructure]?) -> [ConvexHullPoint] {
        var point: ConvexHullPoint
        var convexHullPoints: [ConvexHullPoint] = []
        if var _plotdata = plotdata {
            if _plotdata.count < 2 {
                point = ConvexHullPoint(point: CGPoint(x: _plotdata[0].x, y: _plotdata[0].y), index: 0)
                convexHullPoints.append(point)
                if _plotdata.count == 2 {
                    point = ConvexHullPoint(point: CGPoint(x: _plotdata[1].x, y: _plotdata[1].y), index: 1)
                    convexHullPoints.append(point)
                }
                return convexHullPoints
            }
            else {
                _plotdata.sort(by: { $0.x < $1.x } )
                var pts: [ConvexHullPoint] = []
                for i in 1..<_plotdata.count - 1 {
                    point = ConvexHullPoint(point: CGPoint(x: _plotdata[i].x, y: _plotdata[i].y), index: i)
                    point.point = CGPoint(x: _plotdata[i].x, y: _plotdata[i].y);
                    point.index = i
                    pts.append(point)
                }
                
                // p1 and p2 are outer most points and thus are part of the hull
                let p1: ConvexHullPoint = ConvexHullPoint(point: CGPoint(x: _plotdata[0].x, y: _plotdata[0].y), index: 0)
                // left most point
                convexHullPoints.append(p1)
                let p2: ConvexHullPoint = ConvexHullPoint(point: CGPoint(x: _plotdata[_plotdata.count - 1].x, y: _plotdata[_plotdata.count - 1].y), index: _plotdata.count - 1)
                // right most point
                convexHullPoints.append(p2)

                // points to the right of oriented line from p1 to p2
                var s1: [ConvexHullPoint] = []
                // points to the right of oriented line from p2 to p1
                var s2: [ConvexHullPoint] = []

                // p1 to p2 line
                let lineVec1 = CGPoint(x: p2.point.x - p1.point.x, y: p2.point.y - p1.point.y)
                var pVec1: CGPoint
                var sign1: CGFloat
                for i in 0..<pts.count {
                    point = pts[i]
                    pVec1 = CGPoint(x: point.point.x - p1.point.x, y: point.point.y - p1.point.y)
                    sign1 = lineVec1.x * pVec1.y - pVec1.x * lineVec1.y // cross product to check on which side of the line point p is.
                    if sign1 > 0  { // right of p1 p2 line (in a normal xy coordinate system this would be < 0 but due to the weird iPhone screen coordinates this is > 0
                        s1.append(point)
                    }
                    else { // right of p2 p1 line
                        s2.append(point)
                    }
                }
                // find new hull points
                findHull(points: s1, p1: p1, p2: p2, convexHullPoints: &convexHullPoints)
                findHull(points: s2, p1: p2, p2: p1, convexHullPoints: &convexHullPoints)
            }
        }
        return convexHullPoints
    }

    
    private func findHull(points: [ConvexHullPoint], p1: ConvexHullPoint, p2: ConvexHullPoint, convexHullPoints: inout [ConvexHullPoint]) -> Void {
        
        // if set of points is empty there are no points to the right of this line so this line is part of the hull.
        if points.isEmpty {
            return
        }
        
        var pts = points
        if var maxPoint: ConvexHullPoint = pts.first {
            var maxDist: CGFloat = -1
            for p in pts { // for every point check the distance from our line
                let dist = distance(from: p, to: (p1, p2))
                if dist > maxDist { // if distance is larger than current maxDist remember new point p
                    maxDist = dist
                    maxPoint = p
                }
            }
            // insert point with max distance from line in the convexHull after p1
            if let index = convexHullPoints.firstIndex(of: p1) {
                convexHullPoints.insert(maxPoint, at: index + 1)
            }
            // remove maxPoint from points array as we are going to split this array in points left and right of the line
            if let index = pts.firstIndex(of: maxPoint) {
                pts.remove(at: index)
            }
            
            // points to the right of oriented line from p1 to p2
            var s1 = [ConvexHullPoint]()

            // points to the right of oriented line from p2 to p1
            var s2 = [ConvexHullPoint]()

            // p1 to maxPoint line
            let lineVec1 = CGPoint(x: maxPoint.point.x - p1.point.x, y: maxPoint.point.y - p1.point.y)
            // maxPoint to p2 line
            let lineVec2 = CGPoint(x: p2.point.x - maxPoint.point.x, y: p2.point.y - maxPoint.point.y)

            for p in pts { // per point check if point is to right or left of p1 to p2 line
                let pVec1 = CGPoint(x: p.point.x - p1.point.x, y: p.point.y - p1.point.y)
                let sign1 = lineVec1.x * pVec1.y - pVec1.x * lineVec1.y // cross product to check on which side of the line point p is.
                let pVec2 = CGPoint(x: p.point.x - maxPoint.point.x, y: p.point.y - maxPoint.point.y) // vector from p2 to p
                let sign2 = lineVec2.x * pVec2.y - pVec2.x * lineVec2.y // sign to check is p is to the right or left of lineVec2

                if sign1 > 0 { // right of p1 p2 line (in a normal xy coordinate system this would be < 0 but due to the weird iPhone screen coordinates this is > 0
                    s1.append(p)
                }
                else if sign2 > 0 { // right of p2 p1 line
                    s2.append(p)
                }
            }
            
            // find new hull points
            findHull(points: s1, p1: p1, p2: maxPoint, convexHullPoints: &convexHullPoints)
            findHull(points: s2, p1: maxPoint, p2: p2, convexHullPoints: &convexHullPoints)
        }
    }
    
    private func distance(from p: ConvexHullPoint, to line: (ConvexHullPoint, ConvexHullPoint)) -> CGFloat {
      // If line.0 and line.1 are the same point, they don't define a line (and, besides,
      // would cause division by zero in the distance formula). Return the distance between
      // line.0 and point p instead.
        if __CGPointEqualToPoint(line.0.point, line.1.point) {
            return sqrt(pow(p.point.x - line.0.point.x, 2) + pow(p.point.y - line.0.point.y, 2))
      }

      // from Deza, Michel Marie; Deza, Elena (2013), Encyclopedia of Distances (2nd ed.), Springer, p. 86, ISBN 9783642309588
        return abs((line.1.point.y - line.0.point.y) * p.point.x
        - (line.1.point.x - line.0.point.x) * p.point.y
        + line.1.point.x * line.0.point.y
        - line.1.point.y * line.0.point.x)
        / sqrt(pow(line.1.point.y - line.0.point.y, 2) + pow(line.1.point.x - line.0.point.x, 2))
    }

    
    private let data = [DataStructure(x: 57.333333, y: 206.207746, z: 0.0),
                                   DataStructure(x: 75.250000, y: 206.207746, z: 0.0),
                                   DataStructure(x: 93.166667, y: 206.207746, z: 0.0),
                                   DataStructure(x: 111.083333, y: 206.207746, z: 0.0),
                                   DataStructure(x: 129.000000, y: 206.207746, z: 0.0),
                                   DataStructure(x: 146.916667, y: 206.207746, z: 0.0),
                                   DataStructure(x: 164.833333, y: 206.207746, z: 0.0),
                                   DataStructure(x: 182.750000, y: 206.207746, z: 0.0),
                                   DataStructure(x: 200.666667, y: 206.207746, z: 0.0),
                                   DataStructure(x: 218.583333, y: 206.207746, z: 0.0),
                                   DataStructure(x: 236.500000, y: 206.207746, z: 0.0),
                                   DataStructure(x: 254.416667, y: 206.207746, z: 0.0),
                                   DataStructure(x: 272.333333, y: 206.207746, z: 0.0),
                                   DataStructure(x: 290.250000, y: 206.207746, z: 0.0),
                                   DataStructure(x: 57.333333, y: 223.444762, z: 0.0),
                                   DataStructure(x: 75.250000, y: 223.444762, z: 0.0),
                                   DataStructure(x: 93.166667, y: 223.444762, z: 0.0),
                                   DataStructure(x: 111.083333, y: 223.444762, z: 0.0),
                                   DataStructure(x: 129.000000, y: 223.444762, z: 0.0),
                                   DataStructure(x: 146.916667, y: 223.444762, z: 0.0),
                                   DataStructure(x: 164.833333, y: 223.444762, z: 0.0),
                                   DataStructure(x: 182.750000, y: 223.444762, z: 0.0),
                                   DataStructure(x: 200.666667, y: 223.444762, z: 0.0),
                                   DataStructure(x: 218.583333, y: 223.444762, z: 0.0),
                                   DataStructure(x: 236.500000, y: 223.444762, z: 0.0),
                                   DataStructure(x: 254.416667, y: 223.444762, z: 0.0),
                                   DataStructure(x: 272.333333, y: 223.444762, z: 0.0),
                                   DataStructure(x: 290.250000, y: 223.444762, z: 0.0),
                                   DataStructure(x: 57.333333, y: 240.681778, z: 0.0),
                                   DataStructure(x: 75.250000, y: 240.681778, z: 0.0),
                                   DataStructure(x: 93.166667, y: 240.681778, z: 0.0),
                                   DataStructure(x: 111.083333, y: 240.681778, z: 0.0),
                                   DataStructure(x: 129.000000, y: 240.681778, z: 0.0),
                                   DataStructure(x: 146.916667, y: 240.681778, z: 0.0),
                                   DataStructure(x: 164.833333, y: 240.681778, z: 0.0),
                                   DataStructure(x: 182.750000, y: 240.681778, z: 0.0),
                                   DataStructure(x: 200.666667, y: 240.681778, z: 0.0),
                                   DataStructure(x: 218.583333, y: 240.681778, z: 0.0),
                                   DataStructure(x: 236.500000, y: 240.681778, z: 0.0),
                                   DataStructure(x: 254.416667, y: 240.681778, z: 0.0),
                                   DataStructure(x: 272.333333, y: 240.681778, z: 0.0),
                                   DataStructure(x: 290.250000, y: 240.681778, z: 0.0),
                                   DataStructure(x: 57.333333, y: 257.918794, z: 0.0),
                                   DataStructure(x: 75.250000, y: 257.918794, z: 0.0),
                                   DataStructure(x: 93.166667, y: 257.918794, z: 0.0),
                                   DataStructure(x: 111.083333, y: 257.918794, z: 0.0),
                                   DataStructure(x: 129.000000, y: 257.918794, z: 0.0),
                                   DataStructure(x: 146.916667, y: 257.918794, z: 0.0),
                                   DataStructure(x: 164.833333, y: 257.918794, z: 0.0),
                                   DataStructure(x: 182.750000, y: 257.918794, z: 0.0),
                                   DataStructure(x: 200.666667, y: 257.918794, z: 0.0),
                                   DataStructure(x: 218.583333, y: 257.918794, z: 0.0),
                                   DataStructure(x: 236.500000, y: 257.918794, z: 0.0),
                                   DataStructure(x: 254.416667, y: 257.918794, z: 0.0),
                                   DataStructure(x: 272.333333, y: 257.918794, z: 0.0),
                                   DataStructure(x: 290.250000, y: 257.918794, z: 0.0),
                                   DataStructure(x: 308.166667, y: 257.918794, z: 0.0),
                                   DataStructure(x: 57.333333, y: 275.155810, z: 0.0),
                                   DataStructure(x: 75.250000, y: 275.155810, z: 0.0),
                                   DataStructure(x: 93.166667, y: 275.155810, z: 0.0),
                                   DataStructure(x: 111.083333, y: 275.155810, z: 0.0),
                                   DataStructure(x: 129.000000, y: 275.155810, z: 0.0),
                                   DataStructure(x: 146.916667, y: 275.155810, z: 0.0),
                                   DataStructure(x: 164.833333, y: 275.155810, z: 0.0),
                                   DataStructure(x: 182.750000, y: 275.155810, z: 0.0),
                                   DataStructure(x: 200.666667, y: 275.155810, z: 0.0),
                                   DataStructure(x: 218.583333, y: 275.155810, z: 0.0),
                                   DataStructure(x: 236.500000, y: 275.155810, z: 0.0),
                                   DataStructure(x: 254.416667, y: 275.155810, z: 0.0),
                                   DataStructure(x: 272.333333, y: 275.155810, z: 0.0),
                                   DataStructure(x: 290.250000, y: 275.155810, z: 0.0),
                                   DataStructure(x: 308.166667, y: 275.155810, z: 0.0),
                                   DataStructure(x: 57.333333, y: 292.392826, z: 0.0),
                                   DataStructure(x: 75.250000, y: 292.392826, z: 0.0),
                                   DataStructure(x: 93.166667, y: 292.392826, z: 0.0),
                                   DataStructure(x: 111.083333, y: 292.392826, z: 0.0),
                                   DataStructure(x: 129.000000, y: 292.392826, z: 0.0),
                                   DataStructure(x: 146.916667, y: 292.392826, z: 0.0),
                                   DataStructure(x: 164.833333, y: 292.392826, z: 0.0),
                                   DataStructure(x: 182.750000, y: 292.392826, z: 0.0),
                                   DataStructure(x: 200.666667, y: 292.392826, z: 0.0),
                                   DataStructure(x: 218.583333, y: 292.392826, z: 0.0),
                                   DataStructure(x: 236.500000, y: 292.392826, z: 0.0),
                                   DataStructure(x: 254.416667, y: 292.392826, z: 0.0),
                                   DataStructure(x: 272.333333, y: 292.392826, z: 0.0),
                                   DataStructure(x: 290.250000, y: 292.392826, z: 0.0),
                                   DataStructure(x: 308.166667, y: 292.392826, z: 0.0),
                                   DataStructure(x: 57.333333, y: 309.629842, z: 0.0),
                                   DataStructure(x: 75.250000, y: 309.629842, z: 0.0),
                                   DataStructure(x: 93.166667, y: 309.629842, z: 0.0),
                                   DataStructure(x: 111.083333, y: 309.629842, z: 0.0),
                                   DataStructure(x: 129.000000, y: 309.629842, z: 0.0),
                                   DataStructure(x: 146.916667, y: 309.629842, z: 0.0),
                                   DataStructure(x: 164.833333, y: 309.629842, z: 0.0),
                                   DataStructure(x: 182.750000, y: 309.629842, z: 0.0),
                                   DataStructure(x: 200.666667, y: 309.629842, z: 0.0),
                                   DataStructure(x: 218.583333, y: 309.629842, z: 0.0),
                                   DataStructure(x: 236.500000, y: 309.629842, z: 0.0),
                                   DataStructure(x: 254.416667, y: 309.629842, z: 0.0),
                                   DataStructure(x: 272.333333, y: 309.629842, z: 0.0),
                                   DataStructure(x: 290.250000, y: 309.629842, z: 0.0),
                                   DataStructure(x: 308.166667, y: 309.629842, z: 0.0),
                                   DataStructure(x: 57.333333, y: 326.866857, z: 0.0),
                                   DataStructure(x: 75.250000, y: 326.866857, z: 0.0),
                                   DataStructure(x: 93.166667, y: 326.866857, z: 0.0),
                                   DataStructure(x: 111.083333, y: 326.866857, z: 0.0),
                                   DataStructure(x: 129.000000, y: 326.866857, z: 0.0),
                                   DataStructure(x: 146.916667, y: 326.866857, z: 0.0),
                                   DataStructure(x: 164.833333, y: 326.866857, z: 0.0),
                                   DataStructure(x: 182.750000, y: 326.866857, z: 0.0),
                                   DataStructure(x: 200.666667, y: 326.866857, z: 0.0),
                                   DataStructure(x: 218.583333, y: 326.866857, z: 0.0),
                                   DataStructure(x: 236.500000, y: 326.866857, z: 0.0),
                                   DataStructure(x: 254.416667, y: 326.866857, z: 0.0),
                                   DataStructure(x: 272.333333, y: 326.866857, z: 0.0),
                                   DataStructure(x: 290.250000, y: 326.866857, z: 0.0),
                                   DataStructure(x: 308.166667, y: 326.866857, z: 0.0),
                                   DataStructure(x: 57.333333, y: 344.103873, z: 0.0),
                                   DataStructure(x: 75.250000, y: 344.103873, z: 0.0),
                                   DataStructure(x: 93.166667, y: 344.103873, z: 0.0),
                                   DataStructure(x: 111.083333, y: 344.103873, z: 0.0),
                                   DataStructure(x: 129.000000, y: 344.103873, z: 0.0),
                                   DataStructure(x: 146.916667, y: 344.103873, z: 0.0),
                                   DataStructure(x: 164.833333, y: 344.103873, z: 0.0),
                                   DataStructure(x: 182.750000, y: 344.103873, z: 0.0),
                                   DataStructure(x: 200.666667, y: 344.103873, z: 0.0),
                                   DataStructure(x: 218.583333, y: 344.103873, z: 0.0),
                                   DataStructure(x: 236.500000, y: 344.103873, z: 0.0),
                                   DataStructure(x: 254.416667, y: 344.103873, z: 0.0),
                                   DataStructure(x: 290.250000, y: 344.103873, z: 0.0),
                                   DataStructure(x: 308.166667, y: 344.103873, z: 0.0),
                                   DataStructure(x: 57.333333, y: 361.340889, z: 0.0),
                                   DataStructure(x: 75.250000, y: 361.340889, z: 0.0),
                                   DataStructure(x: 93.166667, y: 361.340889, z: 0.0),
                                   DataStructure(x: 111.083333, y: 361.340889, z: 0.0),
                                   DataStructure(x: 129.000000, y: 361.340889, z: 0.0),
                                   DataStructure(x: 146.916667, y: 361.340889, z: 0.0),
                                   DataStructure(x: 164.833333, y: 361.340889, z: 0.0),
                                   DataStructure(x: 182.750000, y: 361.340889, z: 0.0),
                                   DataStructure(x: 200.666667, y: 361.340889, z: 0.0),
                                   DataStructure(x: 218.583333, y: 361.340889, z: 0.0),
                                   DataStructure(x: 236.500000, y: 361.340889, z: 0.0),
                                   DataStructure(x: 254.416667, y: 361.340889, z: 0.0),
                                   DataStructure(x: 272.333333, y: 361.340889, z: 0.0),
                                   DataStructure(x: 290.250000, y: 361.340889, z: 0.0),
                                   DataStructure(x: 308.166667, y: 361.340889, z: 0.0),
                                   DataStructure(x: 57.333333, y: 378.577905, z: 0.0),
                                   DataStructure(x: 75.250000, y: 378.577905, z: 0.0),
                                   DataStructure(x: 93.166667, y: 378.577905, z: 0.0),
                                   DataStructure(x: 111.083333, y: 378.577905, z: 0.0),
                                   DataStructure(x: 129.000000, y: 378.577905, z: 0.0),
                                   DataStructure(x: 146.916667, y: 378.577905, z: 0.0),
                                   DataStructure(x: 164.833333, y: 378.577905, z: 0.0),
                                   DataStructure(x: 182.750000, y: 378.577905, z: 0.0),
                                   DataStructure(x: 200.666667, y: 378.577905, z: 0.0),
                                   DataStructure(x: 218.583333, y: 378.577905, z: 0.0),
                                   DataStructure(x: 236.500000, y: 378.577905, z: 0.0),
                                   DataStructure(x: 254.416667, y: 378.577905, z: 0.0),
                                   DataStructure(x: 272.333333, y: 378.577905, z: 0.0),
                                   DataStructure(x: 290.250000, y: 378.577905, z: 0.0),
                                   DataStructure(x: 308.166667, y: 378.577905, z: 0.0),
                                   DataStructure(x: 326.083333, y: 378.577905, z: 0.0),
                                   DataStructure(x: 57.333333, y: 395.814921, z: 0.0),
                                   DataStructure(x: 75.250000, y: 395.814921, z: 0.0),
                                   DataStructure(x: 93.166667, y: 395.814921, z: 0.0),
                                   DataStructure(x: 111.083333, y: 395.814921, z: 0.0),
                                   DataStructure(x: 129.000000, y: 395.814921, z: 0.0),
                                   DataStructure(x: 146.916667, y: 395.814921, z: 0.0),
                                   DataStructure(x: 164.833333, y: 395.814921, z: 0.0),
                                   DataStructure(x: 182.750000, y: 395.814921, z: 0.0),
                                   DataStructure(x: 200.666667, y: 395.814921, z: 0.0),
                                   DataStructure(x: 218.583333, y: 395.814921, z: 0.0),
                                   DataStructure(x: 236.500000, y: 395.814921, z: 0.0),
                                   DataStructure(x: 254.416667, y: 395.814921, z: 0.0),
                                   DataStructure(x: 272.333333, y: 395.814921, z: 0.0),
                                   DataStructure(x: 290.250000, y: 395.814921, z: 0.0),
                                   DataStructure(x: 308.166667, y: 395.814921, z: 0.0),
                                   DataStructure(x: 326.083333, y: 395.814921, z: 0.0),
                                   DataStructure(x: 344.000000, y: 395.814921, z: 0.0),
                                   DataStructure(x: 57.333333, y: 413.051937, z: 0.0),
                                   DataStructure(x: 75.250000, y: 413.051937, z: 0.0),
                                   DataStructure(x: 93.166667, y: 413.051937, z: 0.0),
                                   DataStructure(x: 111.083333, y: 413.051937, z: 0.0),
                                   DataStructure(x: 129.000000, y: 413.051937, z: 0.0),
                                   DataStructure(x: 146.916667, y: 413.051937, z: 0.0),
                                   DataStructure(x: 164.833333, y: 413.051937, z: 0.0),
                                   DataStructure(x: 182.750000, y: 413.051937, z: 0.0),
                                   DataStructure(x: 218.583333, y: 413.051937, z: 0.0),
                                   DataStructure(x: 236.500000, y: 413.051937, z: 0.0),
                                   DataStructure(x: 254.416667, y: 413.051937, z: 0.0),
                                   DataStructure(x: 272.333333, y: 413.051937, z: 0.0),
                                   DataStructure(x: 290.250000, y: 413.051937, z: 0.0),
                                   DataStructure(x: 308.166667, y: 413.051937, z: 0.0),
                                   DataStructure(x: 326.083333, y: 413.051937, z: 0.0),
                                   DataStructure(x: 344.000000, y: 413.051937, z: 0.0),
                                   DataStructure(x: 361.916667, y: 413.051937, z: 0.0),
                                   DataStructure(x: 379.833333, y: 413.051937, z: 0.0),
                                   DataStructure(x: 57.333333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 75.250000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 93.166667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 111.083333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 129.000000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 146.916667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 164.833333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 182.750000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 200.666667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 218.583333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 236.500000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 254.416667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 272.333333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 290.250000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 308.166667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 326.083333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 344.000000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 361.916667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 379.833333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 397.750000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 415.666667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 433.583333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 451.500000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 469.416667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 487.333333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 505.250000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 523.166667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 541.083333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 559.000000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 576.916667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 594.833333, y: 430.288952, z: 0.0),
                                   DataStructure(x: 612.750000, y: 430.288952, z: 0.0),
                                   DataStructure(x: 630.666667, y: 430.288952, z: 0.0),
                                   DataStructure(x: 111.083333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 129.000000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 146.916667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 164.833333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 182.750000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 200.666667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 218.583333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 236.500000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 254.416667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 272.333333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 290.250000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 308.166667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 326.083333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 344.000000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 361.916667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 379.833333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 397.750000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 415.666667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 433.583333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 451.500000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 469.416667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 505.250000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 523.166667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 541.083333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 559.000000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 576.916667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 594.833333, y: 447.525968, z: 0.0),
                                   DataStructure(x: 612.750000, y: 447.525968, z: 0.0),
                                   DataStructure(x: 630.666667, y: 447.525968, z: 0.0),
                                   DataStructure(x: 236.500000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 254.416667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 272.333333, y: 464.762984, z: 0.0),
                                   DataStructure(x: 290.250000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 308.166667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 326.083333, y: 464.762984, z: 0.0),
                                   DataStructure(x: 344.000000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 361.916667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 379.833333, y: 464.762984, z: 0.0),
                                   DataStructure(x: 397.750000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 415.666667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 433.583333, y: 464.762984, z: 0.0),
                                   DataStructure(x: 451.500000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 469.416667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 487.333333, y: 464.762984, z: 0.0),
                                   DataStructure(x: 505.250000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 523.166667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 541.083333, y: 464.762984, z: 0.0),
                                   DataStructure(x: 559.000000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 576.916667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 594.833333, y: 464.762984, z: 0.0),
                                   DataStructure(x: 612.750000, y: 464.762984, z: 0.0),
                                   DataStructure(x: 630.666667, y: 464.762984, z: 0.0),
                                   DataStructure(x: 254.416667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 272.333333, y: 482.000000, z: 0.0),
                                   DataStructure(x: 290.250000, y: 482.000000, z: 0.0),
                                   DataStructure(x: 308.166667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 326.083333, y: 482.000000, z: 0.0),
                                   DataStructure(x: 361.916667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 379.833333, y: 482.000000, z: 0.0),
                                   DataStructure(x: 397.750000, y: 482.000000, z: 0.0),
                                   DataStructure(x: 415.666667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 433.583333, y: 482.000000, z: 0.0),
                                   DataStructure(x: 451.500000, y: 482.000000, z: 0.0),
                                   DataStructure(x: 469.416667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 487.333333, y: 482.000000, z: 0.0),
                                   DataStructure(x: 505.250000, y: 482.000000, z: 0.0),
                                   DataStructure(x: 523.166667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 541.083333, y: 482.000000, z: 0.0),
                                   DataStructure(x: 559.000000, y: 482.000000, z: 0.0),
                                   DataStructure(x: 576.916667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 594.833333, y: 482.000000, z: 0.0),
                                   DataStructure(x: 612.750000, y: 482.000000, z: 0.0),
                                   DataStructure(x: 630.666667, y: 482.000000, z: 0.0),
                                   DataStructure(x: 272.333333, y: 499.237016, z: 0.0),
                                   DataStructure(x: 290.250000, y: 499.237016, z: 0.0),
                                   DataStructure(x: 308.166667, y: 499.237016, z: 0.0),
                                   DataStructure(x: 326.083333, y: 499.237016, z: 0.0),
                                   DataStructure(x: 344.000000, y: 499.237016, z: 0.0),
                                   DataStructure(x: 361.916667, y: 499.237016, z: 0.0),
                                   DataStructure(x: 379.833333, y: 499.237016, z: 0.0),
                                   DataStructure(x: 397.750000, y: 499.237016, z: 0.0),
                                   DataStructure(x: 415.666667, y: 499.237016, z: 0.0),
                                   DataStructure(x: 433.583333, y: 499.237016, z: 0.0),
                                   DataStructure(x: 451.500000, y: 499.237016, z: 0.0),
                                   DataStructure(x: 469.416667, y: 499.237016, z: 0.0),
                                   DataStructure(x: 487.333333, y: 499.237016, z: 0.0),
                                   DataStructure(x: 505.250000, y: 499.237016, z: 0.0),
                                   DataStructure(x: 523.166667, y: 499.237016, z: 0.0),
                                   DataStructure(x: 541.083333, y: 499.237016, z: 0.0),
                                   DataStructure(x: 559.000000, y: 499.237016, z: 0.0),
                                   DataStructure(x: 576.916667, y: 499.237016, z: 0.0),
                                   DataStructure(x: 594.833333, y: 499.237016, z: 0.0),
                                   DataStructure(x: 612.750000, y: 499.237016, z: 0.0),
                                   DataStructure(x: 630.666667, y: 499.237016, z: 0.0),
                                   DataStructure(x: 272.333333, y: 516.474032, z: 0.0),
                                   DataStructure(x: 290.250000, y: 516.474032, z: 0.0),
                                   DataStructure(x: 308.166667, y: 516.474032, z: 0.0),
                                   DataStructure(x: 326.083333, y: 516.474032, z: 0.0),
                                   DataStructure(x: 344.000000, y: 516.474032, z: 0.0),
                                   DataStructure(x: 361.916667, y: 516.474032, z: 0.0),
                                   DataStructure(x: 379.833333, y: 516.474032, z: 0.0),
                                   DataStructure(x: 397.750000, y: 516.474032, z: 0.0),
                                   DataStructure(x: 415.666667, y: 516.474032, z: 0.0),
                                   DataStructure(x: 433.583333, y: 516.474032, z: 0.0),
                                   DataStructure(x: 451.500000, y: 516.474032, z: 0.0),
                                   DataStructure(x: 469.416667, y: 516.474032, z: 0.0),
                                   DataStructure(x: 487.333333, y: 516.474032, z: 0.0),
                                   DataStructure(x: 505.250000, y: 516.474032, z: 0.0),
                                   DataStructure(x: 523.166667, y: 516.474032, z: 0.0),
                                   DataStructure(x: 541.083333, y: 516.474032, z: 0.0),
                                   DataStructure(x: 559.000000, y: 516.474032, z: 0.0),
                                   DataStructure(x: 576.916667, y: 516.474032, z: 0.0),
                                   DataStructure(x: 594.833333, y: 516.474032, z: 0.0),
                                   DataStructure(x: 612.750000, y: 516.474032, z: 0.0),
                                   DataStructure(x: 630.666667, y: 516.474032, z: 0.0),
                                   DataStructure(x: 290.250000, y: 533.711048, z: 0.0),
                                   DataStructure(x: 308.166667, y: 533.711048, z: 0.0),
                                   DataStructure(x: 326.083333, y: 533.711048, z: 0.0),
                                   DataStructure(x: 344.000000, y: 533.711048, z: 0.0),
                                   DataStructure(x: 361.916667, y: 533.711048, z: 0.0),
                                   DataStructure(x: 379.833333, y: 533.711048, z: 0.0),
                                   DataStructure(x: 397.750000, y: 533.711048, z: 0.0),
                                   DataStructure(x: 415.666667, y: 533.711048, z: 0.0),
                                   DataStructure(x: 433.583333, y: 533.711048, z: 0.0),
                                   DataStructure(x: 451.500000, y: 533.711048, z: 0.0),
                                   DataStructure(x: 469.416667, y: 533.711048, z: 0.0),
                                   DataStructure(x: 487.333333, y: 533.711048, z: 0.0),
                                   DataStructure(x: 505.250000, y: 533.711048, z: 0.0),
                                   DataStructure(x: 523.166667, y: 533.711048, z: 0.0),
                                   DataStructure(x: 541.083333, y: 533.711048, z: 0.0),
                                   DataStructure(x: 559.000000, y: 533.711048, z: 0.0),
                                   DataStructure(x: 576.916667, y: 533.711048, z: 0.0),
                                   DataStructure(x: 594.833333, y: 533.711048, z: 0.0),
                                   DataStructure(x: 612.750000, y: 533.711048, z: 0.0),
                                   DataStructure(x: 630.666667, y: 533.711048, z: 0.0),
                                   DataStructure(x: 290.250000, y: 550.948063, z: 0.0),
                                   DataStructure(x: 308.166667, y: 550.948063, z: 0.0),
                                   DataStructure(x: 326.083333, y: 550.948063, z: 0.0),
                                   DataStructure(x: 344.000000, y: 550.948063, z: 0.0),
                                   DataStructure(x: 361.916667, y: 550.948063, z: 0.0),
                                   DataStructure(x: 379.833333, y: 550.948063, z: 0.0),
                                   DataStructure(x: 397.750000, y: 550.948063, z: 0.0),
                                   DataStructure(x: 415.666667, y: 550.948063, z: 0.0),
                                   DataStructure(x: 433.583333, y: 550.948063, z: 0.0),
                                   DataStructure(x: 451.500000, y: 550.948063, z: 0.0),
                                   DataStructure(x: 469.416667, y: 550.948063, z: 0.0),
                                   DataStructure(x: 487.333333, y: 550.948063, z: 0.0),
                                   DataStructure(x: 505.250000, y: 550.948063, z: 0.0),
                                   DataStructure(x: 523.166667, y: 550.948063, z: 0.0),
                                   DataStructure(x: 541.083333, y: 550.948063, z: 0.0),
                                   DataStructure(x: 559.000000, y: 550.948063, z: 0.0),
                                   DataStructure(x: 576.916667, y: 550.948063, z: 0.0),
                                   DataStructure(x: 594.833333, y: 550.948063, z: 0.0),
                                   DataStructure(x: 612.750000, y: 550.948063, z: 0.0),
                                   DataStructure(x: 630.666667, y: 550.948063, z: 0.0),
                                   DataStructure(x: 290.250000, y: 568.185079, z: 0.0),
                                   DataStructure(x: 308.166667, y: 568.185079, z: 0.0),
                                   DataStructure(x: 326.083333, y: 568.185079, z: 0.0),
                                   DataStructure(x: 344.000000, y: 568.185079, z: 0.0),
                                   DataStructure(x: 361.916667, y: 568.185079, z: 0.0),
                                   DataStructure(x: 379.833333, y: 568.185079, z: 0.0),
                                   DataStructure(x: 397.750000, y: 568.185079, z: 0.0),
                                   DataStructure(x: 415.666667, y: 568.185079, z: 0.0),
                                   DataStructure(x: 433.583333, y: 568.185079, z: 0.0),
                                   DataStructure(x: 451.500000, y: 568.185079, z: 0.0),
                                   DataStructure(x: 469.416667, y: 568.185079, z: 0.0),
                                   DataStructure(x: 487.333333, y: 568.185079, z: 0.0),
                                   DataStructure(x: 505.250000, y: 568.185079, z: 0.0),
                                   DataStructure(x: 523.166667, y: 568.185079, z: 0.0),
                                   DataStructure(x: 541.083333, y: 568.185079, z: 0.0),
                                   DataStructure(x: 559.000000, y: 568.185079, z: 0.0),
                                   DataStructure(x: 576.916667, y: 568.185079, z: 0.0),
                                   DataStructure(x: 594.833333, y: 568.185079, z: 0.0),
                                   DataStructure(x: 612.750000, y: 568.185079, z: 0.0),
                                   DataStructure(x: 630.666667, y: 568.185079, z: 0.0),
                                   DataStructure(x: 290.250000, y: 585.422095, z: 0.0),
                                   DataStructure(x: 308.166667, y: 585.422095, z: 0.0),
                                   DataStructure(x: 326.083333, y: 585.422095, z: 0.0),
                                   DataStructure(x: 344.000000, y: 585.422095, z: 0.0),
                                   DataStructure(x: 361.916667, y: 585.422095, z: 0.0),
                                   DataStructure(x: 379.833333, y: 585.422095, z: 0.0),
                                   DataStructure(x: 397.750000, y: 585.422095, z: 0.0),
                                   DataStructure(x: 415.666667, y: 585.422095, z: 0.0),
                                   DataStructure(x: 433.583333, y: 585.422095, z: 0.0),
                                   DataStructure(x: 451.500000, y: 585.422095, z: 0.0),
                                   DataStructure(x: 469.416667, y: 585.422095, z: 0.0),
                                   DataStructure(x: 487.333333, y: 585.422095, z: 0.0),
                                   DataStructure(x: 505.250000, y: 585.422095, z: 0.0),
                                   DataStructure(x: 523.166667, y: 585.422095, z: 0.0),
                                   DataStructure(x: 541.083333, y: 585.422095, z: 0.0),
                                   DataStructure(x: 559.000000, y: 585.422095, z: 0.0),
                                   DataStructure(x: 576.916667, y: 585.422095, z: 0.0),
                                   DataStructure(x: 594.833333, y: 585.422095, z: 0.0),
                                   DataStructure(x: 612.750000, y: 585.422095, z: 0.0),
                                   DataStructure(x: 630.666667, y: 585.422095, z: 0.0),
                                   DataStructure(x: 290.250000, y: 602.659111, z: 0.0),
                                   DataStructure(x: 308.166667, y: 602.659111, z: 0.0),
                                   DataStructure(x: 326.083333, y: 602.659111, z: 0.0),
                                   DataStructure(x: 344.000000, y: 602.659111, z: 0.0),
                                   DataStructure(x: 361.916667, y: 602.659111, z: 0.0),
                                   DataStructure(x: 379.833333, y: 602.659111, z: 0.0),
                                   DataStructure(x: 397.750000, y: 602.659111, z: 0.0),
                                   DataStructure(x: 415.666667, y: 602.659111, z: 0.0),
                                   DataStructure(x: 433.583333, y: 602.659111, z: 0.0),
                                   DataStructure(x: 451.500000, y: 602.659111, z: 0.0),
                                   DataStructure(x: 469.416667, y: 602.659111, z: 0.0),
                                   DataStructure(x: 487.333333, y: 602.659111, z: 0.0),
                                   DataStructure(x: 505.250000, y: 602.659111, z: 0.0),
                                   DataStructure(x: 523.166667, y: 602.659111, z: 0.0),
                                   DataStructure(x: 541.083333, y: 602.659111, z: 0.0),
                                   DataStructure(x: 559.000000, y: 602.659111, z: 0.0),
                                   DataStructure(x: 576.916667, y: 602.659111, z: 0.0),
                                   DataStructure(x: 594.833333, y: 602.659111, z: 0.0),
                                   DataStructure(x: 612.750000, y: 602.659111, z: 0.0),
                                   DataStructure(x: 630.666667, y: 602.659111, z: 0.0),
                                   DataStructure(x: 290.250000, y: 619.896127, z: 0.0),
                                   DataStructure(x: 326.083333, y: 619.896127, z: 0.0),
                                   DataStructure(x: 344.000000, y: 619.896127, z: 0.0),
                                   DataStructure(x: 361.916667, y: 619.896127, z: 0.0),
                                   DataStructure(x: 379.833333, y: 619.896127, z: 0.0),
                                   DataStructure(x: 397.750000, y: 619.896127, z: 0.0),
                                   DataStructure(x: 415.666667, y: 619.896127, z: 0.0),
                                   DataStructure(x: 433.583333, y: 619.896127, z: 0.0),
                                   DataStructure(x: 451.500000, y: 619.896127, z: 0.0),
                                   DataStructure(x: 469.416667, y: 619.896127, z: 0.0),
                                   DataStructure(x: 487.333333, y: 619.896127, z: 0.0),
                                   DataStructure(x: 505.250000, y: 619.896127, z: 0.0),
                                   DataStructure(x: 523.166667, y: 619.896127, z: 0.0),
                                   DataStructure(x: 541.083333, y: 619.896127, z: 0.0),
                                   DataStructure(x: 559.000000, y: 619.896127, z: 0.0),
                                   DataStructure(x: 576.916667, y: 619.896127, z: 0.0),
                                   DataStructure(x: 594.833333, y: 619.896127, z: 0.0),
                                   DataStructure(x: 612.750000, y: 619.896127, z: 0.0),
                                   DataStructure(x: 630.666667, y: 619.896127, z: 0.0),
                                   DataStructure(x: 290.250000, y: 637.133143, z: 0.0),
                                   DataStructure(x: 308.166667, y: 637.133143, z: 0.0),
                                   DataStructure(x: 326.083333, y: 637.133143, z: 0.0),
                                   DataStructure(x: 344.000000, y: 637.133143, z: 0.0),
                                   DataStructure(x: 361.916667, y: 637.133143, z: 0.0),
                                   DataStructure(x: 379.833333, y: 637.133143, z: 0.0),
                                   DataStructure(x: 397.750000, y: 637.133143, z: 0.0),
                                   DataStructure(x: 415.666667, y: 637.133143, z: 0.0),
                                   DataStructure(x: 433.583333, y: 637.133143, z: 0.0),
                                   DataStructure(x: 451.500000, y: 637.133143, z: 0.0),
                                   DataStructure(x: 469.416667, y: 637.133143, z: 0.0),
                                   DataStructure(x: 487.333333, y: 637.133143, z: 0.0),
                                   DataStructure(x: 505.250000, y: 637.133143, z: 0.0),
                                   DataStructure(x: 523.166667, y: 637.133143, z: 0.0),
                                   DataStructure(x: 541.083333, y: 637.133143, z: 0.0),
                                   DataStructure(x: 559.000000, y: 637.133143, z: 0.0),
                                   DataStructure(x: 576.916667, y: 637.133143, z: 0.0),
                                   DataStructure(x: 594.833333, y: 637.133143, z: 0.0),
                                   DataStructure(x: 612.750000, y: 637.133143, z: 0.0),
                                   DataStructure(x: 630.666667, y: 637.133143, z: 0.0),
                                   DataStructure(x: 290.250000, y: 654.370158, z: 0.0),
                                   DataStructure(x: 308.166667, y: 654.370158, z: 0.0),
                                   DataStructure(x: 326.083333, y: 654.370158, z: 0.0),
                                   DataStructure(x: 344.000000, y: 654.370158, z: 0.0),
                                   DataStructure(x: 361.916667, y: 654.370158, z: 0.0),
                                   DataStructure(x: 379.833333, y: 654.370158, z: 0.0),
                                   DataStructure(x: 397.750000, y: 654.370158, z: 0.0),
                                   DataStructure(x: 415.666667, y: 654.370158, z: 0.0),
                                   DataStructure(x: 433.583333, y: 654.370158, z: 0.0),
                                   DataStructure(x: 451.500000, y: 654.370158, z: 0.0),
                                   DataStructure(x: 469.416667, y: 654.370158, z: 0.0),
                                   DataStructure(x: 487.333333, y: 654.370158, z: 0.0),
                                   DataStructure(x: 505.250000, y: 654.370158, z: 0.0),
                                   DataStructure(x: 523.166667, y: 654.370158, z: 0.0),
                                   DataStructure(x: 541.083333, y: 654.370158, z: 0.0),
                                   DataStructure(x: 559.000000, y: 654.370158, z: 0.0),
                                   DataStructure(x: 576.916667, y: 654.370158, z: 0.0),
                                   DataStructure(x: 594.833333, y: 654.370158, z: 0.0),
                                   DataStructure(x: 612.750000, y: 654.370158, z: 0.0),
                                   DataStructure(x: 630.666667, y: 654.370158, z: 0.0),
                                   DataStructure(x: 290.250000, y: 671.607174, z: 0.0),
                                   DataStructure(x: 308.166667, y: 671.607174, z: 0.0),
                                   DataStructure(x: 326.083333, y: 671.607174, z: 0.0),
                                   DataStructure(x: 344.000000, y: 671.607174, z: 0.0),
                                   DataStructure(x: 361.916667, y: 671.607174, z: 0.0),
                                   DataStructure(x: 379.833333, y: 671.607174, z: 0.0),
                                   DataStructure(x: 397.750000, y: 671.607174, z: 0.0),
                                   DataStructure(x: 415.666667, y: 671.607174, z: 0.0),
                                   DataStructure(x: 433.583333, y: 671.607174, z: 0.0),
                                   DataStructure(x: 451.500000, y: 671.607174, z: 0.0),
                                   DataStructure(x: 469.416667, y: 671.607174, z: 0.0),
                                   DataStructure(x: 487.333333, y: 671.607174, z: 0.0),
                                   DataStructure(x: 505.250000, y: 671.607174, z: 0.0),
                                   DataStructure(x: 523.166667, y: 671.607174, z: 0.0),
                                   DataStructure(x: 541.083333, y: 671.607174, z: 0.0),
                                   DataStructure(x: 559.000000, y: 671.607174, z: 0.0),
                                   DataStructure(x: 576.916667, y: 671.607174, z: 0.0),
                                   DataStructure(x: 594.833333, y: 671.607174, z: 0.0),
                                   DataStructure(x: 612.750000, y: 671.607174, z: 0.0),
                                   DataStructure(x: 630.666667, y: 671.607174, z: 0.0),
                                   DataStructure(x: 290.250000, y: 688.844190, z: 0.0),
                                   DataStructure(x: 308.166667, y: 688.844190, z: 0.0),
                                   DataStructure(x: 326.083333, y: 688.844190, z: 0.0),
                                   DataStructure(x: 344.000000, y: 688.844190, z: 0.0),
                                   DataStructure(x: 361.916667, y: 688.844190, z: 0.0),
                                   DataStructure(x: 379.833333, y: 688.844190, z: 0.0),
                                   DataStructure(x: 397.750000, y: 688.844190, z: 0.0),
                                   DataStructure(x: 415.666667, y: 688.844190, z: 0.0),
                                   DataStructure(x: 433.583333, y: 688.844190, z: 0.0),
                                   DataStructure(x: 451.500000, y: 688.844190, z: 0.0),
                                   DataStructure(x: 469.416667, y: 688.844190, z: 0.0),
                                   DataStructure(x: 487.333333, y: 688.844190, z: 0.0),
                                   DataStructure(x: 505.250000, y: 688.844190, z: 0.0),
                                   DataStructure(x: 523.166667, y: 688.844190, z: 0.0),
                                   DataStructure(x: 541.083333, y: 688.844190, z: 0.0),
                                   DataStructure(x: 559.000000, y: 688.844190, z: 0.0),
                                   DataStructure(x: 576.916667, y: 688.844190, z: 0.0),
                                   DataStructure(x: 594.833333, y: 688.844190, z: 0.0),
                                   DataStructure(x: 612.750000, y: 688.844190, z: 0.0),
                                   DataStructure(x: 630.666667, y: 688.844190, z: 0.0),
                                   DataStructure(x: 290.250000, y: 706.081206, z: 0.0),
                                   DataStructure(x: 308.166667, y: 706.081206, z: 0.0),
                                   DataStructure(x: 326.083333, y: 706.081206, z: 0.0),
                                   DataStructure(x: 344.000000, y: 706.081206, z: 0.0),
                                   DataStructure(x: 361.916667, y: 706.081206, z: 0.0),
                                   DataStructure(x: 379.833333, y: 706.081206, z: 0.0),
                                   DataStructure(x: 397.750000, y: 706.081206, z: 0.0),
                                   DataStructure(x: 415.666667, y: 706.081206, z: 0.0),
                                   DataStructure(x: 433.583333, y: 706.081206, z: 0.0),
                                   DataStructure(x: 451.500000, y: 706.081206, z: 0.0),
                                   DataStructure(x: 469.416667, y: 706.081206, z: 0.0),
                                   DataStructure(x: 487.333333, y: 706.081206, z: 0.0),
                                   DataStructure(x: 505.250000, y: 706.081206, z: 0.0),
                                   DataStructure(x: 523.166667, y: 706.081206, z: 0.0),
                                   DataStructure(x: 541.083333, y: 706.081206, z: 0.0),
                                   DataStructure(x: 559.000000, y: 706.081206, z: 0.0),
                                   DataStructure(x: 576.916667, y: 706.081206, z: 0.0),
                                   DataStructure(x: 594.833333, y: 706.081206, z: 0.0),
                                   DataStructure(x: 612.750000, y: 706.081206, z: 0.0),
                                   DataStructure(x: 630.666667, y: 706.081206, z: 0.0),
                                   DataStructure(x: 290.250000, y: 723.318222, z: 0.0),
                                   DataStructure(x: 308.166667, y: 723.318222, z: 0.0),
                                   DataStructure(x: 326.083333, y: 723.318222, z: 0.0),
                                   DataStructure(x: 344.000000, y: 723.318222, z: 0.0),
                                   DataStructure(x: 361.916667, y: 723.318222, z: 0.0),
                                   DataStructure(x: 379.833333, y: 723.318222, z: 0.0),
                                   DataStructure(x: 397.750000, y: 723.318222, z: 0.0),
                                   DataStructure(x: 415.666667, y: 723.318222, z: 0.0),
                                   DataStructure(x: 433.583333, y: 723.318222, z: 0.0),
                                   DataStructure(x: 451.500000, y: 723.318222, z: 0.0),
                                   DataStructure(x: 469.416667, y: 723.318222, z: 0.0),
                                   DataStructure(x: 487.333333, y: 723.318222, z: 0.0),
                                   DataStructure(x: 505.250000, y: 723.318222, z: 0.0),
                                   DataStructure(x: 523.166667, y: 723.318222, z: 0.0),
                                   DataStructure(x: 541.083333, y: 723.318222, z: 0.0),
                                   DataStructure(x: 559.000000, y: 723.318222, z: 0.0),
                                   DataStructure(x: 576.916667, y: 723.318222, z: 0.0),
                                   DataStructure(x: 594.833333, y: 723.318222, z: 0.0),
                                   DataStructure(x: 612.750000, y: 723.318222, z: 0.0),
                                   DataStructure(x: 630.666667, y: 723.318222, z: 0.0),
                                   DataStructure(x: 290.250000, y: 740.555238, z: 0.0),
                                   DataStructure(x: 308.166667, y: 740.555238, z: 0.0),
                                   DataStructure(x: 326.083333, y: 740.555238, z: 0.0),
                                   DataStructure(x: 344.000000, y: 740.555238, z: 0.0),
                                   DataStructure(x: 361.916667, y: 740.555238, z: 0.0),
                                   DataStructure(x: 379.833333, y: 740.555238, z: 0.0),
                                   DataStructure(x: 397.750000, y: 740.555238, z: 0.0),
                                   DataStructure(x: 415.666667, y: 740.555238, z: 0.0),
                                   DataStructure(x: 433.583333, y: 740.555238, z: 0.0),
                                   DataStructure(x: 451.500000, y: 740.555238, z: 0.0),
                                   DataStructure(x: 469.416667, y: 740.555238, z: 0.0),
                                   DataStructure(x: 487.333333, y: 740.555238, z: 0.0),
                                   DataStructure(x: 505.250000, y: 740.555238, z: 0.0),
                                   DataStructure(x: 523.166667, y: 740.555238, z: 0.0),
                                   DataStructure(x: 541.083333, y: 740.555238, z: 0.0),
                                   DataStructure(x: 559.000000, y: 740.555238, z: 0.0),
                                   DataStructure(x: 576.916667, y: 740.555238, z: 0.0),
                                   DataStructure(x: 594.833333, y: 740.555238, z: 0.0),
                                   DataStructure(x: 612.750000, y: 740.555238, z: 0.0),
                                   DataStructure(x: 630.666667, y: 740.555238, z: 0.0),
                                   DataStructure(x: 290.250000, y: 757.792254, z: 0.0),
                                   DataStructure(x: 308.166667, y: 757.792254, z: 0.0),
                                   DataStructure(x: 326.083333, y: 757.792254, z: 0.0),
                                   DataStructure(x: 344.000000, y: 757.792254, z: 0.0),
                                   DataStructure(x: 361.916667, y: 757.792254, z: 0.0),
                                   DataStructure(x: 379.833333, y: 757.792254, z: 0.0),
                                   DataStructure(x: 397.750000, y: 757.792254, z: 0.0),
                                   DataStructure(x: 415.666667, y: 757.792254, z: 0.0),
                                   DataStructure(x: 433.583333, y: 757.792254, z: 0.0),
                                   DataStructure(x: 451.500000, y: 757.792254, z: 0.0),
                                   DataStructure(x: 469.416667, y: 757.792254, z: 0.0),
                                   DataStructure(x: 487.333333, y: 757.792254, z: 0.0),
                                   DataStructure(x: 505.250000, y: 757.792254, z: 0.0),
                                   DataStructure(x: 523.166667, y: 757.792254, z: 0.0),
                                   DataStructure(x: 541.083333, y: 757.792254, z: 0.0),
                                   DataStructure(x: 559.000000, y: 757.792254, z: 0.0),
                                   DataStructure(x: 576.916667, y: 757.792254, z: 0.0),
                                   DataStructure(x: 594.833333, y: 757.792254, z: 0.0),
                                   DataStructure(x: 612.750000, y: 757.792254, z: 0.0),
                                   DataStructure(x: 630.666667, y: 757.792254, z: 0.0)]
}

extension UIViewController {

    func presentAlert(withTitle title: String, message: String) {
        let alertController = UIAlertController(title: title, message: "", preferredStyle: .alert)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.paragraphSpacing = 2.0
        paragraphStyle.headIndent = 10.0
        paragraphStyle.firstLineHeadIndent = 10.0
        paragraphStyle.tailIndent = -10.0
        
        let font = UIFont(name: "Helvetica", size: 14)!
        let attribString = NSMutableAttributedString(string: message, attributes: [NSAttributedString.Key.paragraphStyle: paragraphStyle, NSAttributedString.Key.font: font])
        
        //need to set a label as `accessoryView` of an alert.
        alertController.setValue(attribString, forKey: "attributedMessage")
        
        let OKAction = UIAlertAction(title: "Dismiss", style: .default) { action in
        }
        alertController.addAction(OKAction)
        self.present(alertController, animated: true, completion: nil)
    }
}


extension String {
    
    // MARK: -
    // MARK: Insert Linebreak into a String at X intervals and without breaking a word
    
    func splitWithLineBreaks(byCount n: Int, breakableCharacterSet: CharacterSet = CharacterSet(charactersIn: " ")) -> (outString: String, noLines: Int) {
        
        precondition(n > 0)
        guard !self.isEmpty && self.count > n else { return (self, 1) }

        var string = String(self)
        var startIndex = string.startIndex

        repeat {
            // Break a string into lines.
            var endIndex = string[string.index(after: startIndex)...].firstIndex(of: "\n") ?? string.endIndex
            if self.distance(from: startIndex, to: endIndex) > n {
                let wrappedLine = string[startIndex..<endIndex].split(byCount: n, breakableCharacters: breakableCharacterSet.characters())
                string.replaceSubrange(startIndex..<endIndex, with: wrappedLine)
                endIndex = string.index(startIndex, offsetBy: wrappedLine.count)
            }

            startIndex = endIndex
        } while startIndex < string.endIndex
        let nolines = Array<String>(string.components(separatedBy: "\n")).count
        return (string, nolines)
    }
    
}

extension Substring {
    
    func split(byCount n: Int, breakableCharacters: [Character]) -> String {
        var line = String(self)
        var lineStartIndex = self.startIndex
        
        while line.distance(from: lineStartIndex, to: line.endIndex) > n {
            let maxLineEndIndex = line.index(lineStartIndex, offsetBy: n)

            if breakableCharacters.contains(self[maxLineEndIndex]) {
                // If line terminates at a breakable character, replace that character with a newline
                line.replaceSubrange(maxLineEndIndex...maxLineEndIndex, with: "\n")
                lineStartIndex = line.index(after: maxLineEndIndex)
            } else if let index = line[lineStartIndex..<maxLineEndIndex].lastIndex(where: { breakableCharacters.contains($0) }) {
                // Otherwise, find a breakable character that is between lineStartIndex and maxLineEndIndex
                line.replaceSubrange(index...index, with: "\n")
                lineStartIndex = index
            } else {
                // Finally, forcible break a word
                line.insert("\n", at: maxLineEndIndex)
                lineStartIndex = maxLineEndIndex
            }
        }

        return line
    }
}

extension CharacterSet {
    func characters() -> [Character] {
        // A Unicode scalar is any Unicode code point in the range U+0000 to U+D7FF inclusive or U+E000 to U+10FFFF inclusive.
        return codePoints().compactMap { UnicodeScalar($0) }.map { Character($0) }
    }

    func codePoints() -> [Int] {
        var result: [Int] = []
        var plane = 0
        // following documentation at https://developer.apple.com/documentation/foundation/nscharacterset/1417719-bitmaprepresentation
        for (i, w) in bitmapRepresentation.enumerated() {
            let k = i % 8193
            if k == 8192 {
                // plane index byte
                plane = Int(w) << 13
                continue
            }
            let base = (plane + k) << 3
            for j in 0 ..< 8 where w & 1 << j != 0 {
                result.append(base + j)
            }
        }
        return result
    }
}

extension UIImage {
    func tinted(with color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        color.set()
        withRenderingMode(.alwaysTemplate)
            .draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func scale(to newSize: CGSize) -> UIImage? {
        //UIGraphicsBeginImageContext(newSize);
        // In next line, pass 0.0 to use the current device's pixel scaling factor (and thus account for Retina resolution).
        // Pass 1.0 to force exact pixel size.
        UIGraphicsBeginImageContextWithOptions(newSize, _: false, _: 0.0)
        self.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
        let newImage: UIImage? = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}
