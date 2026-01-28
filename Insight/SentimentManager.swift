import SwiftUI
import Foundation
import NaturalLanguage

class SentimentManager {
    static let shared = SentimentManager()
    
    // Returns a score from -1.0 (Negative) to 1.0 (Positive)
    func analyzeSentiment(text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        if let scoreStr = sentiment?.rawValue, let score = Double(scoreStr) {
            return score
        }
        return 0.0 // Neutral default
    }
    
    // Returns a Color based on sentiment
    func colorForScore(_ score: Double?) -> SwiftUICore.Color {
        guard let s = score else { return .white.opacity(0.1) } // Neutral Grey
        
        if s > 0.3 { return .orange } // Happy/Excited
        if s < -0.3 { return .purple } // Sad/Stressed
        return .blue // Calm/Neutral
    }
}
