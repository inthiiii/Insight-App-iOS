import SwiftUI
import SwiftData
import Combine

struct NeuralWebView: View {
    @Query private var allItems: [InsightItem]
    @StateObject private var simulation = GraphSimulation()
    @State private var selectedItem: InsightItem?
    
    // Timer for 60 FPS physics
    let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color(hex: "0f172a").ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // LINES
                    Canvas { context, size in
                        for (indexA, indexB) in simulation.links {
                            if indexA < simulation.nodes.count && indexB < simulation.nodes.count {
                                let start = simulation.nodes[indexA].position
                                let end = simulation.nodes[indexB].position
                                var path = Path(); path.move(to: start); path.addLine(to: end)
                                context.stroke(path, with: .color(.blue.opacity(0.5)), lineWidth: 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .id(simulation.tickCount)
                    
                    // NODES
                    ForEach(simulation.nodes) { node in
                        VStack(spacing: 0) {
                            ZStack {
                                Circle().fill(colorFor(type: node.type).gradient)
                                    .shadow(color: colorFor(type: node.type).opacity(0.8), radius: 10)
                                    .frame(width: 50, height: 50)
                                Image(systemName: iconFor(type: node.type)).font(.caption).foregroundStyle(.white)
                            }
                            Text(node.text).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).shadow(radius: 4).lineLimit(1).frame(width: 80).padding(.top, 4).allowsHitTesting(false)
                        }
                        .position(node.position)
                        .gesture(
                            DragGesture()
                                .onChanged { value in simulation.onDragStart(id: node.id); simulation.onDragChange(id: node.id, location: value.location) }
                                .onEnded { _ in simulation.onDragEnd(id: node.id) }
                        )
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedItem = node.item
                        }
                    }
                }
                .onAppear { if simulation.nodes.isEmpty { simulation.loadData(items: allItems, in: geo.size) } }
                .onReceive(timer) { _ in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    simulation.tick(center: center)
                }
            }
            
            // CONTROLS & INFO
            VStack {
                // Scatter Button (Top Right)
                HStack {
                    Spacer()
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            simulation.toggleScatter()
                        }
                    }) {
                        HStack {
                            Image(systemName: simulation.isScattered ? "arrow.in.circle.fill" : "arrow.up.left.and.arrow.down.right.circle.fill")
                            Text(simulation.isScattered ? "Gather" : "Scatter")
                        }
                        .font(.caption).bold()
                        .padding(8).background(.white.opacity(0.1)).foregroundStyle(.white).clipShape(Capsule())
                        .scaleEffect(simulation.isScattered ? 1.1 : 1.0) // Animation
                    }
                    .padding()
                }
                
                Spacer()
                
                // INFO CARD (Bottom Center - Above Dock)
                HStack {
                    Image(systemName: "circle.grid.hex.fill").foregroundStyle(.purple)
                    Text("Nodes: \(simulation.nodes.count)")
                    Text("|").foregroundStyle(.gray)
                    Image(systemName: "arrow.triangle.pull").foregroundStyle(.blue)
                    Text("Links: \(simulation.links.count)")
                }
                .font(.caption).bold().foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1), lineWidth: 1))
                .padding(.bottom, 100) // Clear the Dock
            }
        }
        .navigationTitle("Neural Web").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in NavigationStack { InsightDetailView(item: item) } }
    }
    
    func colorFor(type: InsightType) -> Color {
        switch type {
        case .audio: return .red; case .image: return .purple; case .note: return .blue; case .pdf: return .orange
        }
    }
    
    func iconFor(type: InsightType) -> String {
        switch type {
        case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill"
        }
    }
}

// GRAPH SIMULATION (Keep existing logic)
class GraphNode: Identifiable {
    let id: UUID; let item: InsightItem; let text: String; let type: InsightType
    var position: CGPoint; var velocity: CGPoint = .zero; var isDragging: Bool = false
    init(item: InsightItem, position: CGPoint) {
        self.id = item.id; self.item = item; self.text = item.content; self.type = item.type; self.position = position
    }
}

class GraphSimulation: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var links: [(Int, Int)] = []
    @Published var tickCount: Int = 0
    @Published var isScattered: Bool = false
    
    let repulsion: CGFloat = 800.0
    let springLength: CGFloat = 150.0
    let springStrength: CGFloat = 0.05
    let centerGravity: CGFloat = 0.005
    let friction: CGFloat = 0.90
    
    func toggleScatter() { isScattered.toggle() }
    
    func loadData(items: [InsightItem], in size: CGSize) {
        self.nodes = items.map { item in
            GraphNode(item: item, position: CGPoint(x: CGFloat.random(in: size.width * 0.2 ... size.width * 0.8), y: CGFloat.random(in: size.height * 0.2 ... size.height * 0.8)))
        }
        var newLinks: [(Int, Int)] = []
        for (indexA, item) in items.enumerated() {
            guard let itemLinks = item.outgoingLinks else { continue }
            for link in itemLinks {
                if let indexB = nodes.firstIndex(where: { $0.id == link.targetID }) {
                    if indexA < indexB { newLinks.append((indexA, indexB)) }
                }
            }
        }
        self.links = newLinks
    }
    
    func tick(center: CGPoint) {
        tickCount += 1
        for i in 0..<nodes.count {
            if nodes[i].isDragging { continue }
            var force = CGPoint.zero
            let activeRepulsion = isScattered ? repulsion * 5 : repulsion
            for j in 0..<nodes.count {
                if i == j { continue }
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let dist = sqrt(dx*dx + dy*dy)
                let safeDist = max(dist, 60.0)
                let repulse = activeRepulsion / (safeDist * safeDist)
                force.x += (dx / safeDist) * repulse
                force.y += (dy / safeDist) * repulse
            }
            if !isScattered {
                let dx = center.x - nodes[i].position.x
                let dy = center.y - nodes[i].position.y
                force.x += dx * centerGravity
                force.y += dy * centerGravity
            }
            nodes[i].velocity.x += force.x
            nodes[i].velocity.y += force.y
        }
        let activeSpringStrength = isScattered ? springStrength * 0.1 : springStrength
        for (indexA, indexB) in links {
            let nodeA = nodes[indexA]; let nodeB = nodes[indexB]
            let dx = nodeB.position.x - nodeA.position.x
            let dy = nodeB.position.y - nodeA.position.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist == 0 { continue }
            let displacement = dist - springLength
            let force = displacement * activeSpringStrength
            let fx = (dx / dist) * force; let fy = (dy / dist) * force
            if !nodeA.isDragging { nodes[indexA].velocity.x += fx; nodes[indexA].velocity.y += fy }
            if !nodeB.isDragging { nodes[indexB].velocity.x -= fx; nodes[indexB].velocity.y -= fy }
        }
        for i in 0..<nodes.count {
            if nodes[i].isDragging { continue }
            nodes[i].velocity.x *= friction
            nodes[i].velocity.y *= friction
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y
        }
    }
    
    func onDragStart(id: UUID) { if let idx = nodes.firstIndex(where: { $0.id == id }) { nodes[idx].isDragging = true; nodes[idx].velocity = .zero } }
    func onDragChange(id: UUID, location: CGPoint) { if let idx = nodes.firstIndex(where: { $0.id == id }) { nodes[idx].position = location } }
    func onDragEnd(id: UUID) { if let idx = nodes.firstIndex(where: { $0.id == id }) { nodes[idx].isDragging = false } }
}
