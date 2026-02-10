import SwiftUI
import SwiftData
import Combine
import CoreMotion

struct NeuralWebView: View {
    @Query private var allItems: [InsightItem]
    @StateObject private var simulation = GraphSimulation()
    @State private var selectedItem: InsightItem?
    
    // --- CAMERA STATE ---
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var isZoomedIn = false
    
    // --- SPOTLIGHT STATE ---
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // --- NAVIGATOR STATE (Pathfinding) ---
    @State private var pathSelection: [UUID] = []
    @State private var activePath: [UUID] = []
    @State private var isNavigatorMode = false
    @State private var showExplainSheet = false // AI Explanation
    
    // --- HISTORY STATE (Time Travel) ---
    @State private var historyValue: Double = 1.0
    @State private var showHistorySlider = false
    
    // --- PHYSICS ---
    let motionManager = CMMotionManager()
    @State private var gravityOffset: CGSize = .zero
    let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    @State private var pulsePhase: CGFloat = 0.0 // For Ghost Links
    
    var body: some View {
        ZStack {
            Color(hex: "0f172a").ignoresSafeArea()
            
            // Background Reset
            Color.clear.contentShape(Rectangle())
                .onTapGesture {
                    resetCamera()
                    isSearchFocused = false
                    pathSelection = []
                    activePath = []
                    withAnimation { showHistorySlider = false }
                }
            
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    
                    // --- LAYER A: LINKS ---
                    Canvas { context, size in
                        // 1. REAL LINKS
                        for (indexA, indexB) in simulation.links {
                            if indexA < simulation.nodes.count && indexB < simulation.nodes.count {
                                let nodeA = simulation.nodes[indexA]
                                let nodeB = simulation.nodes[indexB]
                                
                                if !historyFilter(nodeA) || !historyFilter(nodeB) { continue }
                                
                                let inPath = activePath.contains(nodeA.id) && activePath.contains(nodeB.id)
                                let isDimmed = (shouldDim(nodeA) || shouldDim(nodeB)) && !inPath
                                let color: Color = inPath ? .yellow : .blue
                                let lineWidth: CGFloat = inPath ? 4 : 2
                                let opacity = isDimmed ? 0.05 : (inPath ? 1.0 : 0.4)
                                
                                var path = Path()
                                path.move(to: nodeA.position)
                                path.addLine(to: nodeB.position)
                                context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: lineWidth)
                            }
                        }
                        
                        // 2. GHOST LINKS (AI Predictions)
                        // Dotted lines for potential connections
                        if !isNavigatorMode {
                            for (indexA, indexB) in simulation.ghostLinks {
                                if indexA < simulation.nodes.count && indexB < simulation.nodes.count {
                                    let nodeA = simulation.nodes[indexA]
                                    let nodeB = simulation.nodes[indexB]
                                    
                                    if historyFilter(nodeA) && historyFilter(nodeB) {
                                        var path = Path()
                                        path.move(to: nodeA.position)
                                        path.addLine(to: nodeB.position)
                                        context.stroke(path, with: .color(.white.opacity(0.1 + (pulsePhase * 0.1))), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    }
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    
                    // --- LAYER B: NODES ---
                    ForEach(simulation.nodes) { node in
                        if historyFilter(node) {
                            NodeView(node: node, isDimmed: shouldDim(node), isSelected: pathSelection.contains(node.id), inPath: activePath.contains(node.id))
                                .position(node.position)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            simulation.onDragStart(id: node.id)
                                            simulation.onDragChange(id: node.id, location: value.location)
                                        }
                                        .onEnded { _ in simulation.onDragEnd(id: node.id) }
                                )
                                .onTapGesture { handleTap(node, in: geo.size) }
                                .transition(.scale)
                        }
                    }
                }
                .scaleEffect(zoomScale)
                .offset(panOffset + gravityOffset)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: zoomScale)
                .animation(.linear(duration: 0.1), value: gravityOffset)
                
                .onAppear {
                    if simulation.nodes.isEmpty { simulation.loadData(items: allItems, in: geo.size) }
                    startGyro()
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsePhase = 1.0 }
                }
                .onReceive(timer) { _ in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    simulation.tick(center: center, size: geo.size)
                }
            }
            
