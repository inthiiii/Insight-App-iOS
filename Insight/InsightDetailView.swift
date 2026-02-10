import SwiftUI
import SwiftData

struct InsightDetailView: View {
    @Bindable var item: InsightItem
    @State private var detectedDate: Date?
    @State private var actionMessage = ""
    @State private var showingCategoryAlert = false
    @State private var newCategory = ""
    
    // --- SOCRATIC STATE ---
    @State private var isSocraticMode = false
    @State private var critiques: [CritiquePoint] = []
    
    // --- READER STATE ---
    @State private var isReaderMode = false
    
    var body: some View {
        ShieldView(isLocked: $item.isLocked) {
            ZStack(alignment: .trailing) {
                Color(hex: "0f172a").ignoresSafeArea()
                
                // 1. MAIN CONTENT
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // HEADER
                        VStack(alignment: .leading) {
                            TextField("Add Title...", text: Binding(
                                get: { item.title ?? "" },
                                set: { item.title = $0 }
                            ))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .submitLabel(.done)
                            
                            HStack {
                                Menu {
                                    Button("Work") { item.category = "Work" }
                                    Button("Personal") { item.category = "Personal" }
                                    Button("Ideas") { item.category = "Ideas" }
                                    Divider()
                                    Button("Custom...") { showingCategoryAlert = true }
                                    Button("Clear", role: .destructive) { item.category = nil }
                                } label: {
                                    HStack {
                                        Image(systemName: "tag.fill")
                                        Text(item.category ?? "No Category")
                                    }
                                    .font(.caption).bold().padding(8)
                                    .background(item.category != nil ? .blue : .white.opacity(0.1))
                                    .foregroundStyle(.white).clipShape(Capsule())
                                }
                                
                                if let loc = item.locationLabel {
                                    HStack {
                                        Image(systemName: "location.fill")
                                        Text(loc)
                                    }
                                    .font(.caption).bold().padding(8)
                                    .background(.white.opacity(0.1))
                                    .foregroundStyle(.white.opacity(0.8)).clipShape(Capsule())
                                }
                            }
                        }
                        
                        // MEDIA
                        if let filename = item.localFileName, item.type == .image, let img = VisionManager.loadImageFromDisk(filename: filename) {
                            Image(uiImage: img).resizable().scaledToFit().cornerRadius(15).shadow(radius: 10)
                        }
                        
                        // AUDIO PLAYER (Updated)
                        if item.type == .audio, let filename = item.localFileName {
                            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
                            if FileManager.default.fileExists(atPath: fileURL.path) {
                                // Removed background and cornerRadius container logic here
                                EchoPlayerView(item: item, audioURL: fileURL)
                                    .frame(height: 300)
                            }
                        }
                        
                        // CONTENT SWITCHER
                        HStack {
                            Text(isReaderMode ? "Interactive Reader" : "Content Editor")
                                .font(.headline).foregroundStyle(.white.opacity(0.7))
                            Spacer()
                        }
                        
                        if isReaderMode {
                            RecursiveReader(fullContent: item.content)
                                .frame(minHeight: 400)
                                .transition(.opacity)
                        } else {
                            TextEditor(text: $item.content)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(.white)
                                .font(.body)
                                .frame(minHeight: 150)
                                .padding()
                                .background(.white.opacity(0.05))
                                .cornerRadius(10)
                                .onChange(of: item.content) {
                                    if isSocraticMode { critiques = AraEngine().generateCritique(for: item.content) }
                                }
                                .transition(.opacity)
                        }
                        
                        // SMART ACTIONS
                        if let date = detectedDate { smartActionView(date: date) }
                        if let links = item.outgoingLinks, !links.isEmpty {
                            Text("Linked Knowledge").font(.headline).foregroundStyle(.blue)
                            ForEach(links, id: \.targetID) { link in LinkDestination(id: link.targetID, linkInfo: link) }
                        }
                    }
                    .padding()
                }
                
                // 2. SOCRATIC OVERLAY
                if isSocraticMode {
                    GeometryReader { geo in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 20) {
                                Spacer().frame(height: 180)
                                ForEach(critiques) { point in
                                    HStack {
                                        Spacer()
                                        SocraticBubble(point: point)
                                    }
                                    .padding(.trailing, 10)
                                }
                            }
                            .frame(width: geo.size.width)
                        }
                    }
                    .allowsHitTesting(true)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { isReaderMode.toggle() }
                }) {
                    Image(systemName: "book.pages")
                        .symbolEffect(.bounce, value: isReaderMode)
                        .foregroundStyle(isReaderMode ? .yellow : .gray)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleSocraticMode) {
                    Image(systemName: "brain.head.profile")
                        .symbolEffect(.bounce, value: isSocraticMode)
                        .foregroundStyle(isSocraticMode ? .purple : .gray)
                }
            }
            
            // LOCK TOGGLE
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    if item.isLocked {
                        BiometricManager.shared.authenticate(reason: "Unlock Note") { success in
                            if success {
                                withAnimation { item.isLocked = false }
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                            }
                        }
                    } else {
                        withAnimation { item.isLocked = true }
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    }
                }) {
                    Image(systemName: item.isLocked ? "lock.fill" : "lock.open.fill")
                        .foregroundStyle(item.isLocked ? .red : .blue)
                }
            }
        }
        .alert("New Category", isPresented: $showingCategoryAlert) {
            TextField("Category Name", text: $newCategory)
            Button("Add") { item.category = newCategory; newCategory = "" }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear { self.detectedDate = SmartActionManager.shared.detectDates(in: item.content) }
        .onChange(of: item.content) { self.detectedDate = SmartActionManager.shared.detectDates(in: item.content) }
    }
    
    func toggleSocraticMode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring()) {
            isSocraticMode.toggle()
            if isSocraticMode { critiques = AraEngine().generateCritique(for: item.content) }
        }
    }
    
    func smartActionView(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smart Action").font(.caption).foregroundStyle(.blue)
            HStack { Text(date.formatted()).foregroundStyle(.white); Spacer(); Button("Add") { /*...*/ }.buttonStyle(.bordered) }
        }.padding().background(.white.opacity(0.1)).cornerRadius(12)
    }
}

