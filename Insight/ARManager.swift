import SwiftUI
import ARKit
import SceneKit
import Combine

class ARManager: NSObject, ARSCNViewDelegate, ARSessionDelegate, ObservableObject {
    static let shared = ARManager()
    
    var sceneView: ARSCNView?
    @Published var statusMessage: String = "Initializing AR..."
    
    // Interaction State
    var selectedNode: SCNNode?
    
    // --- SETUP ---
    func setup(view: ARSCNView) {
        self.sceneView = view
        view.delegate = self
        view.session.delegate = self
        view.autoenablesDefaultLighting = true
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        view.session.run(config, options: [])
        
        // Gestures
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        view.addGestureRecognizer(longPressGesture)
    }
    
    func pause() { sceneView?.session.pause() }
    
    // --- TRACKING STATUS ---
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .notAvailable: DispatchQueue.main.async { self.statusMessage = "AR not available." }
        case .limited(let reason):
            DispatchQueue.main.async {
                switch reason {
                case .initializing: self.statusMessage = "Move iPhone to map room..."
                case .excessiveMotion: self.statusMessage = "Slow down."
                default: self.statusMessage = "Improving tracking..."
                }
            }
        case .normal: DispatchQueue.main.async { self.statusMessage = "Ready. Tap surface to Pin." }
        }
    }
    
    // --- PERSISTENCE: LOAD MAP ---
    func loadInitialWorldMap(from items: [InsightItem]) {
        guard let savedItem = items.first(where: { $0.arWorldMapData != nil }),
              let mapData = savedItem.arWorldMapData,
              let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData) else { return }
        
        let config = ARWorldTrackingConfiguration()
        config.initialWorldMap = worldMap
        config.planeDetection = [.horizontal, .vertical]
        sceneView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        statusMessage = "Relocalizing..."
        
        // Restore Custom Scales
        // We defer this slightly to ensure anchors are added by ARKit first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.restoreCustomScales(items: items)
        }
    }
    
    func restoreCustomScales(items: [InsightItem]) {
        guard let view = sceneView else { return }
        for anchor in view.session.currentFrame?.anchors ?? [] {
            if let noteItem = items.first(where: { ($0.title ?? "Note") == anchor.name }),
               let scale = noteItem.arNodeScale,
               let node = view.node(for: anchor),
               let card = node.childNode(withName: "GlassCard", recursively: true) {
                card.scale = SCNVector3(scale, scale, scale)
            }
        }
    }
    
    // --- INTERACTION ---
    
    // 1. TAP (Select/Pin)
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = sceneView else { return }
        let location = gesture.location(in: view)
        let hitTest = view.hitTest(location, options: nil)
        
        if let firstNode = hitTest.first?.node, let rootNode = findRootCard(from: firstNode) {
            selectNode(rootNode)
            return
        }
        NotificationCenter.default.post(name: .arDidTapEmptySpace, object: location)
        deselectNode()
    }
    
    // 2. LONG PRESS (Remove/Menu)
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = sceneView else { return }
        let location = gesture.location(in: view)
        let hitTest = view.hitTest(location, options: nil)
        
        if let firstNode = hitTest.first?.node, let rootNode = findRootCard(from: firstNode) {
            selectNode(rootNode)
            // Notify UI to show menu for this node name
            // The name of the anchor is stored in rootNode.parent's attached anchor
            // But we simplified visuals. The textNode has the title.
            // Let's pass the Title back via Notification
            // We need to find the Anchor associated with this node to delete it properly
            if let anchorNode = rootNode.parent, let anchor = view.anchor(for: anchorNode) {
                NotificationCenter.default.post(name: .arDidLongPressNode, object: anchor.name)
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.impactOccurred()
            }
        }
    }
    
    // 3. PINCH (Resize)
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let node = selectedNode else { return }
        if gesture.state == .changed {
            let pinchScale = Float(gesture.scale)
            let currentScale = node.scale.x
            let newScale = currentScale * pinchScale
            if newScale > 0.5 && newScale < 3.0 {
                node.scale = SCNVector3(newScale, newScale, newScale)
                // Notify UI to save this scale?
                // For performance, we just update visual here.
                // We need a way to save this back to DB.
                // We'll send a notification on .ended
            }
            gesture.scale = 1
        }
        if gesture.state == .ended {
            // Find anchor name to identify item
            if let anchorNode = node.parent, let view = sceneView, let anchor = view.anchor(for: anchorNode) {
                let info: [String: Any] = ["name": anchor.name ?? "", "scale": node.scale.x]
                NotificationCenter.default.post(name: .arDidResizeNode, object: info)
            }
        }
    }
    
    private func findRootCard(from node: SCNNode) -> SCNNode? {
        if node.name == "GlassCard" { return node }
        if let parent = node.parent { return findRootCard(from: parent) }
        return nil
    }
    
    private func selectNode(_ node: SCNNode) {
        deselectNode()
        selectedNode = node
        let pulseUp = SCNAction.scale(to: 1.1, duration: 0.1)
        let pulseDown = SCNAction.scale(to: 1.05, duration: 0.1) // Keep slightly larger
        node.runAction(SCNAction.sequence([pulseUp, pulseDown]))
        if let plane = node.geometry as? SCNPlane { plane.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.3) }
        DispatchQueue.main.async { self.statusMessage = "Note Selected. Pinch to Resize." }
    }
    
    private func deselectNode() {
        if let node = selectedNode {
            node.runAction(SCNAction.scale(to: 1.0, duration: 0.1))
            if let plane = node.geometry as? SCNPlane { plane.firstMaterial?.emission.contents = UIColor.black }
        }
        selectedNode = nil
    }
    
    // --- ACTIONS ---
    func removeAnchor(name: String) {
        guard let view = sceneView else { return }
        if let anchor = view.session.currentFrame?.anchors.first(where: { $0.name == name }) {
            view.session.remove(anchor: anchor)
            statusMessage = "Note Removed."
        }
    }
    
    func placeNote(at screenPoint: CGPoint, for item: InsightItem, completion: @escaping (Data, Data) -> Void) {
        guard let view = sceneView else { return }
        guard let query = view.raycastQuery(from: screenPoint, allowing: .estimatedPlane, alignment: .any),
              let result = view.session.raycast(query).first else {
            statusMessage = "Surface not detected. Move phone."
            return
        }
        
        let anchorName = item.title ?? "Note"
        // Remove old if exists
        if let oldAnchor = view.session.currentFrame?.anchors.first(where: { $0.name == anchorName }) {
            view.session.remove(anchor: oldAnchor)
        }
        
        let anchor = ARAnchor(name: anchorName, transform: result.worldTransform)
        view.session.add(anchor: anchor)
        
        // Inject Content into visual manually for first render
        // (Wait a split second for anchor to register or rely on delegate)
        // Delegate handles it.
        
        view.session.getCurrentWorldMap { map, _ in
            guard let map = map,
                  let mapData = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true),
                  let transformData = try? NSKeyedArchiver.archivedData(withRootObject: result.worldTransform, requiringSecureCoding: false)
            else { return }
            completion(transformData, mapData)
        }
    }
    
    // --- VISUALS ---
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let name = anchor.name else { return }
        // Find content for this note?
        // Limitation: ARManager doesn't have access to DB.
        // We will just render Title for now, OR we need to pass content in anchor name (messy).
        // Solution: Notification to ask Delegate/View for content?
        // Better Solution: We pass the item content in the `addVisual` call or just use title + generic text.
        // For this demo, let's try to lookup the item if possible, but ARManager is decoupled.
        // Quick Fix: We will assume the anchor name is the Title. The View already saves content.
        // To show content 3D, we need it here.
        // We will trigger a callback to get content.
        
        DispatchQueue.main.async {
            // Ask the UI what the content is for this title
            NotificationCenter.default.post(name: .arNeedContentForAnchor, object: node, userInfo: ["name": name])
        }
    }
    
    // Called by View after lookup
    func updateVisual(for node: SCNNode, title: String, content: String) {
        // 1. Card
        let width: CGFloat = 0.25; let height: CGFloat = 0.15
        let plane = SCNPlane(width: width, height: height); plane.cornerRadius = 0.015
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(white: 0.1, alpha: 0.9)
        material.blendMode = .alpha
        plane.materials = [material]
        let cardNode = SCNNode(geometry: plane)
        cardNode.name = "GlassCard"
        cardNode.position = SCNVector3(0, 0.1, 0)
        
        // 2. Title Text
        let titleGeo = SCNText(string: title, extrusionDepth: 0.5)
        titleGeo.font = UIFont.systemFont(ofSize: 12, weight: .bold); titleGeo.flatness = 0.1
        titleGeo.firstMaterial?.diffuse.contents = UIColor.white; titleGeo.firstMaterial?.lightingModel = .constant
        let titleNode = SCNNode(geometry: titleGeo)
        titleNode.scale = SCNVector3(0.0015, 0.0015, 0.0015) // Scale down
        let (minT, maxT) = titleGeo.boundingBox
        let tW = Float(maxT.x - minT.x) * 0.0015
        titleNode.position = SCNVector3(-tW/2, 0.01, 0.01) // Top half
        cardNode.addChildNode(titleNode)
        
        // 3. Content Text (Truncated)
        let safeContent = content.prefix(40) + (content.count > 40 ? "..." : "")
        let contentGeo = SCNText(string: String(safeContent), extrusionDepth: 0.5)
        contentGeo.font = UIFont.systemFont(ofSize: 10, weight: .regular); contentGeo.flatness = 0.1
        contentGeo.firstMaterial?.diffuse.contents = UIColor.lightGray; contentGeo.firstMaterial?.lightingModel = .constant
        let contentNode = SCNNode(geometry: contentGeo)
        contentNode.scale = SCNVector3(0.0012, 0.0012, 0.0012)
        let (minC, maxC) = contentGeo.boundingBox
        let cW = Float(maxC.x - minC.x) * 0.0012
        contentNode.position = SCNVector3(-cW/2, -0.04, 0.01) // Bottom half
        cardNode.addChildNode(contentNode)
        
        // 4. Pin
        let pin = SCNSphere(radius: 0.005)
        pin.firstMaterial?.diffuse.contents = UIColor.yellow; pin.firstMaterial?.lightingModel = .constant
        let pinNode = SCNNode(geometry: pin)
        pinNode.position = SCNVector3(0, 0.07, 0)
        
        node.addChildNode(pinNode); node.addChildNode(cardNode)
        let constraint = SCNBillboardConstraint(); constraint.freeAxes = .Y; cardNode.constraints = [constraint]
    }
}

// Notifications
extension Notification.Name {
    static let arDidTapEmptySpace = Notification.Name("arDidTapEmptySpace")
    static let arDidLongPressNode = Notification.Name("arDidLongPressNode")
    static let arDidResizeNode = Notification.Name("arDidResizeNode")
    static let arNeedContentForAnchor = Notification.Name("arNeedContentForAnchor")
}
