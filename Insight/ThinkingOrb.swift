import SwiftUI

enum AraState {
    case idle
    case thinking
    case speaking
}

struct ThinkingOrb: View {
    var state: AraState
    @State private var isBreathing = false
    @State private var isSpinning = false
    
    var body: some View {
        ZStack {
            // 1. Base Aura (Breathing)
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 120, height: 120)
                .scaleEffect(isBreathing ? 1.2 : 0.8)
                .blur(radius: 20)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isBreathing)
            
            // 2. Core (Solid)
            Circle()
                .fill(color)
                .frame(width: 70, height: 70)
                .shadow(color: color, radius: 15)
            
            // 3. Rings (Spinning when thinking)
            if state == .thinking {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
            }
        }
        .onAppear {
            isBreathing = true // Start breathing immediately
        }
        .onChange(of: state) {
            if state == .thinking { isSpinning = true }
            else { isSpinning = false }
        }
    }
    
    var color: Color {
        switch state {
        case .idle: return .blue
        case .thinking: return .purple
        case .speaking: return .orange // Gold
        }
    }
}