            // --- LAYER C: HUD ---
            VStack {
                // 1. Search
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.gray)
                        TextField("Search Neural Web...", text: $searchText)
                            .focused($isSearchFocused)
                            .foregroundStyle(.white)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray) }
                        }
                    }
                    .padding(10).background(.ultraThinMaterial).clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
                    .padding(.top, 50).padding(.horizontal)
                }
                
                Spacer()
                
                // 2. NAVIGATOR HINT & AI EXPLAINER
                if isNavigatorMode {
                    VStack {
                        if !activePath.isEmpty {
                            Button(action: { showExplainSheet = true }) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Ask ARA to Explain Path")
                                }
                                .font(.caption.bold())
                                .padding(10)
                                .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(radius: 5)
                            }
                            .padding(.bottom, 5)
                        }
                        
                        Text(pathSelection.count < 2 ? (pathSelection.isEmpty ? "Select Start Node" : "Select End Node") : (activePath.isEmpty ? "No Connection Found" : "Path Found"))
                            .font(.subheadline).bold().foregroundStyle(activePath.isEmpty && pathSelection.count == 2 ? .white : .black)
                            .padding(.vertical, 8).padding(.horizontal, 16)
                            .background(activePath.isEmpty && pathSelection.count == 2 ? Color.red : Color.yellow)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 10)
                    .transition(.scale)
                }
                
                // 3. CONTROLS ROW
                HStack(alignment: .bottom) {
                    // Left: Stats
                    HStack(spacing: 12) {
                        HStack(spacing: 4) { Image(systemName: "circle.grid.hex.fill").foregroundStyle(.purple); Text("\(simulation.nodes.count)") }
                        Divider().frame(height: 12).background(.white.opacity(0.3))
                        HStack(spacing: 4) { Image(systemName: "arrow.triangle.pull").foregroundStyle(.blue); Text("\(simulation.links.count)") }
                    }
                    .font(.caption.bold()).foregroundStyle(.white).padding(10).background(.ultraThinMaterial).clipShape(Capsule())
                    
                    Spacer()
                    
                    // Center: Time Travel (Collapsible) - FIXED ERROR HERE
                    HStack {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring()) { showHistorySlider.toggle() }
                        }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2).foregroundStyle(historyValue < 1.0 ? .purple : .white)
                                .padding(10).background(.ultraThinMaterial).clipShape(Circle())
                        }
                        
                        if showHistorySlider {
                            Slider(value: $historyValue, in: 0...1)
                                .tint(.purple)
                                .frame(width: 120)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(5)
                    // FIX: Explicitly cast to AnyShapeStyle to satisfy compiler
                    .background(showHistorySlider ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Right: Toggles
                    VStack(spacing: 12) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation { isNavigatorMode.toggle(); pathSelection = []; activePath = [] }
                        }) {
                            Image(systemName: isNavigatorMode ? "map.fill" : "map")
                                .font(.title3).foregroundStyle(isNavigatorMode ? .yellow : .white)
                                .frame(width: 44, height: 44).background(.ultraThinMaterial).clipShape(Circle())
                        }
                        
                        Button(action: { withAnimation { simulation.toggleClustering() } }) {
                            Image(systemName: simulation.isClustered ? "folder.fill" : "circle.hexagongrid.fill")
                                .font(.title3).foregroundStyle(.white).frame(width: 44, height: 44)
                                .background(simulation.isClustered ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.ultraThinMaterial)).clipShape(Circle())
                        }
                        
                        Button(action: { withAnimation { simulation.toggleScatter() } }) {
                            Image(systemName: simulation.isScattered ? "arrow.in.circle.fill" : "arrow.up.left.and.arrow.down.right.circle.fill")
                                .font(.title3).foregroundStyle(.white).frame(width: 44, height: 44)
                                .background(simulation.isScattered ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.ultraThinMaterial)).clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal).padding(.bottom, 20)
            }
        }
        .navigationTitle("").toolbar(.hidden)
        .sheet(item: $selectedItem) { item in NavigationStack { InsightDetailView(item: item) } }
        // AI EXPLANATION SHEET
        .sheet(isPresented: $showExplainSheet) {
            let pathItems = allItems.filter { activePath.contains($0.id) }
            let explanation = AraEngine().explainConnection(items: pathItems)
            
            VStack(spacing: 20) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.purple)
                Text("Connection Insight").font(.title2).bold()
                ScrollView {
                    Text(explanation).font(.body).padding()
                }
            }
            .padding()
            .presentationDetents([.medium])
        }
        .onDisappear { motionManager.stopDeviceMotionUpdates() }
    }
    
    // --- LOGIC HELPERS ---
    
    func historyFilter(_ node: GraphNode) -> Bool {
        guard let index = simulation.nodes.firstIndex(where: { $0.id == node.id }) else { return false }
        return index <= Int(Double(simulation.nodes.count) * historyValue)
    }
    
    func startGyro() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.02
            motionManager.startDeviceMotionUpdates(to: .main) { data, _ in
                if let data = data {
                    withAnimation(.linear(duration: 0.1)) {
                        gravityOffset = CGSize(width: data.attitude.roll * 50, height: data.attitude.pitch * 50)
                    }
                }
            }
        }
    }
    
    func shouldDim(_ node: GraphNode) -> Bool {
        if !activePath.isEmpty { return !activePath.contains(node.id) }
        guard !searchText.isEmpty else { return false }
        return !node.text.localizedCaseInsensitiveContains(searchText)
    }
    
    func handleTap(_ node: GraphNode, in size: CGSize) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        if isNavigatorMode {
            if pathSelection.contains(node.id) {
                pathSelection.removeAll(where: { $0 == node.id })
                activePath = []
            } else {
                if pathSelection.count < 2 {
                    pathSelection.append(node.id)
                    if pathSelection.count == 2 {
                        let path = BrainManager.shared.findShortestPath(from: pathSelection[0], to: pathSelection[1], allItems: allItems)
                        withAnimation { activePath = path }
                        if !path.isEmpty { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                        else { UINotificationFeedbackGenerator().notificationOccurred(.error) }
                    }
                } else {
                    pathSelection = [node.id]
                    activePath = []
                }
            }
            return
        }
        
        if isZoomedIn { selectedItem = node.item }
        else {
            let center = CGPoint(x: size.width/2, y: size.height/2)
            let target = node.position
            isZoomedIn = true; zoomScale = 2.0
            panOffset = CGSize(width: (center.x - target.x) * 2, height: (center.y - target.y) * 2)
        }
    }
    
    func resetCamera() { withAnimation { zoomScale = 1.0; panOffset = .zero; isZoomedIn = false } }
}

