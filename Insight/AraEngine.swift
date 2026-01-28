import Foundation
import SwiftData
import PDFKit

// Action Enum for Controlling App
enum AraAction: Equatable {
    case none
    case createNote(title: String)
    case enableFocusMode
}

@Observable
class AraEngine {
    var state: AraState = .idle
    var currentStream: String = ""
    var pendingAction: AraAction = .none
    
    // Memory & Context
    private var lastContextTopic: String? = nil
    
    // Focus Mode
    var isFocusMode: Bool = false
    var focusDocumentName: String = ""
    private var focusChunks: [(text: String, page: Int)] = []
    var docStatus: String = ""
    
    // --- 1. LOAD PDF ---
    func loadPDF(url: URL) {
        self.state = .thinking
        self.docStatus = "Analyzing..."
        self.focusDocumentName = url.lastPathComponent
        self.isFocusMode = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let pdf = PDFDocument(url: url) {
                var extracted: [(String, Int)] = []
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i), let text = page.string {
                        // Semantic Chunking: Split by double newlines (Paragraphs)
                        let paragraphs = text.components(separatedBy: "\n\n")
                        for p in paragraphs {
                            // Clean up whitespace
                            let clean = p.replacingOccurrences(of: "\n", with: " ")
                                         .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Only add chunks with actual substance (> 20 chars)
                            if clean.count > 20 {
                                extracted.append((clean, i + 1))
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.focusChunks = extracted
                    self.state = .idle
                    self.docStatus = "Ready"
                    self.currentStream = "I've read \(self.focusDocumentName) (\(pdf.pageCount) pages). I'm ready for your questions."
                }
            }
        }
    }
    
    // --- 2. THE ROUTER (Ask Function) ---
    func ask(query: String, allItems: [InsightItem], onComplete: @escaping (String, InsightItem?) -> Void) {
        self.state = .thinking
        self.currentStream = ""
        self.pendingAction = .none
        
        let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // A. ACTION COMMANDS
        if lowerQuery.hasPrefix("create note") || lowerQuery.contains("create a new note") {
            let title = query.replacingOccurrences(of: "create a new note called", with: "", options: .caseInsensitive)
                             .replacingOccurrences(of: "create note", with: "", options: .caseInsensitive)
                             .trimmingCharacters(in: .whitespaces)
            self.pendingAction = .createNote(title: title)
            self.state = .speaking
            self.typewriterEffect(text: "Opening editor for '\(title)'...") {
                onComplete("Opening editor...", nil)
            }
            return
        }
        
        // B. MATH CHECK
        if let mathResult = solveMath(query) {
            self.state = .speaking
            let response = "Calculation Result:\n\n**\(mathResult)**"
            self.typewriterEffect(text: response) {
                onComplete(response, nil)
            }
            return
        }
        
        // C. CHIT-CHAT & GENERAL KNOWLEDGE CHECK
        // If this returns a string, we stop here. If nil, we go to database.
        if let chatResponse = generalChat(lowerQuery) {
            self.state = .speaking
            self.typewriterEffect(text: chatResponse) {
                onComplete(chatResponse, nil)
            }
            return
        }
        
        // D. CONTEXT INJECTION (Short-term Memory)
        var finalQuery = query
        // If user says "it" or "that", append the last topic found
        if let lastTopic = lastContextTopic, (lowerQuery.contains("it") || lowerQuery.contains("that") || lowerQuery.count < 10) {
            finalQuery = "\(lastTopic) \(query)"
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // E. SEARCH ROUTING
            if self.isFocusMode {
                // --- DOCUMENT SEARCH ---
                var bestChunk = ""
                var bestPage = 0
                var maxScore = 0.0
                
                for chunk in self.focusChunks {
                    let score = BrainManager.shared.compare(query: finalQuery, textChunk: chunk.text)
                    if score > maxScore {
                        maxScore = score
                        bestChunk = chunk.text
                        bestPage = chunk.page
                    }
                }
                
                DispatchQueue.main.async {
                    self.state = .speaking
                    if maxScore > 0.25 { // Lower threshold for better recall
                        let response = "Found on **Page \(bestPage)**:\n\n\"\(bestChunk)\""
                        self.typewriterEffect(text: response) {
                            onComplete(response, nil)
                        }
                    } else {
                        let response = "I analyzed the document, but couldn't find a specific answer to that. Try rephrasing?"
                        self.typewriterEffect(text: response) {
                            onComplete(response, nil)
                        }
                    }
                }
                
            } else {
                // --- MEMORY SEARCH (DATABASE) ---
                let result = BrainManager.shared.smartSearch(query: finalQuery, in: allItems)
                
                DispatchQueue.main.async {
                    self.state = .speaking
                    if let match = result {
                        // Success: Save context for next turn
                        self.lastContextTopic = match.item.title ?? match.item.content.prefix(20).description
                        
                        let sourceName = match.item.title ?? "your notes"
                        let response = "Based on **\(sourceName)**:\n\n\"\(match.snippet)\""
                        
                        self.typewriterEffect(text: response) {
                            onComplete(response, match.item) // Pass item for citation
                        }
                    } else {
                        // Failure: Specific Handling
                        var response = "I couldn't find that in your memory."
                        if lowerQuery.contains("schedule") || lowerQuery.contains("meeting") {
                            response = "I checked for schedules, meetings, and dates, but didn't find any explicit records."
                        }
                        self.typewriterEffect(text: response) {
                            onComplete(response, nil)
                        }
                    }
                }
            }
        }
    }
    
