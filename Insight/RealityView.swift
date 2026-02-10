import SwiftUI
import SwiftData
import NaturalLanguage
import ARKit
import SceneKit

enum RealityMode { case scanner; case spatial }

struct RealityView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [InsightItem]
    
    @State private var currentMode: RealityMode = .scanner
    @State private var foundInsight: InsightItem?
    @State private var scannedText: String = ""
    
    // Spatial State
    @ObservedObject var arManager = ARManager.shared
    @State private var selectedNoteForPinning: InsightItem?
    @State private var showPinPicker = false
    @State private var showCreateNote = false
    @State private var newNoteText = ""
    
    // Interaction State
    @State private var longPressedNodeName: String?
    @State private var showDeleteAction = false
    @State private var selectedInsightForDetail: InsightItem? // For Scanner navigation
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // --- 1. VIEWPORT ---
            if currentMode == .scanner {
                ARScannerView { text in smartMatch(text: text) }.ignoresSafeArea()
            } else {
                ARViewContainer().ignoresSafeArea()
            }
            
            // --- 2. HUD ---
            VStack {
                // Header
                HStack {
                    Text("Reality Anchor")
                        .font(.title2).bold().foregroundStyle(.white)
                    Text("BETA")
                        .font(.caption2).bold().padding(4).background(.blue).foregroundStyle(.white).cornerRadius(4)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 50)
                
                // Mode Picker
                HStack {
                    Picker("Mode", selection: $currentMode) {
                        Text("Scanner").tag(RealityMode.scanner)
                        Text("Spatial").tag(RealityMode.spatial)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .background(.ultraThinMaterial).cornerRadius(8)
                    
                    Spacer()
                    
                    if currentMode == .spatial {
                        Button(action: { showCreateNote = true }) {
                            Image(systemName: "plus").font(.title3).bold().frame(width: 40, height: 40).background(Color.green).foregroundStyle(.white).clipShape(Circle())
                        }
                        Button(action: { showPinPicker = true }) {
                            HStack {
                                Image(systemName: "pin.fill")
                                Text(selectedNoteForPinning == nil ? "Select" : "Ready")
                            }
                            .font(.caption.bold()).padding(8).background(selectedNoteForPinning == nil ? Color.gray : Color.blue).foregroundStyle(.white).clipShape(Capsule())
                        }
                        if selectedNoteForPinning != nil {
                            Button(action: { selectedNoteForPinning = nil; arManager.statusMessage = "Selection Cleared." }) {
                                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }.padding(.horizontal)
                
                // Status
                if currentMode == .spatial {
                    VStack(spacing: 4) {
                        if let selected = selectedNoteForPinning {
                            Text("Pinning: \(selected.title ?? "Note")").font(.caption).bold().foregroundStyle(.yellow)
                        }
                        Text(arManager.statusMessage).font(.caption).padding(6).background(.black.opacity(0.6)).foregroundStyle(.white).cornerRadius(5)
                    }.padding(.top)
                }
                
                Spacer()
                
                // Match Bubble (Scanner)
                if currentMode == .scanner, let insight = foundInsight {
                    matchBubble(insight: insight)
                        .onTapGesture {
                            selectedInsightForDetail = insight
                        }
                }
            }
        }
        // --- SHEETS ---
        .sheet(isPresented: $showPinPicker) { NotePickerSheet(selectedNote: $selectedNoteForPinning) }
        .sheet(item: $selectedInsightForDetail) { item in NavigationStack { InsightDetailView(item: item) } }
        .alert("New Spatial Note", isPresented: $showCreateNote) {
            TextField("Enter note...", text: $newNoteText)
            Button("Create & Select") { createAndSelectNote() }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Manage Note", isPresented: $showDeleteAction, titleVisibility: .visible) {
            Button("Remove Anchor", role: .destructive) {
                if let name = longPressedNodeName {
                    arManager.removeAnchor(name: name)
                    // Clear from DB
                    if let item = allItems.first(where: { ($0.title ?? "Note") == name }) {
                        item.arAnchorTransform = nil
                        item.arWorldMapData = nil // Don't delete WorldMap if other notes use it? Logic limitation: we assume 1 map per note for now or last saved.
                        // Actually, deleting transform is enough to hide it.
                        try? modelContext.save()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        // --- LISTENERS ---
        .onReceive(NotificationCenter.default.publisher(for: .arDidTapEmptySpace)) { notif in
            if let loc = notif.object as? CGPoint { handlePinTap(at: loc) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arDidLongPressNode)) { notif in
            if let name = notif.object as? String {
                longPressedNodeName = name
                showDeleteAction = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arDidResizeNode)) { notif in
            if let info = notif.object as? [String: Any],
               let name = info["name"] as? String,
               let scale = info["scale"] as? Float {
                // Save Scale to DB
                if let item = allItems.first(where: { ($0.title ?? "Note") == name }) {
                    item.arNodeScale = scale
                    try? modelContext.save()
                    arManager.statusMessage = "Size Saved."
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arNeedContentForAnchor)) { notif in
            // Lookup content and send back to ARManager
            if let node = notif.object as? SCNNode,
               let info = notif.userInfo,
               let name = info["name"] as? String {
                let content = allItems.first(where: { ($0.title ?? "Note") == name })?.content ?? "..."
                arManager.updateVisual(for: node, title: name, content: content)
            }
        }
        // --- LIFECYCLE ---
        .onChange(of: currentMode) {
            if currentMode == .spatial { arManager.loadInitialWorldMap(from: allItems) }
            else { arManager.pause() }
        }
        .onAppear { if currentMode == .spatial { arManager.loadInitialWorldMap(from: allItems) } }
    }
    
    // ... (Helper functions createAndSelectNote, handlePinTap, smartMatch same as before) ...
    // Re-paste helpers to ensure completion:
    func createAndSelectNote() {
        guard !newNoteText.isEmpty else { return }
        let newItem = InsightItem(type: .note, content: newNoteText, title: newNoteText, category: "Spatial")
        modelContext.insert(newItem); try? modelContext.save()
        selectedNoteForPinning = newItem
        arManager.statusMessage = "New Note Selected. Tap surface to Pin."
        newNoteText = ""
    }
    
    func handlePinTap(at location: CGPoint) {
        guard let item = selectedNoteForPinning else { arManager.statusMessage = "Select or Create a note first!"; return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        arManager.placeNote(at: location, for: item) { transformData, mapData in
            item.arAnchorTransform = transformData; item.arWorldMapData = mapData
            DispatchQueue.main.async { try? modelContext.save(); arManager.statusMessage = "Anchored." }
        }
    }
    
    func smartMatch(text: String) {
        let tokenizer = NLTokenizer(unit: .word); tokenizer.string = text
        var keywords: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in
            let w = String(text[r]); if w.count > 4 { keywords.append(w.localizedLowercase) }; return true
        }
        for k in keywords {
            if let match = allItems.first(where: { i in let c = i.content.localizedLowercase; let t = i.title?.localizedLowercase ?? ""; return c.contains(k) || t.contains(k) }) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation { self.scannedText = k; self.foundInsight = match }
                return
            }
        }
    }
    
    func matchBubble(insight: InsightItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.yellow)
                Text("Linked Memory Found").font(.caption).bold().foregroundStyle(.gray)
                Spacer()
                Button(action: { withAnimation { foundInsight = nil } }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray.opacity(0.5)) }
            }
            Divider()
            Text(insight.title ?? "Note").font(.headline).foregroundStyle(.white)
            Text(insight.content).font(.subheadline).foregroundStyle(.white.opacity(0.9)).lineLimit(3)
            HStack { Spacer(); Text("Tap to Open").font(.caption).bold().foregroundStyle(.blue) }
        }
        .padding().background(.ultraThinMaterial).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
        .padding()
    }
}

// NOTE PICKER
struct NotePickerSheet: View {
    @Query(sort: \InsightItem.dateCreated, order: .reverse) var items: [InsightItem]
    @Binding var selectedNote: InsightItem?
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List(items) { item in
                Button(action: { selectedNote = item; dismiss() }) {
                    HStack {
                        Image(systemName: "note.text")
                        Text(item.title ?? String(item.content.prefix(20))).foregroundStyle(.primary)
                    }
                }
            }.navigationTitle("Select Memory")
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView { let view = ARSCNView(); ARManager.shared.setup(view: view); return view }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