// --- SUBVIEWS ---

struct NodeView: View {
    let node: GraphNode
    let isDimmed: Bool
    let isSelected: Bool
    let inPath: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if isSelected || inPath {
                    Circle().stroke(inPath ? Color.yellow : Color.cyan, lineWidth: 3).frame(width: 60, height: 60).shadow(color: inPath ? .yellow : .cyan, radius: 10)
                }
                if !isDimmed { Circle().fill(colorFor(type: node.type).opacity(0.3)).frame(width: 70, height: 70).blur(radius: 10) }
                Circle().fill(colorFor(type: node.type).gradient).shadow(color: colorFor(type: node.type).opacity(0.8), radius: 8).frame(width: 50, height: 50).overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                Image(systemName: iconFor(type: node.type)).font(.caption).foregroundStyle(.white)
            }
            Text(node.text).font(.system(size: 10, weight: .bold)).foregroundStyle(inPath ? .yellow : .white).shadow(color: .black, radius: 2).lineLimit(1).frame(width: 100).padding(.top, 4).opacity(isDimmed ? 0 : 1)
        }
        .opacity(isDimmed ? 0.1 : 1.0).scaleEffect(isDimmed ? 0.8 : 1.0).animation(.spring(), value: isDimmed)
    }
    func colorFor(type: InsightType) -> Color { switch type { case .audio: return .red; case .image: return .purple; case .note: return .blue; case .pdf: return .orange } }
    func iconFor(type: InsightType) -> String { switch type { case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill" } }
}

// --- PHYSICS ENGINE ---
class GraphNode: Identifiable {
    let id: UUID; let item: InsightItem; let text: String; let type: InsightType; let category: String
    var position: CGPoint; var velocity: CGPoint = .zero; var isDragging: Bool = false
    init(item: InsightItem, position: CGPoint) { self.id = item.id; self.item = item; self.text = item.title ?? item.content; self.type = item.type; self.category = item.category ?? "Uncategorized"; self.position = position }
}

class GraphSimulation: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var links: [(Int, Int)] = []
    @Published var ghostLinks: [(Int, Int)] = [] // <--- GHOST LINKS
    @Published var tickCount: Int = 0
    @Published var isScattered: Bool = false; @Published var isClustered: Bool = false
    
    let repulsion: CGFloat = 800.0; let springLength: CGFloat = 150.0; let springStrength: CGFloat = 0.05; let centerGravity: CGFloat = 0.005; let clusterGravity: CGFloat = 0.02; let friction: CGFloat = 0.90
    var categoryCenters: [String: CGPoint] = [:]
    
    func toggleScatter() { isScattered.toggle(); isClustered = false }
    func toggleClustering() { isClustered.toggle(); isScattered = false }
    
    func loadData(items: [InsightItem], in size: CGSize) {
        self.nodes = items.map { item in GraphNode(item: item, position: CGPoint(x: CGFloat.random(in: size.width * 0.2 ... size.width * 0.8), y: CGFloat.random(in: size.height * 0.2 ... size.height * 0.8))) }
        
        let categories = Array(Set(items.compactMap { $0.category ?? "Uncategorized" })).sorted()
        let center = CGPoint(x: size.width/2, y: size.height/2); let radius = min(size.width, size.height) * 0.35
        for (i, cat) in categories.enumerated() { let angle = (Double(i) / Double(categories.count)) * 2 * .pi; categoryCenters[cat] = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle))) }
        
        // Build Links & Ghost Links
        var newLinks: [(Int, Int)] = []
        var newGhosts: [(Int, Int)] = []
        
        for (indexA, itemA) in items.enumerated() {
            // Existing Links
            if let itemLinks = itemA.outgoingLinks {
                for link in itemLinks {
                    if let indexB = nodes.firstIndex(where: { $0.id == link.targetID }) {
                        if indexA < indexB { newLinks.append((indexA, indexB)) }
                    }
                }
            }
            
            // Ghost Links (AI Predictions)
            // Look for high similarity but NO link
            if let embeddingA = itemA.embedding {
                for (indexB, itemB) in items.enumerated() {
                    if indexA < indexB, let embeddingB = itemB.embedding {
                        // Check if already linked
                        let alreadyLinked = itemA.outgoingLinks?.contains(where: { $0.targetID == itemB.id }) ?? false
                        if !alreadyLinked {
                            // Calculate sim manually since we are outside BrainManager
                            // Simplified: Just use category match as a heuristic for ghost link visual
                            // Or use BrainManager shared if possible. For simplicity here:
                            // If same category and not linked -> Ghost Link
                            if itemA.category == itemB.category && itemA.category != nil {
                                newGhosts.append((indexA, indexB))
                            }
                        }
                    }
                }
            }
        }
        self.links = newLinks
        self.ghostLinks = newGhosts
    }
    
    func tick(center: CGPoint, size: CGSize) {
        tickCount += 1
        for i in 0..<nodes.count {
            if nodes[i].isDragging { continue }
            var force = CGPoint.zero
            let activeRepulsion = isScattered ? repulsion * 5 : repulsion
            for j in 0..<nodes.count { if i == j { continue }; let dx = nodes[i].position.x - nodes[j].position.x; let dy = nodes[i].position.y - nodes[j].position.y; let dist = sqrt(dx*dx + dy*dy); let safeDist = max(dist, 60.0); let repulse = activeRepulsion / (safeDist * safeDist); force.x += (dx / safeDist) * repulse; force.y += (dy / safeDist) * repulse }
            if isClustered { let cat = nodes[i].category; let target = categoryCenters[cat] ?? center; let dx = target.x - nodes[i].position.x; let dy = target.y - nodes[i].position.y; force.x += dx * clusterGravity; force.y += dy * clusterGravity }
            else if !isScattered { let dx = center.x - nodes[i].position.x; let dy = center.y - nodes[i].position.y; force.x += dx * centerGravity; force.y += dy * centerGravity }
            nodes[i].velocity.x += force.x; nodes[i].velocity.y += force.y
        }
        let activeSpringStrength = isClustered ? springStrength * 0.2 : (isScattered ? springStrength * 0.1 : springStrength)
        for (indexA, indexB) in links { let nodeA = nodes[indexA]; let nodeB = nodes[indexB]; let dx = nodeB.position.x - nodeA.position.x; let dy = nodeB.position.y - nodeA.position.y; let dist = sqrt(dx*dx + dy*dy); if dist == 0 { continue }; let displacement = dist - springLength; let force = displacement * activeSpringStrength; let fx = (dx / dist) * force; let fy = (dy / dist) * force; if !nodeA.isDragging { nodes[indexA].velocity.x += fx; nodes[indexA].velocity.y += fy }; if !nodeB.isDragging { nodes[indexB].velocity.x -= fx; nodes[indexB].velocity.y -= fy } }
        for i in 0..<nodes.count { if nodes[i].isDragging { continue }; nodes[i].velocity.x *= friction; nodes[i].velocity.y *= friction; nodes[i].position.x += nodes[i].velocity.x; nodes[i].position.y += nodes[i].velocity.y }
    }
    func onDragStart(id: UUID) { if let idx = nodes.firstIndex(where: { $0.id == id }) { nodes[idx].isDragging = true; nodes[idx].velocity = .zero } }
    func onDragChange(id: UUID, location: CGPoint) { if let idx = nodes.firstIndex(where: { $0.id == id }) { nodes[idx].position = location } }
    func onDragEnd(id: UUID) { if let idx = nodes.firstIndex(where: { $0.id == id }) { nodes[idx].isDragging = false } }
}
