import SwiftUI

// --- HELPER: SHAKE NOTIFICATION ---
extension NSNotification.Name {
    static let deviceDidShakeNotification = NSNotification.Name("deviceDidShakeNotification")
}

// Subclass UIWindow to capture shakes globally
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShakeNotification, object: nil)
        }
    }
}

struct ShieldView<Content: View>: View {
    @Binding var isLocked: Bool
    var content: Content
    
    @State private var isAuthenticating = false
    @State private var liquidPhase: CGFloat = 0.0
    
    // TTL Timer reference
    @State private var autoLockTask: Task<Void, Error>?
    
    init(isLocked: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isLocked = isLocked
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // 1. CONTENT LAYER
            content
                .blur(radius: (isLocked || liquidPhase > 0) ? 20 : 0)
                .opacity((isLocked || liquidPhase > 0) ? 0 : 1)
                .animation(.easeInOut(duration: 0.6), value: isLocked)
            
            // 2. SHIELD LAYER
            if isLocked || liquidPhase > 0 {
                ZStack {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width/2, y: size.height/2)
                        let maxRadius = max(size.width, size.height) * 1.2
                        
                        context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 0), with: .color(.black.opacity(0.01)))
                        context.blendMode = .destinationOut
                        
                        if liquidPhase > 0 {
                            context.fill(Path(ellipseIn: CGRect(
                                x: center.x - (maxRadius * liquidPhase),
                                y: center.y - (maxRadius * liquidPhase),
                                width: maxRadius * 2 * liquidPhase,
                                height: maxRadius * 2 * liquidPhase
                            )), with: .color(.black))
                        }
                    }
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    
                    if liquidPhase == 0 {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.1))
                                    .frame(width: 100, height: 100)
                                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                                
                                Image(systemName: isAuthenticating ? "faceid" : "lock.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white)
                                    .symbolEffect(.pulse, isActive: isAuthenticating)
                            }
                            .onTapGesture { triggerBiometrics() }
                            
                            VStack(spacing: 5) {
                                Text("Secured Memory").font(.title2).bold().foregroundStyle(.white)
                                Text("Tap to Decrypt").font(.footnote).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        // --- FEATURE 1: PANIC MODE (SHAKE TO LOCK) ---
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShakeNotification)) { _ in
            if !isLocked {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                withAnimation { isLocked = true }
            }
        }
        // --- FEATURE 2: TTL (AUTO-LOCK) ---
        .onChange(of: isLocked) {
            if !isLocked {
                // Cancel any existing timer
                autoLockTask?.cancel()
                
                // Start new 2-minute timer
                autoLockTask = Task {
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 120 Seconds
                    if !Task.isCancelled {
                        await MainActor.run {
                            withAnimation { isLocked = true }
                        }
                    }
                }
            } else {
                liquidPhase = 0
                autoLockTask?.cancel()
            }
        }
    }
    
    func triggerBiometrics() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isAuthenticating = true
        
        BiometricManager.shared.authenticate(reason: "Unlock this Insight") { success in
            isAuthenticating = false
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.8)) { liquidPhase = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    isLocked = false
                    liquidPhase = 0
                }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
