import Foundation
import NaturalLanguage
import SwiftData

class BrainManager {
    static let shared = BrainManager()
    private let embeddingModel = NLEmbedding.sentenceEmbedding(for: .english)
    
    // --- 1. PROCESS & LINKING ---
    func process(_ newItem: InsightItem, in context: ModelContext, allItems: [InsightItem]) {
        guard let vector = embeddingModel?.vector(for: newItem.content) else { return }
        newItem.embedding = vector.map { Float($0) }
        
        for existingItem in allItems {
            if existingItem.id == newItem.id { continue }
            guard let existingVector = existingItem.embedding else { continue }
            
            let score = cosineSimilarity(vectorA: newItem.embedding!, vectorB: existingVector)
            if score > 0.35 {
                createLink(from: newItem, to: existingItem, score: score, context: context)
            }
        }
        try? context.save()
    }
    
    private func createLink(from itemA: InsightItem, to itemB: InsightItem, score: Double, context: ModelContext) {
        let reason = "Contextual Match (\(Int(score * 100))%)"
        let linkA = InsightLink(sourceID: itemA.id, targetID: itemB.id, reason: reason, strength: score)
        let linkB = InsightLink(sourceID: itemB.id, targetID: itemA.id, reason: reason, strength: score)
        
        context.insert(linkA); context.insert(linkB)
        
        if itemA.outgoingLinks == nil { itemA.outgoingLinks = [] }
        itemA.outgoingLinks?.append(linkA)
        if itemB.outgoingLinks == nil { itemB.outgoingLinks = [] }
        itemB.outgoingLinks?.append(linkB)
    }
    
    // --- 2. ORACLE SEARCH (Returns a List) ---
    func search(query: String, in items: [InsightItem]) -> [(item: InsightItem, score: Double)] {
        guard let queryVector = embeddingModel?.vector(for: query) else { return [] }
        let queryFloats = queryVector.map { Float($0) }
        let lowerQuery = query.localizedLowercase
        
        var results: [(item: InsightItem, score: Double)] = []
        
        for item in items {
            var score = 0.0
            
            // A. Vector Match
            if let itemVector = item.embedding {
                score = cosineSimilarity(vectorA: queryFloats, vectorB: itemVector)
            }
            
            // B. Smart Title Boost (The "Alpha" Fix)
            if let title = item.title?.localizedLowercase {
                // If Title is IN the query (e.g., Query: "About Alpha", Title: "Alpha")
                if lowerQuery.contains(title) {
                    score += 0.5 // Massive Boost
                }
                // If Query is IN the title (e.g., Query: "Project", Title: "Alpha Project")
                else if title.contains(lowerQuery) {
                    score += 0.3
                }
            }
            
            // C. Keyword Boost
            if item.content.localizedLowercase.contains(lowerQuery) {
                score += 0.1
            }
            
            if score > 0.22 { // Lowered slightly to catch more results
                results.append((item, score))
            }
        }
        
        return results.sorted { $0.score > $1.score }
    }
    
    // --- 3. ARA SMART SEARCH (Returns Single Best Match with Snippet) ---
    func smartSearch(query: String, in items: [InsightItem]) -> (item: InsightItem, score: Double, snippet: String)? {
        // Re-use the list logic to get candidates
        let candidates = search(query: query, in: items)
        
        if let best = candidates.first {
            let snippet = extractRelevantSnippet(from: best.item.content, query: query)
            return (best.item, best.score, snippet)
        }
        return nil
    }
    
    // --- 4. HELPERS ---
    
    // Extracts the most relevant sentence(s) instead of the whole note
    func extractRelevantSnippet(from content: String, query: String) -> String {
        let queryWords = Set(query.localizedLowercase.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 })
        let sentences = content.components(separatedBy: ". ")
        
        var bestSentence = ""
        var maxOverlap = 0
        
        // Find the sentence with the most keyword overlap
        for sentence in sentences {
            let sentenceWords = Set(sentence.localizedLowercase.components(separatedBy: CharacterSet.alphanumerics.inverted))
            let overlap = queryWords.intersection(sentenceWords).count
            
            if overlap > maxOverlap {
                maxOverlap = overlap
                bestSentence = sentence
            }
        }
        
        // If no specific sentence won, or text is short, return start
        if bestSentence.isEmpty { bestSentence = sentences.first ?? content }
        
        // Truncate if too long
        if bestSentence.count > 300 {
            return String(bestSentence.prefix(300)) + "..."
        }
        return bestSentence
    }
    
    func compare(query: String, textChunk: String) -> Double {
        // A. Keyword Bonus
        let queryWords = query.localizedLowercase.split(separator: " ")
        var keywordScore = 0.0
        let chunkLower = textChunk.localizedLowercase
        
        for word in queryWords {
            if chunkLower.contains(word) {
                keywordScore += 0.2 // Boost per word match
            }
        }
        
        // B. Vector Score
        var vectorScore = 0.0
        if let queryVector = embeddingModel?.vector(for: query),
           let chunkVector = embeddingModel?.vector(for: textChunk) {
            
            let qFloats = queryVector.map { Float($0) }
            let cFloats = chunkVector.map { Float($0) }
            vectorScore = cosineSimilarity(vectorA: qFloats, vectorB: cFloats)
        }
        
        return max(vectorScore, keywordScore)
    }
    
    private func cosineSimilarity(vectorA: [Float], vectorB: [Float]) -> Double {
        guard vectorA.count == vectorB.count else { return 0.0 }
        let dotProduct = zip(vectorA, vectorB).map(*).reduce(0, +)
        let magnitudeA = sqrt(vectorA.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(vectorB.map { $0 * $0 }.reduce(0, +))
        return Double(dotProduct / (magnitudeA * magnitudeB))
    }
}
