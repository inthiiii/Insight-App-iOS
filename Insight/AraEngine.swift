import Foundation
import SwiftData
import PDFKit
import NaturalLanguage

// --- ENUMS ---
enum AraAction: Equatable {
    case none
    case createNote(title: String)
    case enableFocusMode
}

enum GhostFormat: String, CaseIterable {
    case email = "Email Draft"
    case linkedin = "LinkedIn Post"
    case summary = "Executive Summary"
}

enum GhostTone: String, CaseIterable {
    case formal = "Formal"
    case casual = "Casual"
    case creative = "Creative"
}

@Observable
class AraEngine {
    var state: AraState = .idle
    var currentStream: String = ""
    var pendingAction: AraAction = .none
    
    // --- MEMORY & CONTEXT ---
    private var lastContextTopic: String? = nil
    private var shortTermMemory: String = "" // Stores the last answer for context
    
    // --- FOCUS MODE STATE ---
    var isFocusMode: Bool = false
    var focusDocumentName: String = ""
    private var focusChunks: [(text: String, page: Int)] = []
    var docStatus: String = ""
    
    // --- 1. SYSTEM KNOWLEDGE (Self-Awareness) ---
    private let appKnowledgeBase: [String: String] = [
        "reality anchor": "Reality Anchors allow you to pin notes to physical objects using AR. Go to the Home Screen -> Eye Icon -> Switch to 'Spatial' mode.",
        "fusion": "Fusion Mode allows you to combine multiple notes into a new insight. Go to Library -> Select 2+ notes -> Tap the Atom icon.",
        "socratic": "The Socratic Mirror is a critique tool. Open a note -> Tap the Brain icon. ARA will challenge your assumptions.",
        "oracle": "Oracle is the semantic search engine. It understands concepts, not just keywords. Switch to 3D mode for a visual helix.",
        "deep dive": "Dynamic Deep Dive generates new content recursively. Open a note -> Switch to Reader Mode (Book Icon) -> Long press a sentence.",
        "privacy": "All data is stored locally on your device using SwiftData. Nothing is sent to the cloud.",
        "error": "If you encounter issues, try restarting the app or checking your permissions in Settings."
    ]
    
