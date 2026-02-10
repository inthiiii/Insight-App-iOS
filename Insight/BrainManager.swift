import Foundation
import NaturalLanguage
import SwiftData

class BrainManager {
    static let shared = BrainManager()
    private let embeddingModel = NLEmbedding.sentenceEmbedding(for: .english)
    
    // --- 1. PROCESS & LINKING (The Synapse) ---
    // Called whenever a new note is saved to find connections
    func process(_ newItem: InsightItem, in context: ModelContext, allItems: [InsightItem]) {
        guard let vector = embeddingModel?.vector(for: newItem.content) else { return }
        newItem.embedding = vector.map { Float($0) }
        
        for existingItem in allItems {
            if existingItem.id == newItem.id { continue }
            guard let existingVector = existingItem.embedding else { continue }
            
            // Calculate relevance
            let score = cosineSimilarity(vectorA: newItem.embedding!, vectorB: existingVector)
            
            // Contextual Threshold: Only link if relevance is > 35%
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
        
        context.insert(linkA)
        context.insert(linkB)
        
        if itemA.outgoingLinks == nil { itemA.outgoingLinks = [] }
        itemA.outgoingLinks?.append(linkA)
        if itemB.outgoingLinks == nil { itemB.outgoingLinks = [] }
        itemB.outgoingLinks?.append(linkB)
    }
    
    // --- 2. SEARCH & RETRIEVAL (The Oracle) ---
    
    // Returns a sorted list of matches for the List View
    func search(query: String, in items: [InsightItem]) -> [(item: InsightItem, score: Double)] {
        guard let queryVector = embeddingModel?.vector(for: query) else { return [] }
        let queryFloats = queryVector.map { Float($0) }
        let lowerQuery = query.localizedLowercase
        
        var results: [(item: InsightItem, score: Double)] = []
        
        for item in items {
            var score = 0.0
            
            // A. Vector Match (Semantic Meaning)
            if let itemVector = item.embedding {
                score = cosineSimilarity(vectorA: queryFloats, vectorB: itemVector)
            }
            
            // B. Smart Title Boost (The "Alpha" Fix)
            if let title = item.title?.localizedLowercase {
                if lowerQuery.contains(title) { score += 0.5 }
                else if title.contains(lowerQuery) { score += 0.3 }
            }
            
            // C. Keyword Boost (Exact Match)
            if item.content.localizedLowercase.contains(lowerQuery) { score += 0.1 }
            
            // Threshold to filter noise
            if score > 0.22 { results.append((item, score)) }
        }
        
        return results.sorted { $0.score > $1.score }
    }
    
    // Returns the single best match with a specific snippet (Used by ARA Chat)
    func smartSearch(query: String, in items: [InsightItem]) -> (item: InsightItem, score: Double, snippet: String)? {
        let candidates = search(query: query, in: items)
        
        if let best = candidates.first {
            let snippet = extractRelevantSnippet(from: best.item.content, query: query)
            return (best.item, best.score, snippet)
        }
        return nil
    }
    
    // --- 3. INTELLIGENT EXTRACTOR (Needle in Haystack) ---
    func extractRelevantSnippet(from content: String, query: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = content
        
        let queryWords = query.localizedLowercase.components(separatedBy: .punctuationCharacters).joined().split(separator: " ")
        
        var bestSentence = ""
        var maxScore = 0.0
        
        // Scan sentences to find the one with the most relevant keywords
        tokenizer.enumerateTokens(in: content.startIndex..<content.endIndex) { range, _ in
            let sentence = String(content[range])
            let lowerSentence = sentence.localizedLowercase
            
            var score = 0.0
            // Keyword Density check
            for word in queryWords {
                if lowerSentence.contains(word) { score += 1.0 }
            }
            
            // Exact phrase match bonus
            if lowerSentence.contains(query.localizedLowercase) { score += 5.0 }
            
            if score > maxScore {
                maxScore = score
                bestSentence = sentence
            }
            return true
        }
        
        // Fallback: If no specific sentence won, return start of note
        if bestSentence.isEmpty {
            bestSentence = content.components(separatedBy: ".").first ?? content.prefix(100) + "..."
        }
        
        // Limit length to keep chat readable
        if bestSentence.count > 300 {
            return String(bestSentence.prefix(300)) + "..."
        }
        
        return bestSentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // --- 4. MATH HELPERS (The Engine Room) ---
    
    // Helper to compare query vs text chunk (Used by PDF Reader)
    func compare(query: String, textChunk: String) -> Double {
        // Hybrid Score: Vector + Keywords
        let queryWords = query.localizedLowercase.split(separator: " ")
        var keywordScore = 0.0
        let chunkLower = textChunk.localizedLowercase
        
        for word in queryWords {
            if chunkLower.contains(word) { keywordScore += 0.2 }
        }
        
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
    
    // --- 5. PATHFINDER (Navigator Feature) ---
    func findShortestPath(from startID: UUID, to endID: UUID, allItems: [InsightItem]) -> [UUID] {
        // Build Adjacency Graph
        var graph: [UUID: [UUID]] = [:]
        for item in allItems {
            let neighbors = item.outgoingLinks?.map { $0.targetID } ?? []
            graph[item.id] = neighbors
        }
        
        // BFS Queue
        var queue: [[UUID]] = [[startID]]
        var visited = Set<UUID>()
        visited.insert(startID)
        
        while !queue.isEmpty {
            let path = queue.removeFirst()
            let node = path.last!
            
            if node == endID { return path } // Found!
            
            if let neighbors = graph[node] {
                for neighbor in neighbors {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        var newPath = path
                        newPath.append(neighbor)
                        queue.append(newPath)
                    }
                }
            }
        }
        return [] // No path found
    }
}
