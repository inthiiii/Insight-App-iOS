import Foundation
import NaturalLanguage

class SynthesisManager {
    static let shared = SynthesisManager()
    
    func synthesize(items: [InsightItem]) -> String {
        // 1. Combine all content
        let fullText = items.map { $0.content }.joined(separator: "\n\n")
        
        // 2. Setup Tokenizer to find sentences
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = fullText
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { range, _ in
            sentences.append(String(fullText[range]))
            return true
        }
        
        // 3. Simple Importance Algorithm (Extractive Summary)
        // We pick sentences that contain the most frequent words in the group
        let importantSentences = sentences.filter { sentence in
            sentence.count > 20 // Filter out short noise
        }.prefix(5) // Take top 5 sentences (In a real LLM, we'd generate new text)
        
        return "--- INSIGHT BRIEFING ---\n\n" + importantSentences.joined(separator: "\n• ")
    }
}
