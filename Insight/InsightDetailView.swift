import SwiftUI
import SwiftData

struct InsightDetailView: View {
    @Bindable var item: InsightItem
    @State private var detectedDate: Date?
    @State private var actionMessage = ""
    @State private var showingCategoryAlert = false
    @State private var newCategory = ""
    
    var body: some View {
        ZStack {
            Color(hex: "0f172a").ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 0. HEADER: Title & Category
                    VStack(alignment: .leading) {
                        TextField("Add Title...", text: Binding(
                            get: { item.title ?? "" },
                            set: { item.title = $0 }
                        ))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .submitLabel(.done)
                        
                        HStack {
                            // Category Tag
                            Menu {
                                Button("Work") { item.category = "Work" }
                                Button("Personal") { item.category = "Personal" }
                                Button("Vitalis Project") { item.category = "Vitalis Project" }
                                Button("Ideas") { item.category = "Ideas" }
                                Divider()
                                Button("Custom Category...") { showingCategoryAlert = true }
                                Button("Clear Category", role: .destructive) { item.category = nil }
                            } label: {
                                HStack {
                                    Image(systemName: "tag.fill")
                                    Text(item.category ?? "No Category")
                                }
                                .font(.caption).bold()
                                .padding(8)
                                .background(item.category != nil ? .blue : .white.opacity(0.1))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            
                            // LOCATION TAG (NEW)
                            if let loc = item.locationLabel {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text(loc)
                                }
                                .font(.caption).bold()
                                .padding(8)
                                .background(.white.opacity(0.1))
                                .foregroundStyle(.white.opacity(0.8))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    
                    // 1. Image
                    if let filename = item.localFileName, let img = VisionManager.loadImageFromDisk(filename: filename) {
                        Image(uiImage: img)
                            .resizable().scaledToFit().cornerRadius(15).shadow(radius: 10)
                            .frame(maxHeight: 300).frame(maxWidth: .infinity)
                    }
                    
                    // 2. Meta
                    HStack {
                        Label(item.type.rawValue.capitalized, systemImage: iconFor(type: item.type))
                            .font(.caption).padding(8).background(.white.opacity(0.1)).clipShape(Capsule())
                        Text(item.dateCreated.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.gray)
                        Spacer()
                    }
                    
                    // 3. Content
                    Text("Content").font(.headline).foregroundStyle(.white.opacity(0.7))
                    
                    TextEditor(text: $item.content)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white)
                        .font(.body)
                        .frame(minHeight: 150)
                        .padding()
                        .background(.white.opacity(0.05))
                        .cornerRadius(10)
                    
                    Divider().background(.gray)
                    
                    // 4. Smart Actions
                    if let date = detectedDate {
                        smartActionView(date: date)
                    }
                    
                    // 5. Connections
                    if let links = item.outgoingLinks, !links.isEmpty {
                        Text("Linked Knowledge").font(.headline).foregroundStyle(.blue)
                        
                        ForEach(links, id: \.targetID) { link in
                            LinkDestination(id: link.targetID, linkInfo: link)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Category", isPresented: $showingCategoryAlert) {
            TextField("Category Name", text: $newCategory)
            Button("Add") { item.category = newCategory; newCategory = "" }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear { self.detectedDate = SmartActionManager.shared.detectDates(in: item.content) }
        .onChange(of: item.content) { self.detectedDate = SmartActionManager.shared.detectDates(in: item.content) }
    }
    
    // Helper for Smart Action
    func smartActionView(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smart Action Detected").font(.caption).textCase(.uppercase).foregroundStyle(.blue)
            HStack {
                VStack(alignment: .leading) {
                    Text("Schedule Event").font(.headline).foregroundStyle(.white)
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.gray)
                }
                Spacer()
                Button(action: {
                    SmartActionManager.shared.addEvent(title: item.content, date: date) { success, error in
                        actionMessage = success ? "Added to Calendar!" : "Error: \(error ?? "Unknown")"
                        if success { detectedDate = nil }
                    }
                }) {
                    Label("Add", systemImage: "calendar.badge.plus")
                        .padding(.horizontal, 15).padding(.vertical, 8)
                        .background(.blue).foregroundStyle(.white).cornerRadius(8)
                }
            }
            .padding().background(.white.opacity(0.1)).cornerRadius(12)
            if !actionMessage.isEmpty { Text(actionMessage).font(.caption).foregroundStyle(.green) }
        }
    }
    
    func iconFor(type: InsightType) -> String {
        switch type {
        case .audio: return "mic.fill"; case .image: return "camera.fill"; case .note: return "doc.text.fill"; case .pdf: return "doc.fill"
        }
    }
}

// Helper struct for Links
struct LinkDestination: View {
    let id: UUID
    let linkInfo: InsightLink
    @Query private var items: [InsightItem]
    
    init(id: UUID, linkInfo: InsightLink) {
        self.id = id
        self.linkInfo = linkInfo
        self._items = Query(filter: #Predicate { $0.id == id })
    }
    
    var body: some View {
        if let targetItem = items.first {
            NavigationLink(destination: InsightDetailView(item: targetItem)) {
                HStack {
                    Image(systemName: "link").foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(targetItem.title ?? targetItem.content.prefix(30) + "...")
                            .font(.subheadline).bold().foregroundStyle(.white)
                            .lineLimit(1)
                        
                        HStack {
                            Text("\(Int(linkInfo.strength * 100))% Match").font(.caption).foregroundStyle(.blue)
                            Text("• " + linkInfo.reason).font(.caption2).foregroundStyle(.gray)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.gray)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.05)).cornerRadius(10)
            }
        }
    }
}
