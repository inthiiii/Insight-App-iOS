import SwiftUI
import SwiftData
import PencilKit

// Extension for Vector Arithmetic
extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
    static func += (lhs: inout CGSize, rhs: CGSize) {
        lhs = lhs + rhs
    }
}

struct StudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss // For Back Button
    
    @Query private var allItems: [InsightItem]
    @Query private var allZones: [InsightZone]
    @Query private var drawings: [InsightDrawing]
    
    // --- CANVAS STATE ---
    @State private var panOffset: CGSize = .zero
    @State private var zoom: CGFloat = 1.0
    
    // --- GESTURE STATE ---
    @State private var tempPanOffset: CGSize = .zero
    @State private var tempZoom: CGFloat = 1.0
    
    // --- INTERACTION MODES ---
    // Removed isDrawMode as per request
    @State private var isLinkingMode = false // "The Loom"
    @State private var linkStartID: UUID?
    @State private var linkCurrentPoint: CGPoint?
    
    // --- ITEM DRAG STATE ---
    @State private var draggingItemID: UUID?
    @State private var draggingItemOffset: CGSize = .zero
    @State private var draggingZoneID: UUID?
    
    // --- SNAP LINES ---
    @State private var snapLineX: CGFloat?
    @State private var snapLineY: CGFloat?
    
    // --- UI STATE ---
    @State private var showAddSheet = false
    // Removed showZoneAlert as per request
    
    // NEW: Board Description
    @AppStorage("studioTitle") private var boardTitle = "Untitled Project"
    @AppStorage("studioDesc") private var boardDesc = "Tap to add description..."
    
    // PencilKit Canvas
    @State private var canvasView = PKCanvasView()
    
    var canvasItems: [InsightItem] { allItems.filter { $0.canvasX != nil } }
    
    // Computed property for smooth panning
    var currentPan: CGSize {
        return panOffset + tempPanOffset
    }
    
    var body: some View {
        ZStack {
            // 1. INFINITE BACKGROUND
            Color(hex: "0f172a").ignoresSafeArea()
            StudioBackground(pan: currentPan, zoom: zoom * tempZoom)
            
            // 2. THE WORLD (Scalable)
            ZStack {
                
                // A. ZONES LAYER (Fixed Visibility)
                ForEach(allZones) { zone in
                    StudioZone(zone: zone)
                        .position(
                            x: zone.x + (draggingZoneID == zone.id ? draggingItemOffset.width : 0),
                            y: zone.y + (draggingZoneID == zone.id ? draggingItemOffset.height : 0)
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if draggingZoneID == nil { draggingZoneID = zone.id }
                                    draggingItemOffset = CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom)
                                }
                                .onEnded { value in
                                    let dx = value.translation.width / zoom
                                    let dy = value.translation.height / zoom
                                    zone.x += dx
                                    zone.y += dy
                                    
                                    // Move children items inside the zone
                                    for child in canvasItems.filter({ $0.zoneID == zone.id }) {
                                        child.canvasX = (child.canvasX ?? 0) + dx
                                        child.canvasY = (child.canvasY ?? 0) + dy
                                    }
                                    
                                    draggingZoneID = nil; draggingItemOffset = .zero
                                    try? modelContext.save()
                                }
                        )
                        .onTapGesture(count: 2) { // Double tap to delete zone
                            modelContext.delete(zone)
                        }
                }
                
                // B. PENCILKIT LAYER (Viewing Only - Editing Removed per request)
                if let data = drawings.first?.data, let image = try? PKDrawing(data: data).image(from: CGRect(x: 0, y: 0, width: 5000, height: 5000), scale: 1.0) {
                    Image(uiImage: image)
                        .frame(width: 5000, height: 5000)
                        .scaleEffect(zoom * tempZoom)
                        .offset(currentPan)
                        .allowsHitTesting(false)
                }
                
                // C. CONNECTIONS
                StudioConnectionsLayer(items: canvasItems, linkStart: linkStartID != nil ? getPos(linkStartID!) : nil, linkEnd: linkCurrentPoint)
                
                // D. CARDS
                ForEach(canvasItems) { item in
                    StudioCard(item: item, onDelete: {
                        // Handle Delete from Menu
                        withAnimation { item.canvasX = nil; item.canvasY = nil }
                    })
                    .position(
                        x: (item.canvasX ?? 0) + (draggingItemID == item.id ? draggingItemOffset.width : 0),
                        y: (item.canvasY ?? 0) + (draggingItemID == item.id ? draggingItemOffset.height : 0)
                    )
                    .gesture(
                        // DRAG GESTURE
                        DragGesture()
                            .onChanged { value in
                                if isLinkingMode { return }
                                if draggingItemID == nil { draggingItemID = item.id }
                                let dx = value.translation.width / zoom
                                let dy = value.translation.height / zoom
                                draggingItemOffset = CGSize(width: dx, height: dy)
                                checkSnap(currentX: (item.canvasX ?? 0) + dx, currentY: (item.canvasY ?? 0) + dy, currentID: item.id)
                            }
                            .onEnded { value in
                                if isLinkingMode { return }
                                item.canvasX = (item.canvasX ?? 0) + (value.translation.width / zoom)
                                item.canvasY = (item.canvasY ?? 0) + (value.translation.height / zoom)
                                checkZoneDrop(item: item)
                                draggingItemID = nil; draggingItemOffset = .zero; snapLineX = nil; snapLineY = nil
                                try? modelContext.save()
                            }
                    )
                    .simultaneousGesture(
                        // LOOM GESTURE (Long Press Drag)
                        LongPressGesture(minimumDuration: 0.3)
                            .onEnded { _ in
                                isLinkingMode = true
                                linkStartID = item.id
                                linkCurrentPoint = CGPoint(x: item.canvasX ?? 0, y: item.canvasY ?? 0)
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            }
                            .sequenced(before: DragGesture(minimumDistance: 0).onChanged { value in
                                guard isLinkingMode else { return }
                                let startPos = getPos(item.id)
                                linkCurrentPoint = CGPoint(
                                    x: startPos.x + (value.translation.width / zoom),
                                    y: startPos.y + (value.translation.height / zoom)
                                )
                            }.onEnded { value in
                                guard isLinkingMode else { return }
                                let dropPoint = linkCurrentPoint ?? .zero
                                if let target = canvasItems.first(where: {
                                    $0.id != item.id &&
                                    hypot((($0.canvasX ?? 0) - dropPoint.x), (($0.canvasY ?? 0) - dropPoint.y)) < 80
                                }) {
                                    createLink(from: item, to: target)
                                }
                                isLinkingMode = false; linkStartID = nil; linkCurrentPoint = nil
                            })
                    )
                }
                
                // SNAP GUIDES
                if let sx = snapLineX {
                    Path { p in p.move(to: CGPoint(x: sx, y: -5000)); p.addLine(to: CGPoint(x: sx, y: 5000)) }
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1, dash: [5]))
                }
                if let sy = snapLineY {
                    Path { p in p.move(to: CGPoint(x: -5000, y: sy)); p.addLine(to: CGPoint(x: 5000, y: sy)) }
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1, dash: [5]))
                }
            }
            .scaleEffect(zoom * tempZoom)
            .offset(currentPan)
            .gesture(
                SimultaneousGesture(
                    DragGesture().onChanged { val in if !isLinkingMode { tempPanOffset = val.translation } }
                        .onEnded { val in if !isLinkingMode { panOffset += val.translation; tempPanOffset = .zero } },
                    MagnificationGesture().onChanged { val in tempZoom = val }.onEnded { val in zoom *= val; tempZoom = 1.0 }
                )
            )
            
            // 3. HUD
            VStack {
                // TOP CONTROLS
                HStack(alignment: .top) {
                    
                    // 1. BACK BUTTON (New)
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2).bold()
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    // 2. TEXT FIELDS (Expanded)
                    VStack(alignment: .leading) {
                        TextField("Project Title", text: $boardTitle)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                        
                        // Expanded Description
                        TextField("Description", text: $boardDesc, axis: .vertical)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(3...10) // Allows growth
                    }
                    .padding(.leading, 10)
                    
                    Spacer()
                    
                    // 3. RECENTER BUTTON (Kept)
                    Button(action: recenterCanvas) {
                        Image(systemName: "scope")
                            .font(.title2).foregroundStyle(.white)
                            .padding(10).background(.ultraThinMaterial).clipShape(Circle())
                    }
                }
                .padding(.top, 60).padding(.horizontal)
                
                Spacer()
                
                // BOTTOM CONTROLS
                HStack {
                    Spacer()
                    // ADD BUTTON
                    Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); showAddSheet = true }) {
                        Image(systemName: "plus").font(.title).foregroundStyle(.white).frame(width: 60, height: 60).background(Color.blue).clipShape(Circle()).shadow(color: .blue.opacity(0.5), radius: 10, y: 5)
                    }
                    .padding(.bottom, 50).padding(.trailing, 20)
                }
            }
        }
        .navigationTitle("").toolbar(.hidden)
        .sheet(isPresented: $showAddSheet) { StudioAddSheet(items: allItems).presentationDetents([.medium, .large]) }
        .onAppear {
            if let saved = drawings.first?.data {
                try? canvasView.drawing = PKDrawing(data: saved)
            }
            // Auto-Center on Open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                recenterCanvas()
            }
        }
    }
    
    // --- LOGIC ---
    
    func getPos(_ id: UUID) -> CGPoint {
        if let item = canvasItems.first(where: { $0.id == id }) { return CGPoint(x: item.canvasX ?? 0, y: item.canvasY ?? 0) }
        return .zero
    }
    
    func createLink(from: InsightItem, to: InsightItem) {
        if from.outgoingLinks?.contains(where: { $0.targetID == to.id }) == true { return }
        let link = InsightLink(sourceID: from.id, targetID: to.id, reason: "Manual Link", strength: 1.0)
        let backLink = InsightLink(sourceID: to.id, targetID: from.id, reason: "Manual Link", strength: 1.0)
        modelContext.insert(link); modelContext.insert(backLink)
        if from.outgoingLinks == nil { from.outgoingLinks = [] }; from.outgoingLinks?.append(link)
        if to.outgoingLinks == nil { to.outgoingLinks = [] }; to.outgoingLinks?.append(backLink)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    // (Removed addZone function)
    
    func checkZoneDrop(item: InsightItem) {
        let itemPos = CGPoint(x: item.canvasX ?? 0, y: item.canvasY ?? 0)
        for zone in allZones {
            let zRect = CGRect(x: zone.x - zone.width/2, y: zone.y - zone.height/2, width: zone.width, height: zone.height)
            if zRect.contains(itemPos) {
                if item.zoneID != zone.id { item.zoneID = zone.id; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                return
            }
        }
        item.zoneID = nil
    }
    
    func checkSnap(currentX: Double, currentY: Double, currentID: UUID) {
        let threshold: CGFloat = 10.0
        var foundX = false; var foundY = false
        for item in canvasItems {
            if item.id == currentID { continue }
            if abs(CGFloat(item.canvasX ?? 0) - CGFloat(currentX)) < threshold { snapLineX = CGFloat(item.canvasX ?? 0); UIImpactFeedbackGenerator(style: .soft).impactOccurred(); foundX = true }
            if abs(CGFloat(item.canvasY ?? 0) - CGFloat(currentY)) < threshold { snapLineY = CGFloat(item.canvasY ?? 0); UIImpactFeedbackGenerator(style: .soft).impactOccurred(); foundY = true }
        }
        if !foundX { snapLineX = nil }; if !foundY { snapLineY = nil }
    }
    
    func getScreenCenterWorldPos() -> CGPoint {
        let screenCenter = CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
        return CGPoint(
            x: (screenCenter.x - currentPan.width) / zoom,
            y: (screenCenter.y - currentPan.height) / zoom
        )
    }
    
    func recenterCanvas() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        if canvasItems.isEmpty && allZones.isEmpty {
            withAnimation { panOffset = .zero; zoom = 1.0 }
            return
        }
        
        let itemXs = canvasItems.compactMap { $0.canvasX }
        let itemYs = canvasItems.compactMap { $0.canvasY }
        let zoneXs = allZones.map { $0.x }
        let zoneYs = allZones.map { $0.y }
        
        let allXs = itemXs + zoneXs
        let allYs = itemYs + zoneYs
        
        guard let minX = allXs.min(), let maxX = allXs.max(),
              let minY = allYs.min(), let maxY = allYs.max() else {
            withAnimation { panOffset = .zero; zoom = 1.0 }
            return
        }
        
        let contentCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let screenCenter = CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            zoom = 1.0
            panOffset = CGSize(width: screenCenter.x - contentCenter.x, height: screenCenter.y - contentCenter.y)
            tempPanOffset = .zero
        }
    }
}