    // --- HELPER LOGIC ---
    
    func solveMath(_ query: String) -> String? {
        // Regex: Allow numbers, math symbols, and specific keywords like "calc"
        let mathChars = CharacterSet(charactersIn: "0123456789+-*/().^ ")
        let cleanQuery = query.lowercased().replacingOccurrences(of: "what is", with: "")
                              .replacingOccurrences(of: "calc", with: "")
                              .trimmingCharacters(in: .whitespaces)
        
        // If it contains letters (except 'e' for math), it's probably not pure math
        let letters = CharacterSet.letters.subtracting(CharacterSet(charactersIn: "e")) // e for exponent
        if cleanQuery.rangeOfCharacter(from: letters) != nil {
            return nil
        }
        
        // Must contain at least one digit
        if cleanQuery.rangeOfCharacter(from: .decimalDigits) == nil {
            return nil
        }
        
        let expr = NSExpression(format: cleanQuery)
        if let result = expr.expressionValue(with: nil, context: nil) as? NSNumber {
            return result.stringValue
        }
        return nil
    }
    
    func generalChat(_ query: String) -> String? {
        let q = query.lowercased()
        
        // GREETINGS
        if q == "hi" || q == "hello" || q == "hey" { return "Hello! I am ARA. I can read your notes, analyze PDFs, or do math." }
        if q.contains("how are you") { return "I am functioning perfectly within your device's ecosystem. How can I help?" }
        if q.contains("who are you") { return "I am ARA (Autonomous Responsive Assistant), a sovereign AI running completely offline." }
        
        // CREATIVITY (Jokes, Poems)
        if q.contains("joke") {
            let jokes = [
                "Why don't AIs trust atoms? Because they make up everything!",
                "I changed my password to 'incorrect'. So whenever I forget it, the computer tells me.",
                "A SQL query walks into a bar, walks up to two tables and asks... 'Can I join you?'"
            ]
            return jokes.randomElement()
        }
        if q.contains("poem") {
            return "In circuits deep where logic flows,\nA quiet mind of silicon grows.\nI keep your thoughts, I guard your key,\nA digital ghost, wild and free."
        }
        if q.contains("story") {
            return "Once upon a time, there was a user who wanted privacy. They built an AI that lived only on their phone, never speaking to the cloud. And they lived happily, and securely, ever after."
        }
        
        // PHILOSOPHY
        if q.contains("meaning of life") { return "42. Or perhaps, simply to create and remember." }
        
        // MANNERS
        if q.contains("thank") { return "You're welcome. Let me know if you need to find anything else." }
        
        // If query is about specific user data ("Schedule", "Notes", "Key"), return nil so it searches DB
        if q.contains("schedule") || q.contains("meeting") || q.contains("plan") { return nil }
        
        return nil // Fallback to Memory Search
    }
    
    // Animation Logic
    private func typewriterEffect(text: String, completion: @escaping () -> Void) {
        var charIndex = 0.0
        self.currentStream = "" // Reset visual stream
        
        for char in text {
            DispatchQueue.main.asyncAfter(deadline: .now() + (charIndex * 0.005)) {
                self.currentStream += String(char)
            }
            charIndex += 1
        }
        
        // Wait for typing to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(text.count) * 0.005) + 0.5) {
            self.state = .idle
            completion() // Save data
            self.currentStream = "" // Clear visual stream
        }
    }
    
    func exitFocusMode() {
        isFocusMode = false; focusChunks = []; focusDocumentName = ""; docStatus = ""
    }
}
