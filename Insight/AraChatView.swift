import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Updated Model to support Citations
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    var citation: InsightItem? = nil
}

struct AraChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [InsightItem]
    
    @State private var ara = AraEngine()
    @State private var userInput = ""
    @State private var messages: [ChatMessage] = []
    @State private var showDocPicker = false
    
    // Logic States
    @State private var showNewNoteSheet = false
    @State private var newNoteTitle = ""
    
    // Animation States
    @Namespace private var bottomID
    @FocusState private var isInputFocused: Bool
    
    // RIPPLE EFFECT STATE
    @State private var rippleStart = CGPoint.zero
    @State private var isRippleExpanding = false
    
    var body: some View {
        ZStack {
            // 1. BACKGROUND
            Color(hex: "0f172a").ignoresSafeArea()
            
            // 2. MAIN CONTENT
            VStack(spacing: 0) {
                // --- HEADER ---
                HStack {
                    Spacer()
                    // Reset Button with GeometryReader
                    GeometryReader { geo in
                        Button(action: {
                            let frame = geo.frame(in: .global)
                            rippleStart = CGPoint(x: frame.midX, y: frame.midY)
                            triggerResetAnimation()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .padding(.trailing, 20)
                }
                .padding(.top, 10)
                .zIndex(10)
                
                // --- AVATAR ---
                ZStack {
                    if ara.state == .thinking {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                AngularGradient(colors: [.purple, .blue, .clear], center: .center),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 140, height: 140)
                            .rotationEffect(.degrees(360))
                            .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: ara.state)
                    }
                    
                    ThinkingOrb(state: ara.state)
                        .frame(height: 120)
                }
                .padding(.vertical, 20)
                .onTapGesture { isInputFocused = false }
                
                // --- FOCUS TAG ---
                if ara.isFocusMode {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill").foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ara.focusDocumentName).font(.caption).fontWeight(.medium).foregroundStyle(.white).lineLimit(1)
                            Text(ara.docStatus).font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        Divider().frame(height: 12).background(.white.opacity(0.3))
                        Button(action: { lightHaptic(); ara.exitFocusMode() }) {
                            Image(systemName: "xmark").font(.caption2).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(12).glassEffect(cornerRadius: 20).padding(.bottom, 10)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // --- CHAT SCROLL ---
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { msg in
                                ChatBubble(msg: msg)
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                            
                            // Ghost Text (Typing)
                            if ara.state == .thinking || (!ara.currentStream.isEmpty && ara.state != .idle) {
                                HStack(alignment: .bottom, spacing: 8) {
                                    if ara.currentStream.isEmpty {
                                        TypingIndicator()
                                    } else {
                                        Text(LocalizedStringKey(ara.currentStream))
                                            .padding(12)
                                            .glassEffect(cornerRadius: 18, corners: [.topRight, .bottomLeft, .bottomRight])
                                            .foregroundStyle(.white)
                                    }
                                    Spacer()
                                }
                                .id(bottomID)
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: ara.currentStream) { _ in withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) } }
                    .onChange(of: messages.count) { _ in withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) } }
                    .onTapGesture { isInputFocused = false }
                }
                
                // --- INPUT BAR ---
                HStack(spacing: 12) {
                    Button(action: { mediumHaptic(); showDocPicker = true }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 20)).foregroundStyle(.blue.gradient)
                            .padding(10).background(.white.opacity(0.05)).clipShape(Circle())
                    }
                    
                    TextField("Ask ARA...", text: $userInput)
                        .focused($isInputFocused)
                        .padding(12)
                        .background(Capsule().fill(.white.opacity(0.05)).stroke(.white.opacity(0.1), lineWidth: 1))
                        .foregroundStyle(.white)
                        .tint(.blue)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue.gradient)
                            .font(.system(size: 38))
                            .shadow(color: .blue.opacity(0.4), radius: 8)
                            .scaleEffect(userInput.isEmpty ? 0.8 : 1.0)
                            .opacity(userInput.isEmpty ? 0.5 : 1.0)
                            .animation(.spring(), value: userInput.isEmpty)
                    }
                    .disabled(userInput.isEmpty)
                }
                .padding(.horizontal).padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedCorner(radius: 25, corners: [.topLeft, .topRight]))
            }
            .blur(radius: isRippleExpanding ? 10 : 0)
            
            // 3. LIQUID RESET RIPPLE (Top Layer)
            if isRippleExpanding {
                ZStack {
                    Circle().stroke(AngularGradient(colors: [.blue.opacity(0.9), .purple.opacity(0.8), .cyan.opacity(0.6), .clear], center: .center), lineWidth: 6)
                        .frame(width: 120, height: 120).scaleEffect(18).position(rippleStart).blur(radius: 1).blendMode(.plusLighter)
                    Circle().fill(.ultraThinMaterial).frame(width: 140, height: 140).scaleEffect(14).position(rippleStart).blur(radius: 6).opacity(0.85)
                    Circle().fill(RadialGradient(colors: [.blue.opacity(0.35), .purple.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 600))
                        .frame(width: 200, height: 200).scaleEffect(12).position(rippleStart).blendMode(.screen)
                }
                .ignoresSafeArea().transition(.opacity).zIndex(100)
            }
        }
        .fileImporter(isPresented: $showDocPicker, allowedContentTypes: [.pdf]) { result in
            if let url = try? result.get(), url.startAccessingSecurityScopedResource() {
                heavyHaptic(); withAnimation { ara.loadPDF(url: url) }
            }
        }
        .sheet(isPresented: $showNewNoteSheet) {
            TextInputView(text: $newNoteTitle) { }
        }
        .onChange(of: ara.pendingAction) {
            switch ara.pendingAction {
            case .createNote(let title): self.newNoteTitle = title; self.showNewNoteSheet = true
            case .none, .enableFocusMode: break
            }
        }
    }
    
    // MARK: - Logic
    func triggerResetAnimation() {
        heavyHaptic()
        withAnimation(.easeIn(duration: 0.4)) { isRippleExpanding = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { messages = []; ara.exitFocusMode() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(.easeOut(duration: 0.4)) { isRippleExpanding = false } }
    }
    
    func sendMessage() {
        guard !userInput.isEmpty else { return }
        mediumHaptic()
        let q = userInput
        withAnimation(.spring()) { messages.append(ChatMessage(text: q, isUser: true)); userInput = "" }
        
        // FIX: Capture citation in callback
        ara.ask(query: q, allItems: allItems) { finalAnswer, citation in
            withAnimation(.spring()) {
                self.messages.append(ChatMessage(text: finalAnswer, isUser: false, citation: citation))
            }
            lightHaptic()
        }
    }
    
    func lightHaptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    func mediumHaptic() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func heavyHaptic() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}

