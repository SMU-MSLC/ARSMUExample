//
//  ViewController.swift
//  ARSMUExample
//
//  Created by Eric Larson on 11/2/17.
//  Copyright © 2017 Eric Larson. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    
    //MARK: - Class Properties
    
    let imageSize = 720
    var lastNode:SCNNode? = nil
    
    var label = SCNNode()
    var objectFound = false
    var objectNode:SCNNode? = nil
    var numArtImages = 0
    
    // Special thanks to SMU students T. Pop, J. Ledford, and L. Wood for these styles!
    var models = [wave_style().model,mosaic_style().model,udnie_style().model] as [MLModel]
    
    //MARK: - UI and Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        // distilled from https://www.thingiverse.com/thing:210565/#files 
        let scene = SCNScene(named: "art.scnassets/peruna.dae")!
        
        // Set the scene to the view
        sceneView.scene = scene
        
        label = createTextNode(textString: "Welcome to the Art Gallery!")!
        
        setupDetectionOverlay()
        setupVision(useCPUOnly:false) // set to use GPU, if FPS is a problem, change to true.
        
    }
    
    
    
    @IBAction func handleTap(_ sender: UITapGestureRecognizer) {
        
        // grab the current AR session frame from the scene, if possible
        guard let currentFrame = sceneView.session.currentFrame else {
            return
        }
        
        // setup some geometry for a simple plane
        let imagePlane = SCNPlane(width:sceneView.bounds.width/6000,
                                  height:sceneView.bounds.height/6000)
        
        // take a snapshot of the current image shown to user
        // spawn this on a separate queue
        //       and then come back to main queue for adding node
        let idx = random(models.count) // choose random style
        
        let startImage = sceneView.snapshot()
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            // this is spawned on background process so that it is not at the expense of
            // the AR Session performance
            guard let self = self else {
                // try to get a weak handle to self, if self still exists
                return // this prevents memory cycles
            }
                
            let newImage = self.stylizeImage(cgImage: startImage.cgImage!, model: self.models[idx])

            imagePlane.firstMaterial?.diffuse.contents = newImage
            imagePlane.firstMaterial?.lightingModel = .constant
            imagePlane.firstMaterial?.isDoubleSided = true
            
            // add the node to the scene
            let planeNode = SCNNode(geometry:imagePlane)
            
            
            // save this last node
            self.lastNode = planeNode
            
            // Now the image is stylized, added to a node, and ready to be added into the AR session
            
            // To update the UI, we should now change to main thread
            DispatchQueue.main.async{
                if let object=self.objectNode{
                    // add node in relation to other node
                    // keep tweaking position along the "art" walls
                    // so that the images appear in rows
                    let imagesPerRow:Int = 6
                    let separation:Float = 0.15
                    let x = -separation * Float(imagesPerRow/2) + Float(self.numArtImages % imagesPerRow) * separation
                    let y = 0.1 * Float(Int(self.numArtImages / imagesPerRow))
                    
                    planeNode.position = SCNVector3Make(x,0,y)// tweak position on anchor
                    object.addChildNode(planeNode)
                    
                    self.numArtImages += 1
                }
                else{
                    // otherwise, add in the node where the camera is
                    // update the node to be a bit in front of the camera inside the AR session
                    self.sceneView.scene.rootNode.addChildNode(planeNode)
                    
                    // step one create a translation transform
                    var translation = matrix_identity_float4x4
                    translation.columns.3.z = -0.1 // make transition a little in front of camera
                    
                    // step two, apply translation relative to camera for the node
                    // if we have recognized an object, add in the node at the recognized object
                    planeNode.simdTransform = matrix_multiply(currentFrame.camera.transform, translation )
                }
            }
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // here is where we setup detection of 3D point clouds, drag into AR assests
        guard let referenceObjects = ARReferenceObject.referenceObjects(inGroupNamed: "gallery", bundle: nil) else {
            fatalError("Missing expected asset catalog resources.")
        }
        configuration.detectionObjects = referenceObjects // only one object to detect, which is the engine

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    @IBAction func didSwipe(_ sender: UISwipeGestureRecognizer) {
        
        // for making actions on nodes (images) that are already added to the gallery
        if let node = lastNode {
            var moveAction:SCNAction
            
            switch sender.direction {
            case .left:
                moveAction = SCNAction.moveBy(x: -0.1, y: 0.0, z: 0, duration: 0.25)
            case .right:
                moveAction = SCNAction.moveBy(x: 0.1, y: 0.0, z: 0, duration: 0.25)
            case .up:
                moveAction = SCNAction.moveBy(x: 0.0, y: 0.1, z: 0, duration: 0.25)
            case .down:
                moveAction = SCNAction.moveBy(x: 0.0, y: -0.1, z: 0, duration: 0.25)
            default:
                moveAction = SCNAction.moveBy(x: 0.0, y: 0.0, z: 0, duration: 0.25)
            }
            

            node.runAction(SCNAction.repeatForever(moveAction))
        }
        
    }
    
    
    

    // MARK: - ARSCNViewDelegate
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        // This delegate is called when an object in the ARObject list is detected
        // Perform setup of the object and add any nodes, slaved to the position
        // of the detected object (so that they also get corrected from ARKit
        // if the tracking get updated).
        
        
        if let objectAnchor = anchor as? ARObjectAnchor {
            if (objectNode != nil) { return } // if we already recognized the object, don't do this again

            print(objectAnchor.name! + " found")
            
            // add some text and action for animating the text
            let prevScale = label.scale
            label.scale = SCNVector3(CGFloat(prevScale.x)/3, CGFloat(prevScale.x)/3, CGFloat(prevScale.x)/3)
            
            let scaleAction = SCNAction.scale(to: CGFloat(prevScale.x), duration: 2)
            scaleAction.timingMode = .easeIn
            
            node.addChildNode(label)
            
            self.label.runAction(scaleAction, forKey: "scaleAction")
            
            
            //==================================================
            // add a box, translucent, around the object
            let box = self.createBox()
            node.addChildNode(box!)
            
            let alphaAction = SCNAction.fadeOpacity(to: 0.1, duration: 5)
            box?.runAction(alphaAction)
            
            //==================================================
            // add in a video near the detected object
            let contentPlane = SCNPlane(width: CGFloat(0.1), height: CGFloat(0.05))
            
            // make into material
            let avMaterial = SCNMaterial()
            avMaterial.diffuse.contents = getLoopingAVPlayerFromFile(file:"Dumbo", ext:"mp4")
            
            // play on a plane
            contentPlane.materials = [avMaterial]
            
            contentPlane.firstMaterial?.isDoubleSided = true
            
            let videoNode = SCNNode()
            videoNode.position = SCNVector3Make(-0.1, 0.2, 0.0)
            videoNode.geometry = contentPlane
            node.addChildNode(videoNode)

            objectNode = node // save for adding to this node later on
        }

    }
    
    
    // AR delegate where we run our image model on video frame
    // check to be sure this is the proper delegate function for this.
    var currentBuffer:CVPixelBuffer! = nil
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        //MARK: Two, Get Image Frame from AR
        // get current ARSession frame so that we can get AVSession Image Capture
        guard let frame = sceneView.session.currentFrame else { return }

        // check to be sure buffer is nil, which means free to process
        guard self.currentBuffer == nil, case .normal = frame.camera.trackingState else {
            // drop the frame if we are processing a current image or if AR is suffering tracking
            return // just drop the frame
        }
        // Otherwise, let's get the image and analyze it!
        
        // Retain the image buffer for Vision processing.
        self.currentBuffer = frame.capturedImage // the pixels to process
        self.captureImageSize = frame.camera.imageResolution // needed for displaying overlays
        
        // get phone orientation (currently only supports lanscape left)
        let exifOrientation = self.exifOrientationFromDeviceOrientation()
        
        // run in the background so that AR doesn't suffer performance
        // this delegate function is called at nearly 60 FPS
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else {
                return // this prevent memory cycles
            }
            
            // generate a request to analyze the image for objects
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: self.currentBuffer,
                                                            orientation: exifOrientation,
                                                            options: [:])
            
            //MARK: Three, Start Vision Request
            // the handler for this was specified in setupVision
            // when the request is done, we will call handleObjectRecognitionResult
            do {
                try imageRequestHandler.perform(self.requests)
            } catch {
                print(error)
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    //MARK: - Utils
    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        // override, only works in landscape left for Demo
        // ORIENT:change this if running in another position
        // Device oriented horizontally, home button on the left
        return CGImagePropertyOrientation.down
    }
    
    
    // code from fast style transfer example in iOS app
    // https://github.com/prisma-ai/torch2coreml/tree/master/example/fast-neural-style/ios
    private func stylizeImage(cgImage: CGImage, model: MLModel) -> CGImage {
        let input = StyleTransferInput(input: pixelBuffer(cgImage: cgImage, width: imageSize, height: imageSize))
        let outFeatures = try! model.prediction(from: input)
        let output = outFeatures.featureValue(for: "outputImage")!.imageBufferValue!
        CVPixelBufferLockBaseAddress(output, .readOnly)
        let width = CVPixelBufferGetWidth(output)
        let height = CVPixelBufferGetHeight(output)
        let data = CVPixelBufferGetBaseAddress(output)!
        
        let outContext = CGContext(data: data,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(output),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageByteOrderInfo.order32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)!
        let outImage = outContext.makeImage()!
        CVPixelBufferUnlockBaseAddress(output, .readOnly)
        
        return outImage
    }
    
    //https://github.com/prisma-ai/torch2coreml/tree/master/example/fast-neural-style/ios
    private func pixelBuffer(cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA , nil, &pixelBuffer)
        if status != kCVReturnSuccess {
            fatalError("Cannot create pixel buffer for image")
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags.init(rawValue: 0))
        let data = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: bitmapInfo.rawValue)
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer!
    }
    
    func createTextNode(textString: String)->SCNNode?{
        
        let textNode:SCNNode? = SCNNode()
        textNode!.geometry = setupTextParameters(textString: textString) // make this node text
        textNode!.scale = SCNVector3Make(0.001, 0.001, 0.001)
        textNode!.position = SCNVector3Make(-0.1, 0.1, 0.0)// tweak position over anchor
        textNode!.eulerAngles.y = 0
        textNode?.castsShadow = true
        
        
        return textNode
    }
    
    func setupTextParameters(textString: String)->SCNText{
        let text = SCNText(string: textString, extrusionDepth: 1)
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        
        text.flatness = 0
        text.isWrapped = true
        text.materials = [material]
        return text
    }
    
    var avPlayer:AVPlayer! = nil
    func getLoopingAVPlayerFromFile(file:String, ext:String)->AVPlayer?{
        // https://www.raywenderlich.com/6957-building-a-museum-app-with-arkit-2
        guard let videoURL = Bundle.main.url(forResource: file,
                                             withExtension: ext) else {
                                                return nil
        }
        
        let avPlayerItem = AVPlayerItem(url: videoURL)
        if avPlayer==nil{
            avPlayer = AVPlayer(playerItem: avPlayerItem)
            avPlayer.play()
            
            // replay
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: nil,
                queue: nil) { notification in
                    self.avPlayer.seek(to: .zero)
                    self.avPlayer.play()
            }
        }else{
            avPlayer = AVPlayer(playerItem: avPlayerItem)
            avPlayer.play()
        }
        
        
        return avPlayer
    }
    
    func createBox()->SCNNode?{
        let boxNode:SCNNode? = SCNNode()
        
        let box = SCNBox(width: CGFloat(0.1), height: CGFloat(0.1), length: CGFloat(0.1), chamferRadius: 0.01)
        box.firstMaterial?.diffuse.contents = UIColor(white: 1.0, alpha: 0.8)
        box.firstMaterial?.isDoubleSided = true
        
        boxNode!.geometry = box // make this node a box!
        boxNode!.position = SCNVector3Make(0.0, 0.0, 0.0)// tweak position over anchor
        
        return boxNode
    }
    
    func random(_ n:Int) -> Int
    {
        return Int(arc4random_uniform(UInt32(n)))
    }
    
    
    //MARK: - Vision YOLO Methods
    
    let model = PersonBike()
    private var requests = [VNRequest]()
    
    @discardableResult
    func setupVision(useCPUOnly:Bool) -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        
        do {
            
            //MARK: One, Setup Vision
            // grabe the model and wrap as a Vision Object
            let visionModel = try VNCoreMLModel(for: model.model)
            
            // use this request to setup the object recognition with Vision
            let objectRecognition = VNCoreMLRequest(model: visionModel,
                                                    completionHandler: self.handleObjectRecognitionResult)
            
            objectRecognition.imageCropAndScaleOption = .scaleFill
            objectRecognition.usesCPUOnly = useCPUOnly // ensure we have resources for AR
            self.requests = [objectRecognition] // recognition requests for the vision model
            
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        return error
    }
    
    func handleObjectRecognitionResult(_ request:VNRequest, error:Error?){
        
        //MARK: Four, Handle Display of Results
        // perform all the UI updates on the main queue
        if let results = request.results { // if we have valid results, else its nil
            DispatchQueue.main.async(execute: {
                

                // this display code adapted from WWDC 2018, Breakfast Finder App
                // https://developer.apple.com/documentation/vision/recognizing_objects_in_live_capture
                self.drawVisionRequestResults(results)
                self.updateOverlay() // move overlay with screen position
                
                // set as nil so we can process next ARFrame Image
                self.currentBuffer = nil
            })
        }
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
        // this display code adapted from WWDC 2018, Breakfast Finder App
        // https://developer.apple.com/documentation/vision/recognizing_objects_in_live_capture
        
        // now draw everything (halt animation while we update)
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // if any other displayed objects existed, delete them
        detectionOverlay.sublayers = nil // remove all the old recognized objects
        
        // for each result, create an overlay layer to display on it
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox,
                                                            Int(captureImageSize.width),
                                                            Int(captureImageSize.height))
            // get bounding box for object
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds,
                                                                   identifier: topLabelObservation.identifier)
            // show the label and confidence
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                            identifier: topLabelObservation.identifier,
                                                            confidence: topLabelObservation.confidence)
            shapeLayer.addSublayer(textLayer)// add text to box
            detectionOverlay.addSublayer(shapeLayer) // add box to the UI
        }
        CATransaction.commit() // now commit eveything so that it displays
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        // this display code adapted from WWDC 2018, Breakfast Finder App
        // https://developer.apple.com/documentation/vision/recognizing_objects_in_live_capture
        
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "HelveticaNeue-Light", size: 28.0)!
        let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 1.0, 1.0])!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont,
                                       NSAttributedString.Key.foregroundColor:color],
                                      range: NSRange(location: 0, length: identifier.count))
        formattedString.addAttributes([NSAttributedString.Key.foregroundColor:color],
                                      range: NSRange(location: identifier.count-1, length:19 ))
        textLayer.string = formattedString
        
        textLayer.shadowOpacity = 0.3
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.contentsScale = 1.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.width - 10, height: bounds.size.height - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        //textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(0.0 / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect, identifier:String) -> CALayer {
        let shapeLayer = CALayer()
        
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = self.mapColorFrom(identifier)
        shapeLayer.cornerRadius = 7
        
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        shapeLayer.setAffineTransform(CGAffineTransform(translationX: 0.0, y: 0.0).scaledBy(x: 1.0, y: -1.0))
        return shapeLayer
    }
    
    func mapColorFrom(_ identifier:String)->CGColor? {
        
        var color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 0.0, 0.2, 0.2])
        
        switch identifier {
        case "Person":
            color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                            components: [1.0, 0.0, 0.0, 0.2])
        case "Bike":
            color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                            components: [0.0, 1.0, 0.0, 0.2])
        default:
            color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                            components: [0.0, 0.0, 1.0, 0.2])
        }
        
        return color
    }
    
    var detectionOverlay:CALayer! = nil
    var captureImageSize:CGSize! = nil
    func setupDetectionOverlay() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        
        
        // set the initial bounds, will transform when we know more about the image
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: (self.view.bounds.width * 1),
                                         height: (self.view.bounds.height * 1))

        self.sceneView.layer.addSublayer(detectionOverlay)
    }
    
    func updateOverlay() {
        // this function must be called from the main Queue
        
        let bounds = self.view.bounds
        var scale: CGFloat
        
        // phone is flipped so be sure bounds line up with scaling
        let xScale: CGFloat = bounds.size.width /  captureImageSize.width * 1.0
        let yScale: CGFloat = bounds.size.height / captureImageSize.height * 1.0
        
        // depending on the size of the image Vision cropped it
        // according to the larger dimension, so we need to take a
        // max here to account for that.
        // NOTE: this is specific to the .scaleFill setting in setupVision
        scale = fmax(xScale, yScale)
        
        // rotate the layer into screen orientation and scale and mirror
        // ORIENT: hard coded for landscape left format
        detectionOverlay.setAffineTransform(
            CGAffineTransform(scaleX: scale, y: -scale))
        
        // this tries to get the best mapping we can from the cropping that
        // Core Vision used. It may not be 100% perfect
        
        // center the layer, after scaling it
        detectionOverlay.position = CGPoint (x: bounds.midY * 1.0,
                                             y: bounds.midX * 1.0)
        
        detectionOverlay.setNeedsDisplay() // sets display for all subviews in object dictionary
        
    }
    
}