    // --- 2. LOAD PDF ---
    func loadPDF(url: URL) {
        self.state = .thinking
        self.docStatus = "Reading..."
        self.focusDocumentName = url.lastPathComponent
        self.isFocusMode = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let pdf = PDFDocument(url: url) {
                var extracted: [(String, Int)] = []
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i), let text = page.string {
                        // Split by paragraphs to keep context
                        let paragraphs = text.components(separatedBy: "\n\n")
                        for p in paragraphs {
                            let clean = p.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                            if clean.count > 20 { extracted.append((clean, i + 1)) }
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.focusChunks = extracted
                    self.state = .idle
                    self.docStatus = "Ready"
                    self.currentStream = "I've analyzed \(self.focusDocumentName) (\(pdf.pageCount) pages). Ask me specific questions."
                }
            }
        }
    }
    
    // --- 3. THE INTELLIGENT ROUTER (Ask Function) ---
    func ask(query: String, allItems: [InsightItem], onComplete: @escaping (String, InsightItem?) -> Void) {
        self.state = .thinking
        self.currentStream = ""
        self.pendingAction = .none
        
        let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // LAYER 1: SYSTEM COMMANDS
        if lowerQuery.hasPrefix("create note") {
            let title = query.replacingOccurrences(of: "create note", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            self.pendingAction = .createNote(title: title)
            self.state = .speaking
            self.typewriterEffect(text: "Opening editor for '\(title)'...") { onComplete("Opening editor...", nil) }
            return
        }
        
        // LAYER 2: MATH & CALCULATIONS
        if let mathResult = solveMath(query) {
            self.state = .speaking
            let response = "Calculation Result: \(mathResult)"
            self.typewriterEffect(text: response) { onComplete(response, nil) }
            return
        }
        
        // LAYER 3: APP KNOWLEDGE (Self-Help)
        for (key, answer) in appKnowledgeBase {
            if lowerQuery.contains(key) && (lowerQuery.contains("how") || lowerQuery.contains("what") || lowerQuery.contains("help")) {
                self.state = .speaking
                self.typewriterEffect(text: answer) { onComplete(answer, nil) }
                return
            }
        }
        
        // LAYER 4: CHIT-CHAT (Personality)
        if let chatResponse = generalChat(lowerQuery) {
            self.state = .speaking
            self.typewriterEffect(text: chatResponse) { onComplete(chatResponse, nil) }
            return
        }
        
        // LAYER 5: CONTEXTUAL DATA RETRIEVAL
        // Resolve Pronouns using Short Term Memory
        var finalQuery = query
        if !shortTermMemory.isEmpty {
            if lowerQuery.contains(" it ") || lowerQuery.contains(" he ") || lowerQuery.contains(" she ") || lowerQuery.contains(" that ") {
                finalQuery = "\(query) (Context: \(shortTermMemory))"
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // A. PDF MODE
            if self.isFocusMode {
                let answer = self.analyzePDFQuery(query: finalQuery)
                DispatchQueue.main.async {
                    self.state = .speaking
                    self.shortTermMemory = answer // Save to memory
                    self.typewriterEffect(text: answer) { onComplete(answer, nil) }
                }
            }
            // B. LIBRARY MODE
            else {
                let result = BrainManager.shared.smartSearch(query: finalQuery, in: allItems)
                DispatchQueue.main.async {
                    self.state = .speaking
                    if let match = result {
                        self.lastContextTopic = match.item.title
                        // Construct Reasoning
                        let reason = "Found in **\(match.item.title ?? "Note")**:"
                        let fullAnswer = "\(reason)\n\n\"\(match.snippet)\""
                        
                        self.shortTermMemory = match.snippet // Save snippet to memory
                        self.typewriterEffect(text: fullAnswer) { onComplete(fullAnswer, match.item) }
                    } else {
                        let fail = "I searched your memory banks but couldn't find a direct match."
                        self.typewriterEffect(text: fail) { onComplete(fail, nil) }
                    }
                }
            }
        }
    }
    
    // --- 4. PRECISION EXTRACTOR (PDF) ---
    private func analyzePDFQuery(query: String) -> String {
        var bestChunk = ""
        var bestPage = 0
        var maxScore = 0.0
        
        // 1. Find best chunk
        for chunk in self.focusChunks {
            let score = BrainManager.shared.compare(query: query, textChunk: chunk.text)
            if score > maxScore {
                maxScore = score
                bestChunk = chunk.text
                bestPage = chunk.page
            }
        }
        
        if maxScore > 0.25 {
            // 2. Extract Needle from Haystack (Sentence Level)
            // We use BrainManager's extractor which we updated in Phase 12.6
            let snippet = BrainManager.shared.extractRelevantSnippet(from: bestChunk, query: query)
            return "From Page \(bestPage):\n\n\"\(snippet)\""
        } else {
            return "I scanned the document but couldn't find a specific answer to that."
        }
    }
    
    // --- 5. GHOST WRITER ---
    func ghostWrite(items: [InsightItem], format: GhostFormat, tone: GhostTone) -> String {
        let rawTexts = items.map { $0.content }.joined(separator: "\n\n")
        let topicStr = items.first?.title ?? "Project"
        
        return """
        \(format.rawValue.uppercased())
        Topic: \(topicStr)
        Tone: \(tone.rawValue)
        
        \(rawTexts.prefix(800))...
        
        (Generated by ARA Intelligence)
        """
    }
    
    // --- 6. SYNTHESIZER ---
    func synthesize(items: [InsightItem]) -> String {
        let titles = items.compactMap { $0.title }.joined(separator: " + ")
        return """
        FUSION RESULT: \(titles)
        
        By combining these concepts, a new perspective emerges.
        
        1. Intersection:
        The logic of the first note meets the constraints of the second.
        
        2. Opportunity:
        There is a gap identified here that can be solved using this hybrid methodology.
        """
    }
    
    // --- 7. SOCRATIC MIRROR ---
    func generateCritique(for text: String) -> [CritiquePoint] {
        var points: [CritiquePoint] = []
        let sentences = text.components(separatedBy: ". ")
        for sentence in sentences {
            let lower = sentence.lowercased()
            if lower.contains("assume") || lower.contains("believe") {
                points.append(CritiquePoint(originalText: sentence, question: "Uncertainty detected. Data?", type: .evidence))
            } else if lower.contains("always") || lower.contains("never") {
                points.append(CritiquePoint(originalText: sentence, question: "Absolutes are risky.", type: .logic))
            }
        }
        return Array(points.prefix(3))
    }
    
    // --- 8. DYNAMIC DEEP DIVE ---
    func expand(sentence: String, context: String) -> String {
        // Simple context-aware expansion simulation
        let topic = sentence.components(separatedBy: " ").sorted { $0.count > $1.count }.first ?? "this topic"
        return """
        DEEP DIVE: \(topic.capitalized)
        
        You focused on "\(topic)". Contextually, this represents the structural foundation of the argument.
        
        Implication:
        Ignoring this variable typically leads to downstream instability.
        """
    }
    
    // --- 9. NAVIGATOR EXPLAINER (Fixed Missing Function) ---
    func explainConnection(items: [InsightItem]) -> String {
        let titles = items.compactMap { $0.title ?? "Note" }.joined(separator: " -> ")
        return """
        I have analyzed the connection path:
        
        \(titles)
        
        These items appear to be linked because they share semantic similarities in their content embeddings or explicit category tags. This path represents a logical flow of information in your database.
        """
    }
    
    // --- HELPER LOGIC ---
    
    func solveMath(_ query: String) -> String? {
        let mathChars = CharacterSet(charactersIn: "0123456789+-*/().^ ")
        let cleanQuery = query.lowercased().replacingOccurrences(of: "what is", with: "").replacingOccurrences(of: "calc", with: "").trimmingCharacters(in: .whitespaces)
        let letters = CharacterSet.letters.subtracting(CharacterSet(charactersIn: "e"))
        if cleanQuery.rangeOfCharacter(from: letters) != nil { return nil }
        if cleanQuery.rangeOfCharacter(from: .decimalDigits) == nil { return nil }
        let expr = NSExpression(format: cleanQuery)
        if let result = expr.expressionValue(with: nil, context: nil) as? NSNumber { return result.stringValue }
        return nil
    }
    
    func generalChat(_ query: String) -> String? {
        let q = query.lowercased()
        if q == "hi" || q == "hello" || q == "hey" { return "Hello. I am functioning within optimal parameters. How can I help?" }
        if q.contains("who are you") { return "I am ARA (Autonomous Responsive Assistant). I live on this device, secure and offline." }
        if q.contains("joke") { return "I tried to explain a pun to a qubit, but it was two-faced." }
        if q.contains("thank") { return "You are welcome. Ready for the next task." }
        return nil
    }
    
    private func typewriterEffect(text: String, completion: @escaping () -> Void) {
        var charIndex = 0.0
        self.currentStream = ""
        let speed = text.count > 100 ? 0.002 : 0.005
        
        for char in text {
            DispatchQueue.main.asyncAfter(deadline: .now() + (charIndex * speed)) { self.currentStream += String(char) }
            charIndex += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(text.count) * speed) + 0.5) {
            self.state = .idle
            completion()
        }
    }
    
    func exitFocusMode() { isFocusMode = false; focusChunks = []; focusDocumentName = ""; docStatus = "" }
}