struct SocraticBubble: View {
    let point: CritiquePoint; @State private var isExpanded = false
    var body: some View { ZStack(alignment: .trailing) { if isExpanded { HStack(alignment: .top, spacing: 10) { VStack(alignment: .leading, spacing: 6) { Text(point.type == .evidence ? "Evidence Missing" : (point.type == .logic ? "Logic Gap" : "Clarify")).font(.caption).bold().foregroundStyle(point.type.color).textCase(.uppercase); Text(point.question).font(.caption).foregroundStyle(.black.opacity(0.8)).fixedSize(horizontal: false, vertical: true) }; Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.gray) }.padding(12).frame(width: 240).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.95)).shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)).offset(x: -50).transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity)).onTapGesture { UIImpactFeedbackGenerator(style: .light).impactOccurred(); withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isExpanded = false } }.zIndex(2) }; Circle().fill(point.type.color.gradient).frame(width: 44, height: 44).overlay(Image(systemName: point.type == .evidence ? "magnifyingglass" : (point.type == .logic ? "exclamationmark.triangle" : "bubble.left.and.bubble.right")).font(.caption).bold().foregroundStyle(.white)).shadow(color: point.type.color.opacity(0.5), radius: 6).scaleEffect(isExpanded ? 0.0 : 1.0).opacity(isExpanded ? 0 : 1).onTapGesture { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { isExpanded = true } }.zIndex(1) }.frame(height: 50) }
}
struct LinkDestination: View { let id: UUID; let linkInfo: InsightLink; @Query private var items: [InsightItem]; init(id: UUID, linkInfo: InsightLink) { self.id = id; self.linkInfo = linkInfo; self._items = Query(filter: #Predicate { $0.id == id }) }; var body: some View { if let targetItem = items.first { NavigationLink(destination: InsightDetailView(item: targetItem)) { HStack { Image(systemName: "link"); Text(targetItem.title ?? "Note"); Spacer() }.padding().background(.white.opacity(0.05)).cornerRadius(10) } } } }
