import SwiftUI

// 1. The Glass Container
// This acts as the "lens" that warps the content behind it.
struct LiquidGlass: ViewModifier {
    var cornerRadius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial) // The "Frosted" effect
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.6), // Top-left highlight
                                .white.opacity(0.1),
                                .clear,
                                .black.opacity(0.1), // Bottom-right shadow
                                .black.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .cornerRadius(cornerRadius)
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 10)
    }
}

// 2. The "Fluid" Background
// This goes BEHIND the glass to make it look like liquid is moving.
struct FluidBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Deep Ocean / Ink Color Base
            Color(hex: "0f172a").ignoresSafeArea() // Dark Blue-Black
            
            // Moving Orbs
            Circle()
                .fill(Color(hex: "3b82f6").opacity(0.4)) // Blue
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animate ? -100 : 100, y: animate ? -50 : 50)
                .animation(
                    Animation.easeInOut(duration: 7).repeatForever(autoreverses: true),
                    value: animate
                )
            
            Circle()
                .fill(Color(hex: "8b5cf6").opacity(0.4)) // Purple
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animate ? 100 : -100, y: animate ? 100 : -100)
                .animation(
                    Animation.easeInOut(duration: 7).repeatForever(autoreverses: true),
                    value: animate
                )
        }
        .onAppear {
            animate.toggle()
        }
    }
}

// Helper for Hex Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Easy extension to use it
extension View {
    func liquidGlass(cornerRadius: CGFloat = 20) -> some View {
        self.modifier(LiquidGlass(cornerRadius: cornerRadius))
    }
}
