import SwiftUI
import NaturalLanguage

struct SentenceBlock: Identifiable {
    let id = UUID()
    let text: String
    var isExpanded: Bool = false
    var expansion: String? = nil
    var isLoading: Bool = false
}

struct RecursiveReader: View {
    let fullContent: String
    @State private var blocks: [SentenceBlock] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Intro Hint
                HStack {
                    Image(systemName: "hand.tap")
                    Text("Long Press any sentence to Deep Dive")
                }
                .font(.caption).bold().foregroundStyle(.gray)
                .padding(.bottom, 10)
                
                // Sentence Blocks
                ForEach(blocks) { block in
                    VStack(alignment: .leading, spacing: 8) {
                        // 1. The Sentence (Interactive Trigger)
                        Text(block.text)
                            .font(.body)
                            .foregroundStyle(block.isExpanded ? .yellow : .white)
                            .padding(8)
                            .background(block.isExpanded ? Color.white.opacity(0.1) : Color.clear)
                            .cornerRadius(8)
                            .onLongPressGesture {
                                // PASS ID INSTEAD OF BINDING
                                triggerExpansion(for: block.id)
                            }
                        
                        // 2. The Expansion (Liquid Growth)
                        if block.isExpanded {
                            VStack(alignment: .leading) {
                                if block.isLoading {
                                    HStack {
                                        ProgressView()
                                            .tint(.yellow)
                                        Text("ARA is analyzing context...")
                                            .font(.caption).italic().foregroundStyle(.gray)
                                    }
                                    .padding(.leading, 16)
                                } else if let expansion = block.expansion {
                                    Text(expansion)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(hex: "1e293b"))
                                                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 5)
                                        )
                                        .overlay(
                                            Rectangle()
                                                .fill(Color.yellow)
                                                .frame(width: 2)
                                                .padding(.vertical, 8),
                                            alignment: .leading
                                        )
                                        .padding(.leading, 16)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: block.isExpanded)
                }
            }
            .padding()
        }
        .onAppear {
            parseContent()
        }
    }
    
    // Break text into sentences
    func parseContent() {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = fullContent
        var newBlocks: [SentenceBlock] = []
        
        tokenizer.enumerateTokens(in: fullContent.startIndex..<fullContent.endIndex) { range, _ in
            let sentence = String(fullContent[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                newBlocks.append(SentenceBlock(text: sentence))
            }
            return true
        }
        self.blocks = newBlocks
    }
    
    // AI Trigger (Fixed Logic)
    func triggerExpansion(for id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Toggle UI State
        withAnimation {
            blocks[index].isExpanded.toggle()
        }
        
        // If opening and no content, start AI load
        if blocks[index].isExpanded && blocks[index].expansion == nil {
            blocks[index].isLoading = true
            let sentenceText = blocks[index].text // Capture value, not reference
            
            // Simulate AI Delay
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                // Generate
                let generatedText = AraEngine().expand(sentence: sentenceText, context: fullContent)
                
                DispatchQueue.main.async {
                    // Locate index again (safe check)
                    if let newIndex = self.blocks.firstIndex(where: { $0.id == id }) {
                        withAnimation {
                            self.blocks[newIndex].isLoading = false
                            self.blocks[newIndex].expansion = generatedText
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }
}
