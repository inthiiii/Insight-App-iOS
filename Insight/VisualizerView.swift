import SwiftUI
import SwiftData

struct VisualizerView: View {
    let results: [(item: InsightItem, score: Double)]
    // Closure to trigger synthesis back in parent
    var onSynthesize: ([InsightItem]) -> Void
    
    // --- SCROLL ENGINE ---
    @State private var visualIndex: CGFloat = 0.0
    @State private var dragOffset: CGFloat = 0.0
    
    // CONFIGURATION
    let spacing: CGFloat = 180.0
    let cardHeight: CGFloat = 240
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. ATMOSPHERE
                RadialGradient(colors: [Color(hex: "1e293b"), .black], center: .center, startRadius: 100, endRadius: 600)
                    .ignoresSafeArea()
                
                // 2. 3D CARD STACK
                ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                    let i = CGFloat(index)
                    
                    // --- MATH & TRANSFORMS ---
                    let currentScrollIndex = visualIndex - (dragOffset / spacing)
                    let dist = i - currentScrollIndex
                    
                    // Visual Props
                    let scale = max(0.7, 1.0 - abs(dist) * 0.15)
                    let opacity = max(0.0, 1.0 - abs(dist) * 0.3)
                    let yOffset = dist * spacing
                    let xOffset = sin(dist * 0.5) * 40
                    let rotation = Double(dist) * -5.0
                    let zIndex = 100.0 - abs(dist) * 10.0
                    
                    VisualizerCard(item: result.item, score: result.score, isFocused: abs(dist) < 0.5)
                        .frame(width: 320, height: cardHeight)
                        .scaleEffect(scale)
                        .offset(x: xOffset, y: yOffset)
                        .rotation3DEffect(.degrees(rotation), axis: (x: 1, y: 0, z: 0))
                        .opacity(opacity)
                        .zIndex(zIndex)
                        .blur(radius: abs(dist) * 3)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                visualIndex = i
                                dragOffset = 0
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            
            // 3. GESTURES
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let velocity = value.predictedEndTranslation.height
                        let snapOffset = -(value.translation.height + velocity * 0.2) / spacing
                        let newIndex = round(visualIndex + snapOffset)
                        let clampedIndex = max(0, min(CGFloat(results.count - 1), newIndex))
                        
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            visualIndex = clampedIndex
                            dragOffset = 0
                        }
                    }
            )
            
            // 4. FLOATING ACTION BUTTON (Centered)
            VStack {
                Spacer()
                Button(action: {
                    let currentIndex = Int(round(visualIndex))
                    let start = max(0, currentIndex)
                    let end = min(results.count, start + 3)
                    if start < end {
                        let subset = Array(results[start..<end].map { $0.item })
                        onSynthesize(subset)
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Synthesize Focused")
                    }
                    .font(.headline)
                    .padding()
                    .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .purple.opacity(0.5), radius: 10, x: 0, y: 5)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity) // Enforce horizontal center alignment
        }
    }
}

// --- VISUALIZER CARD (Unchanged) ---
struct VisualizerCard: View {
    let item: InsightItem
    let score: Double
    let isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconFor(type: item.type))
                    .font(.title3)
                    .foregroundStyle(isFocused ? .yellow : .white.opacity(0.7))
                    .symbolEffect(.bounce, value: isFocused)
                
                Spacer()
                
                Text("\(Int(score * 100))%")
                    .font(.caption).bold()
                    .padding(6)
                    .background(score > 0.6 ? Color.green.opacity(0.2) : Color.yellow.opacity(0.2))
                    .foregroundStyle(score > 0.6 ? .green : .yellow)
                    .cornerRadius(8)
            }
            
            Text(item.title ?? "Untitled Note")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            
            Text(item.content)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            HStack {
                Text(item.dateCreated.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .background(isFocused ? Color.blue.opacity(0.15) : Color.black.opacity(0.2))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    LinearGradient(
                        colors: isFocused ? [.yellow.opacity(0.5), .white.opacity(0.1)] : [.white.opacity(0.2), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .shadow(color: isFocused ? .blue.opacity(0.3) : .black.opacity(0.2), radius: 15, x: 0, y: 10)
    }
    
    func iconFor(type: InsightType) -> String {
        switch type { case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill" }
    }
}
