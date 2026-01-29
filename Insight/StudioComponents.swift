import SwiftUI
import SwiftData

// --- 1. STUDIO ZONE (FIXED UI) ---
struct StudioZone: View {
    @Bindable var zone: InsightZone
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Frosted Glass Background
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(radius: 5)
            
            // Border
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: zone.colorHex), lineWidth: 3)
            
            // Title Input
            TextField("Zone Name", text: $zone.title)
                .font(.headline)
                .foregroundStyle(.white)
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(10, corners: [.topLeft, .bottomRight])
        }
        .frame(width: zone.width, height: zone.height)
    }
}

// --- 2. CONNECTIONS LAYER (Same as before) ---
struct StudioConnectionsLayer: View {
    let items: [InsightItem]
    var linkStart: CGPoint?
    var linkEnd: CGPoint?
    
    var body: some View {
        Canvas { context, size in
            for item in items {
                guard let startX = item.canvasX, let startY = item.canvasY else { continue }
                let start = CGPoint(x: startX, y: startY)
                if let links = item.outgoingLinks {
                    for link in links {
                        if let target = items.first(where: { $0.id == link.targetID }),
                           let endX = target.canvasX, let endY = target.canvasY {
                            let end = CGPoint(x: endX, y: endY)
                            var path = Path(); path.move(to: start)
                            let midX = (start.x + end.x) / 2; let midY = (start.y + end.y) / 2 + 50
                            path.addQuadCurve(to: end, control: CGPoint(x: midX, y: midY))
                            context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 2)
                        }
                    }
                }
            }
            // Ghost Line
            if let s = linkStart, let e = linkEnd {
                var path = Path(); path.move(to: s); path.addLine(to: e)
                context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 2, dash: [5]))
            }
        }
        .allowsHitTesting(false)
    }
}

// --- 3. STUDIO CARD (FIXED - With Double Tap Menu) ---
struct StudioCard: View {
    let item: InsightItem
    var onDelete: () -> Void // Callback for delete
    @State private var showMenu = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconFor(type: item.type)).font(.caption)
                Text(item.title ?? "Note").font(.caption).bold().lineLimit(1)
                Spacer()
                
                // Emoji Tag Display
                if let emoji = item.emojiTag { Text(emoji).font(.caption) }
            }
            .foregroundStyle(.white)
            
            Text(item.content).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).lineLimit(4).multilineTextAlignment(.leading)
        }
        .padding(12).frame(width: 160, height: 110)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        // DOUBLE TAP FOR MENU
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showMenu = true
        }
        .sheet(isPresented: $showMenu) {
            StudioCardMenu(item: item, onDelete: onDelete)
                .presentationDetents([.fraction(0.3)])
        }
    }
    
    func iconFor(type: InsightType) -> String {
        switch type { case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill" }
    }
}

// New Helper Menu for Card
struct StudioCardMenu: View {
    let item: InsightItem
    var onDelete: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Options for \(item.title ?? "Note")").font(.headline)
            HStack(spacing: 20) {
                Button("⭐") { item.emojiTag = "⭐"; dismiss() }.font(.largeTitle)
                Button("🔥") { item.emojiTag = "🔥"; dismiss() }.font(.largeTitle)
                Button("✅") { item.emojiTag = "✅"; dismiss() }.font(.largeTitle)
                Button("❌") { item.emojiTag = nil; dismiss() }.font(.largeTitle)
            }
            Button("Remove from Board", role: .destructive) { onDelete(); dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.fraction(0.3)])
    }
}

// --- 4. BACKGROUND GRID (Unchanged) ---
struct StudioBackground: View {
    var pan: CGSize; var zoom: CGFloat
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let spacing: CGFloat = 40 * zoom
                let rows = Int(geo.size.height / spacing) + 2; let cols = Int(geo.size.width / spacing) + 2
                let offsetX = pan.width.remainder(dividingBy: spacing); let offsetY = pan.height.remainder(dividingBy: spacing)
                for r in -1...rows { for c in -1...cols {
                    let x = CGFloat(c) * spacing + offsetX; let y = CGFloat(r) * spacing + offsetY
                    path.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                }}
            }.fill(Color.white.opacity(0.15))
        }
    }
}

// --- 5. STUDIO ADD SHEET (Unchanged) ---
struct StudioAddSheet: View {
    let items: [InsightItem]
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    var filteredItems: [InsightItem] { if searchText.isEmpty { return items }; return items.filter { $0.content.localizedCaseInsensitiveContains(searchText) } }
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredItems) { item in
                    HStack {
                        Image(systemName: iconFor(type: item.type)).foregroundStyle(.blue)
                        VStack(alignment: .leading) { Text(item.title ?? "Untitled").font(.headline); Text(item.content).font(.caption).lineLimit(1).foregroundStyle(.gray) }
                        Spacer()
                        Button(action: { toggleItem(item) }) {
                            if item.canvasX != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2) }
                            else { Image(systemName: "plus.circle").foregroundStyle(.blue).font(.title2) }
                        }
                    }
                }
            }
            .searchable(text: $searchText).navigationTitle("Manage Board").toolbar { Button("Done") { dismiss() } }
        }
    }
    func toggleItem(_ item: InsightItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            if item.canvasX != nil { item.canvasX = nil; item.canvasY = nil }
            else { item.canvasX = CGFloat.random(in: -50...50) + UIScreen.main.bounds.midX; item.canvasY = CGFloat.random(in: -50...50) + UIScreen.main.bounds.midY }
        }
    }
    func iconFor(type: InsightType) -> String { switch type { case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill" } }
}
