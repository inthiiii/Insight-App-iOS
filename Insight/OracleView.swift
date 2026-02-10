import SwiftUI
import SwiftData

struct OracleView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [InsightItem]
    
    @State private var query = ""
    @State private var results: [(item: InsightItem, score: Double)] = []
    @State private var showSuccessAlert = false
    @FocusState private var isFocused: Bool
    
    // --- VISUALIZER STATE ---
    @State private var isVisualizerMode = false
    
    var body: some View {
        ZStack {
            Color(hex: "0f172a").ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Oracle Search")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Spacer()
                    
                    // MODE TOGGLE BUTTON
                    if !results.isEmpty {
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { isVisualizerMode.toggle() }
                        }) {
                            Image(systemName: isVisualizerMode ? "list.bullet" : "cube.transparent")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.top).padding(.horizontal)
                
                // Search Field (Hidden in Visualizer Mode for immersion)
                if !isVisualizerMode {
                    searchField.transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // LIST MODE SYNTHESIZE BUTTON
                if !results.isEmpty && !isVisualizerMode {
                    Button(action: { runSynthesis(items: results.map { $0.item }) }) {
                        HStack { Image(systemName: "sparkles"); Text("Synthesize All \(results.count)") }
                        .font(.caption).padding(8)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        .foregroundStyle(.white).cornerRadius(20)
                    }
                    .padding(.bottom, 5)
                }
                
                // RESULTS AREA
                if results.isEmpty && !query.isEmpty {
                    Text("No matching knowledge found.").foregroundStyle(.gray).padding(.top, 50)
                    Spacer()
                } else {
                    // --- SWITCHER LOGIC ---
                    if isVisualizerMode {
                        // 3D SPIRAL VIEW
                        VisualizerView(results: results, onSynthesize: { subset in
                            // Handle synthesis from 3D view
                            runSynthesis(items: subset)
                        })
                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                        .zIndex(1)
                        // Tap background to exit visualizer
                        .onTapGesture(count: 2) { withAnimation { isVisualizerMode = false } }
                    } else {
                        // STANDARD LIST VIEW
                        ScrollView {
                            VStack(spacing: 15) {
                                ForEach(results, id: \.item.id) { result in
                                    NavigationLink(destination: InsightDetailView(item: result.item)) {
                                        resultRow(result: result)
                                    }
                                }
                            }
                            .padding()
                        }
                        .transition(.move(edge: .leading))
                        .zIndex(0)
                    }
                }
            }
        }
        .alert("Briefing Created", isPresented: $showSuccessAlert) { Button("OK", role: .cancel) { } } message: { Text("A new summary note has been added to your Library.") }
        .onAppear { if results.isEmpty { isFocused = true } }
    }
    
    // Helper: Run Synthesis
    func runSynthesis(items: [InsightItem]) {
        guard !items.isEmpty else { return }
        let summary = SynthesisManager.shared.synthesize(items: items)
        let newItem = InsightItem(type: .note, content: summary, title: "Oracle Briefing: \(query)", category: "Oracle")
        modelContext.insert(newItem)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showSuccessAlert = true
    }
    
    var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.gray)
            TextField("Ask your knowledge base...", text: $query)
                .foregroundStyle(.white)
                .focused($isFocused)
                .onSubmit { performSearch() }
                .submitLabel(.search)
            if !query.isEmpty {
                Button(action: { query = ""; results = [] }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                }
            }
        }
        .padding()
        .background(.white.opacity(0.1)).cornerRadius(15).padding(.horizontal)
    }
    
    // Paste them here to ensure the file is complete if you copy-paste
    func resultRow(result: (item: InsightItem, score: Double)) -> some View {
        HStack(alignment: .center, spacing: 15) {
            VStack {
                Text("\(Int(result.score * 100))%").font(.caption).bold().foregroundStyle(result.score > 0.6 ? .green : .yellow)
                Image(systemName: iconFor(type: result.item.type)).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: 50).padding(.vertical, 8).background(.white.opacity(0.05)).cornerRadius(8)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.item.content).font(.system(size: 16)).foregroundStyle(.white.opacity(0.9)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(result.item.localFileName ?? "Written Note").font(.caption2).foregroundStyle(.blue.opacity(0.8)).lineLimit(1)
                    Text("• " + result.item.dateCreated.formatted(date: .numeric, time: .omitted)).font(.caption2).foregroundStyle(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding().frame(height: 90).background(.white.opacity(0.05)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))
    }
    func performSearch() { let matches = BrainManager.shared.search(query: query, in: allItems); withAnimation { results = matches } }
    func iconFor(type: InsightType) -> String { switch type { case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "pencil"; case .pdf: return "doc.text.fill" } }
}
