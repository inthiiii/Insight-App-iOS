import SwiftUI

struct FusionView: View {
    let selectedItems: [InsightItem]
    var onDismiss: () -> Void
    var onSave: (String) -> Void
    
    // State
    @State private var orbPositions: [CGPoint] = [] // Current Position
    @State private var orbAnchors: [CGPoint] = []   // Orbital "Home" Position
    @State private var isFusing = false
    @State private var showResult = false
    @State private var resultText = ""
    @State private var rotation: Double = 0
    @State private var breathingPhase: Bool = false // For floating animation
    
    // Physics Constants
    let orbSize: CGFloat = 65
    let vortexRadius: CGFloat = 100 // Visual size of center
    let eventHorizon: CGFloat = 110 // Distance where gravity sucks it in
    
    init(items: [InsightItem], onDismiss: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.selectedItems = items
        self.onDismiss = onDismiss
        self.onSave = onSave
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. COSMIC BACKGROUND
                RadialGradient(colors: [Color(hex: "1a0b2e"), .black], center: .center, startRadius: 10, endRadius: 500)
                    .ignoresSafeArea()
                
                // Stars/Dust overlay (Simple dots)
                Canvas { context, size in
                    for _ in 0..<50 {
                        let x = Double.random(in: 0...size.width)
                        let y = Double.random(in: 0...size.height)
                        let r = Double.random(in: 1...2)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.3)))
                    }
                }.ignoresSafeArea()
                
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                
                // 2. THE VORTEX (Gravity Well)
                if !showResult {
                    ZStack {
                        // Spinning Rings
                        ForEach(0..<4) { i in
                            Circle()
                                .strokeBorder(
                                    AngularGradient(colors: [.cyan.opacity(0.5), .purple.opacity(0.5), .clear], center: .center),
                                    lineWidth: isFusing ? 4 : 1
                                )
                                .frame(width: 120 + CGFloat(i * 35), height: 120 + CGFloat(i * 35))
                                .rotationEffect(.degrees(rotation * (i % 2 == 0 ? 1 : -0.8)))
                                .opacity(0.5)
                        }
                        
                        // The Core
                        Circle()
                            .fill(RadialGradient(colors: [.white, .purple.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 60))
                            .frame(width: 100, height: 100)
                            .blur(radius: 10)
                            .scaleEffect(breathingPhase ? 1.1 : 1.0)
                        
                        Text(isFusing ? "Fusing..." : "Fusion Core")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(2)
                    }
                    .position(center)
                    .onAppear {
                        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { rotation = 360 }
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { breathingPhase.toggle() }
                        setupOrbs(center: center)
                    }
                }
                
                // 3. FLOATING ORBS (Notes)
                if !showResult && !orbPositions.isEmpty {
                    ForEach(Array(selectedItems.enumerated()), id: \.element.id) { index, item in
                        OrbView(text: item.title ?? "Note")
                            .frame(width: orbSize, height: orbSize)
                            .position(orbPositions[index])
                            // Floating Animation (Zero-G Bobbing)
                            .offset(y: breathingPhase ? -5 : 5)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true).delay(Double(index) * 0.3), value: breathingPhase)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // 1:1 Tracking during drag
                                        orbPositions[index] = value.location
                                    }
                                    .onEnded { value in
                                        handleRelease(at: value.location, center: center, index: index)
                                    }
                            )
                    }
                }
                
                // 4. RESULT CARD (Golden Ticket)
                if showResult {
                    VStack(spacing: 25) {
                        // Icon
                        ZStack {
                            Circle().fill(.yellow.opacity(0.2)).frame(width: 80, height: 80)
                            Image(systemName: "atom").font(.system(size: 40)).foregroundStyle(.yellow)
                        }
                        .padding(.top, 20)
                        
                        Text("Insight Synthesized")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        
                        ScrollView {
                            Text(resultText)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(6)
                                .padding()
                        }
                        .frame(height: 300)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                        
                        HStack(spacing: 20) {
                            Button("Discard") { withAnimation { onDismiss() } }
                                .foregroundStyle(.white.opacity(0.6))
                            
                            Button(action: { onSave(resultText); onDismiss() }) {
                                Text("Save to Library")
                                    .bold()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.yellow)
                                    .foregroundStyle(.black)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(25)
                    .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.1), lineWidth: 1))
                    .padding(30)
                    .position(center)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                
                // Close Button
                if !showResult && !isFusing {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onDismiss) {
                                Image(systemName: "xmark").font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding()
                        }
                        Spacer()
                    }
                }
            }
        }
    }
    
    // --- PHYSICS LOGIC ---
    
    func setupOrbs(center: CGPoint) {
        let count = selectedItems.count
        let orbitRadius: CGFloat = 140
        var positions: [CGPoint] = []
        var anchors: [CGPoint] = []
        
        for i in 0..<count {
            // Distribute in a circle
            let angle = (Double(i) / Double(count)) * 2 * .pi - (.pi / 2) // Start top
            let x = center.x + orbitRadius * CGFloat(cos(angle))
            let y = center.y + orbitRadius * CGFloat(sin(angle))
            let point = CGPoint(x: x, y: y)
            positions.append(point)
            anchors.append(point)
        }
        self.orbPositions = positions
        self.orbAnchors = anchors
    }
    
    func handleRelease(at location: CGPoint, center: CGPoint, index: Int) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let dist = sqrt(dx*dx + dy*dy)
        
        // PHYSICS CHECK
        if dist < eventHorizon {
            // Case A: Event Horizon Crossed -> SUCK IN (Black Hole Gravity)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                orbPositions[index] = center
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            checkFusion(center: center)
        } else {
            // Case B: Orbit Gravity -> SNAP BACK (Spring)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                orbPositions[index] = orbAnchors[index]
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    func checkFusion(center: CGPoint) {
        // Are all orbs at the center?
        let allCentered = orbPositions.allSatisfy { pos in
            let dx = pos.x - center.x
            let dy = pos.y - center.y
            return sqrt(dx*dx + dy*dy) < 5 // Tolerance
        }
        
        if allCentered {
            startFusionProcess()
        }
    }
    
    func startFusionProcess() {
        isFusing = true
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning) // Build up tension
        
        // Simulating AI Processing
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            let result = AraEngine().synthesize(items: selectedItems)
            DispatchQueue.main.async {
                self.resultText = result
                generator.notificationOccurred(.success) // Release tension
                withAnimation {
                    self.showResult = true
                }
            }
        }
    }
}

// --- BEAUTIFUL ORB COMPONENT ---
struct OrbView: View {
    let text: String
    
    var body: some View {
        ZStack {
            // Glow Aura
            Circle()
                .fill(
                    RadialGradient(colors: [.blue.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 40)
                )
                .frame(width: 80, height: 80)
                .blur(radius: 5)
            
            // Core Sphere
            Circle()
                .fill(
                    LinearGradient(colors: [Color(hex: "4facfe"), Color(hex: "00f2fe")], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Circle().stroke(.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 5)
            
            // Text Label
            Text(text)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 50)
                .shadow(radius: 2)
        }
    }
}
