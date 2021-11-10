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
    
    //MARK: Class Properties
    
    let imageSize = 720
    var lastNode:SCNNode? = nil
    
    var label = SCNNode()
    var objectFound = false
    var objectNode:SCNNode? = nil
    var numArtImages = 0
    
    // Special thanks to SMU students T. Pop, J. Ledford, and L. Wood for these styles!
    lazy var wave:wave_style = {
        do{
            let config = MLModelConfiguration()
            return try wave_style(configuration: config)
        }catch{
            print(error)
            fatalError("Could not load ML model")
        }
    }()
    
    lazy var mosaic:mosaic_style = {
        do{
            let config = MLModelConfiguration()
            return try mosaic_style(configuration: config)
        }catch{
            print(error)
            fatalError("Could not load ML model")
        }
    }()
    
    lazy var udnie:udnie_style = {
        do{
            let config = MLModelConfiguration()
            return try udnie_style(configuration: config)
        }catch{
            print(error)
            fatalError("Could not load ML model")
        }
    }()
    
    
    var models:[MLModel] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Special thanks to SMU students T. Pop, J. Ledford, and L. Wood for these styles!
        self.models = [wave.model, mosaic.model, udnie.model] as [MLModel]
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        // distilled from https://www.thingiverse.com/thing:210565/#files
        if let scene = SCNScene(named: "peruna.scn"){
            // Set the scene to the view
            sceneView.scene = scene
        }
        
        label = createTextNode(textString: "Welcome to the Art Gallery!")!
        
    }
    
    func random(_ n:Int) -> Int
    {
        return Int(arc4random_uniform(UInt32(n)))
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
                return // this prevent memory cycles
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
            
            
            node.runAction(moveAction)
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
            
            DispatchQueue.main.async{
                
                // add some text and action for animating the text
                let prevScale = self.label.scale
                self.label.scale = SCNVector3(CGFloat(prevScale.x)/3, CGFloat(prevScale.x)/3, CGFloat(prevScale.x)/3)
                
                let scaleAction = SCNAction.scale(to: CGFloat(prevScale.x), duration: 2)
                scaleAction.timingMode = .easeIn
                
                node.addChildNode(self.label)
                
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
                avMaterial.diffuse.contents = self.getLoopingAVPlayerFromFile(file:"Dumbo", ext:"mp4")
                
                // play on a plane
                contentPlane.materials = [avMaterial]
                
                contentPlane.firstMaterial?.isDoubleSided = true
                
                let videoNode = SCNNode()
                videoNode.position = SCNVector3Make(-0.1, 0.2, 0.0)
                videoNode.geometry = contentPlane
                node.addChildNode(videoNode)
                
                self.objectNode = node // save for adding to this node later on
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
    
}



