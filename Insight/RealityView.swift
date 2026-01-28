import SwiftUI
import SwiftData
import NaturalLanguage // Added for Tokenization

struct RealityView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [InsightItem]
    
    // State
    @State private var foundInsight: InsightItem?
    @State private var scannedText: String = ""
    @State private var isScanning = true
    
    // For Navigation (Click to Open)
    @State private var selectedInsightForDetail: InsightItem?
    
    var body: some View {
        ZStack {
            // 1. The Camera Feed
            if isScanning {
                ARScannerView { text in
                    smartMatch(text: text)
                }
                .ignoresSafeArea()
            }
            
            // 2. The Overlay UI
            VStack {
                // Header
                Text("Reality Anchor")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 50)
                    .shadow(radius: 5)
                
                Spacer()
                
                // 3. The Match Bubble (Clickable)
                if let insight = foundInsight {
                    Button(action: {
                        // Trigger Navigation
                        selectedInsightForDetail = insight
                    }) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.yellow)
                                Text("Linked Memory Found")
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(.gray)
                                Spacer()
                                // Close Button
                                Button(action: {
                                    withAnimation { foundInsight = nil }
                                }) {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.gray.opacity(0.5))
                                }
                            }
                            
                            Divider()
                            
                            // Title (if exists) or Content
                            if let title = insight.title, !title.isEmpty {
                                Text(title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            
                            Text(insight.content)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            
                            HStack {
                                Image(systemName: "link")
                                Text("Triggered by: \"\(scannedText.prefix(20))...\"")
                                    .italic()
                                Spacer()
                                Text("Tap to Open")
                                    .font(.caption2).bold()
                                    .foregroundStyle(.blue)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
                        }
                        .padding()
                        .background(.ultraThinMaterial) // Glass effect
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                        )
                        .padding()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: foundInsight)
                }
            }
        }
        // 4. The Sheet for Full View
        .sheet(item: $selectedInsightForDetail) { item in
            NavigationStack {
                InsightDetailView(item: item)
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    // LOGIC: Smart Keyword Extraction
    func smartMatch(text: String) {
        // 1. Tokenize the scanned text (Split paragraphs into words)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        var keywords: [String] = []
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let word = String(text[tokenRange])
            // Filter out small noise words (is, the, at, etc)
            if word.count > 4 {
                keywords.append(word.localizedLowercase)
            }
            return true
        }
        
        // 2. Check Database for Matches
        // We look for ANY keyword from the scanned text that appears in your Notes
        for keyword in keywords {
            if let match = allItems.first(where: { item in
                let contentMatch = item.content.localizedLowercase.contains(keyword)
                let titleMatch = item.title?.localizedLowercase.contains(keyword) ?? false
                let categoryMatch = item.category?.localizedLowercase.contains(keyword) ?? false
                
                return contentMatch || titleMatch || categoryMatch
            }) {
                // Found a match!
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                
                withAnimation {
                    self.scannedText = keyword // Show WHICH word triggered it
                    self.foundInsight = match
                }
                return // Stop after first match to avoid flickering
            }
        }
    }
}
