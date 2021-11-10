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
        // TODO: something is wrong with the assets cache, so loading directly
        //let scene = SCNScene(named: "art.scnassets/peruna.dae")!
        if let scene = SCNScene(named: "peruna.scn"){
            // Set the scene to the view
            sceneView.scene = scene
            print("loaded file for scene")
        }
        
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
        // TODO: spawn this on a separate queue
        //       and then come back to main queue for adding node
        let idx = random(models.count) // choose random style
        
        let startImage = sceneView.snapshot()
        DispatchQueue.global(qos: .background).async{
            let newImage = self.stylizeImage(cgImage: startImage.cgImage!, model: self.models[idx])
            
            DispatchQueue.main.async{
                imagePlane.firstMaterial?.diffuse.contents = newImage
                imagePlane.firstMaterial?.lightingModel = .constant
                
                // add the node to the scene
                let planeNode = SCNNode(geometry:imagePlane)
                self.sceneView.scene.rootNode.addChildNode(planeNode)
                
                // save this last node
                self.lastNode = planeNode
                
                // update the node to be a bit in front of the camera inside the AR session
                
                // step one create a translation transform
                var translation = matrix_identity_float4x4
                translation.columns.3.z = -0.1
                
                // step two, apply translation relative to camera for the node
                planeNode.simdTransform = matrix_multiply(currentFrame.camera.transform, translation )
            }
        }
        
    }
    
    @IBAction func didSwipe(_ sender: UISwipeGestureRecognizer) {
        
        
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
        configuration.detectionObjects = referenceObjects // look for these

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
//    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
//        let node = SCNNode()
//
//        return node
//    }

    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
        if let objectAnchor = anchor as? ARObjectAnchor {
            print("Elephant Found!!", node)
        }
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
}