// Components
struct ChatBubble: View {
    let msg: ChatMessage
    var body: some View {
        VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 8) {
                if msg.isUser { Spacer() }
                Text(LocalizedStringKey(msg.text))
                    .font(.body).lineSpacing(4).padding(14)
                    .background(msg.isUser ? LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .glassStyle(isUser: msg.isUser)
                    .foregroundStyle(.white)
                    .cornerRadius(18, corners: msg.isUser ? [.topLeft, .bottomLeft, .topRight] : [.topRight, .bottomLeft, .bottomRight])
                    .frame(maxWidth: 280, alignment: msg.isUser ? .trailing : .leading)
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                if !msg.isUser { Spacer() }
            }
            if let citation = msg.citation {
                NavigationLink(destination: InsightDetailView(item: citation)) {
                    HStack {
                        Image(systemName: "link").foregroundStyle(.blue)
                        Text("Source: \(citation.title ?? "Note")").font(.caption).bold().foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.gray)
                    }
                    .padding(10).background(Color.black.opacity(0.3)).cornerRadius(10).frame(maxWidth: 200)
                }
                .padding(.leading, msg.isUser ? 0 : 5)
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var showDots = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle().fill(.white.opacity(0.6)).frame(width: 6, height: 6).scaleEffect(showDots ? 1 : 0.5).opacity(showDots ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: showDots)
            }
        }.padding(12).glassEffect(cornerRadius: 18, corners: [.topRight, .bottomLeft, .bottomRight]).onAppear { showDots = true }
    }
}

// Action Enum Equatable
extension AraAction {
    static func == (lhs: AraAction, rhs: AraAction) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none), (.enableFocusMode, .enableFocusMode): return true
        case (.createNote(let t1), .createNote(let t2)): return t1 == t2
        default: return false
        }
    }
}

// Extensions
extension View {
    func glassEffect(cornerRadius: CGFloat = 15, corners: UIRectCorner = .allCorners) -> some View {
        self.background(.ultraThinMaterial).clipShape(RoundedCorner(radius: cornerRadius, corners: corners))
            .overlay(RoundedCorner(radius: cornerRadius, corners: corners).stroke(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 5)
    }
    @ViewBuilder func glassStyle(isUser: Bool) -> some View {
        if isUser { self.overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.2), lineWidth: 1)) }
        else { self.background(.ultraThinMaterial).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1), lineWidth: 1)) }
    }
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View { clipShape(RoundedCorner(radius: radius, corners: corners)) }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity; var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
