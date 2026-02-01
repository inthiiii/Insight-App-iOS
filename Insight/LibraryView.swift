import SwiftUI
import SwiftData
import MapKit

struct LibraryView: View {
    @Query(sort: \InsightItem.dateCreated, order: .reverse) private var items: [InsightItem]
    @Environment(\.modelContext) private var modelContext
    
    @State private var isMapView = false
    @State private var showSentiment = false // <--- FIXED: Default OFF
    @State private var isSelectionMode = false
    @State private var selectedItems = Set<UUID>()
    @State private var selectedCategory: String? = nil
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var categories: [String] {
        let all = Set(items.compactMap { $0.category })
        return Array(all).sorted()
    }
    
    var filteredItems: [InsightItem] {
        if let category = selectedCategory { return items.filter { $0.category == category } }
        return items
    }
    
    var body: some View {
        ZStack {
            Color(hex: "0f172a").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Category Filter
                if !isMapView {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            CategoryPill(name: "All", isSelected: selectedCategory == nil) { withAnimation { selectedCategory = nil } }
                            ForEach(categories, id: \.self) { cat in
                                CategoryPill(name: cat, isSelected: selectedCategory == cat) { withAnimation { selectedCategory = cat } }
                            }
                        }
                        .padding()
                    }
                    .background(.white.opacity(0.05))
                }
                
                // Content
                if isMapView {
                    Map(position: $cameraPosition) {
                        ForEach(filteredItems) { item in
                            if let lat = item.latitude, let long = item.longitude {
                                Annotation(item.title ?? "Note", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: long)) {
                                    NavigationLink(destination: InsightDetailView(item: item)) {
                                        Image(systemName: iconFor(type: item.type))
                                            .padding(8)
                                            .background(SentimentManager.shared.colorForScore(item.sentimentScore))
                                            .clipShape(Circle())
                                            .foregroundStyle(.white)
                                            .shadow(radius: 5)
                                    }
                                }
                            }
                        }
                    }
                    .mapStyle(.hybrid(elevation: .realistic))
                } else {
                    if filteredItems.isEmpty {
                        ContentUnavailableView("No Items", systemImage: "tray").frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(filteredItems) { item in
                                    if isSelectionMode {
                                        InsightCard(item: item, isSelected: selectedItems.contains(item.id), isSelectionMode: true, showSentiment: showSentiment)
                                            .onTapGesture {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                if selectedItems.contains(item.id) { selectedItems.remove(item.id) }
                                                else { selectedItems.insert(item.id) }
                                            }
                                    } else {
                                        NavigationLink(destination: InsightDetailView(item: item)) {
                                            InsightCard(item: item, isSelected: false, isSelectionMode: false, showSentiment: showSentiment)
                                        }
                                        .simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .light).impactOccurred() })
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.5)) { showSentiment.toggle() }
                }) {
                    Image(systemName: showSentiment ? "sparkles" : "sparkles.rectangle.stack")
                        .symbolEffect(.bounce, value: showSentiment)
                        .foregroundStyle(showSentiment ? .yellow : .gray)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { isMapView.toggle() }
                }) {
                    Image(systemName: isMapView ? "square.grid.2x2" : "map")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelectionMode ? "Done" : "Select") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { isSelectionMode.toggle(); selectedItems.removeAll() }
                }
            }
            if isSelectionMode && !selectedItems.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) { deleteSelected() } label: {
                        Label("Delete (\(selectedItems.count))", systemImage: "trash").foregroundStyle(.red)
                    }
                }
            }
        }
    }
    
    func deleteSelected() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation {
            for id in selectedItems {
                if let item = items.first(where: { $0.id == id }) { modelContext.delete(item) }
            }
            selectedItems.removeAll(); isSelectionMode = false
        }
    }
    
    func iconFor(type: InsightType) -> String {
        switch type {
        case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill"
        }
    }
}

// Subview: The Card
struct InsightCard: View {
    let item: InsightItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let showSentiment: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon & Selection
            HStack {
                // If locked, show Lock Icon instead of file type
                Image(systemName: item.isLocked ? "lock.fill" : iconFor(type: item.type))
                    .foregroundStyle(item.isLocked ? .red : .white)
                
                Spacer()
                
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .blue : .gray).font(.title2)
                }
            }
            
            // --- STEALTH PREVIEW LOGIC ---
            if item.isLocked {
                // LOCKED STATE UI
                // 1. Show the REAL Title so user knows what it is
                Text(item.title?.isEmpty == false ? item.title! : "Encrypted Note")
                    .font(.headline)
                    .foregroundStyle(.white) // Brighter visibility
                    .lineLimit(1)
                
                // 2. Hide Content
                Text("Content hidden via biometric shield.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .italic()
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blur(radius: 2) // Slight blur for effect
            } else {
                // UNLOCKED STATE UI (Normal)
                if let title = item.title, !title.isEmpty {
                    Text(title).font(.headline).foregroundStyle(.white).lineLimit(1)
                }
                
                Text(item.content)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // -----------------------------
            
            Spacer()
            
            // Location Badge (Only show if unlocked to prevent leaking location context)
            if !item.isLocked, let loc = item.locationLabel {
                HStack(spacing: 4) { Image(systemName: "location.fill").font(.caption2); Text(loc).font(.caption2) }
                .foregroundStyle(.white.opacity(0.6)).padding(.bottom, 2)
            }
            
            // Category & Date
            HStack {
                // Hide Category if locked (optional privacy), or keep it visible if you prefer:
                // Currently hiding category if locked to be safe.
                if let cat = item.category, !item.isLocked {
                    Text(cat).font(.caption2).bold().padding(4).background(.blue.opacity(0.5)).cornerRadius(4).foregroundStyle(.white)
                }
                Spacer()
                Text(item.dateCreated.formatted(date: .numeric, time: .omitted)).font(.caption2).foregroundStyle(.gray)
            }
        }
        .padding()
        .frame(height: 170)
        .background(.ultraThinMaterial)
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(
                    isSelected ? .blue : (showSentiment && !item.isLocked ? SentimentManager.shared.colorForScore(item.sentimentScore).opacity(0.6) : .white.opacity(0.1)),
                    lineWidth: isSelected ? 3 : (showSentiment ? 2 : 1)
                )
                .shadow(color: (showSentiment && !item.isLocked) ? SentimentManager.shared.colorForScore(item.sentimentScore).opacity(0.5) : .clear, radius: showSentiment ? 8 : 0)
        )
    }
    
    func iconFor(type: InsightType) -> String {
        switch type {
        case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill"
        }
    }
}

// Subview: Category Pill
struct CategoryPill: View {
    let name: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Text(name).font(.caption).bold().padding(.horizontal, 16).padding(.vertical, 8)
            .background(isSelected ? .blue : .white.opacity(0.1)).foregroundStyle(.white).clipShape(Capsule())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            }
    }
}
