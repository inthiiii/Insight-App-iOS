import SwiftUI
import SwiftData

// 1. The Types of Data we accept
enum InsightType: String, Codable {
    case note, audio, image, pdf
}

// 2. Transcription Word Model (Karaoke Logic)
struct TranscriptWord: Codable, Identifiable, Equatable {
    var id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

// 3. The "Atom"
@Model
final class InsightItem {
    var id: UUID
    var typeString: String
    var content: String
    var dateCreated: Date
    var embedding: [Float]?
    var localFileName: String?
    
    // Meta
    var title: String?
    var category: String?
    var emojiTag: String?
    
    // Locus & Empathy
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String?
    var sentimentScore: Double?
    
    // Studio Fields
    var canvasX: Double?
    var canvasY: Double?
    var zoneID: UUID?
    
    // Shield
    var isLocked: Bool = false
    
    // --- ECHO FIELDS (Fixing the Error) ---
    var transcriptData: Data? // Stores [TranscriptWord] as JSON
    var waveformSamples: [Float]? // Stores amplitude bars
    
    @Relationship(deleteRule: .cascade)
    var outgoingLinks: [InsightLink]? = []
    
    var type: InsightType {
        get { InsightType(rawValue: typeString) ?? .note }
        set { typeString = newValue.rawValue }
    }
    
    // Helper to decode words
    var transcriptWords: [TranscriptWord] {
        guard let data = transcriptData else { return [] }
        return (try? JSONDecoder().decode([TranscriptWord].self, from: data)) ?? []
    }
    
    init(type: InsightType, content: String, title: String? = nil, category: String? = nil, localFileName: String? = nil, lat: Double? = nil, long: Double? = nil, locLabel: String? = nil, sentiment: Double? = nil, x: Double? = nil, y: Double? = nil, isLocked: Bool = false, transcriptWords: [TranscriptWord]? = nil, waveformSamples: [Float]? = nil) {
        self.id = UUID()
        self.typeString = type.rawValue
        self.content = content
        self.title = title
        self.category = category
        self.dateCreated = Date()
        self.localFileName = localFileName
        self.latitude = lat; self.longitude = long; self.locationLabel = locLabel
        self.sentimentScore = sentiment
        self.canvasX = x; self.canvasY = y
        self.isLocked = isLocked
        
        // Echo Init
        if let words = transcriptWords {
            self.transcriptData = try? JSONEncoder().encode(words)
        }
        self.waveformSamples = waveformSamples
        
        self.outgoingLinks = []
    }
}

// Links, Zones, Drawings
@Model final class InsightLink {
    var reason: String; var strength: Double; var sourceID: UUID; var targetID: UUID
    init(sourceID: UUID, targetID: UUID, reason: String, strength: Double) { self.sourceID = sourceID; self.targetID = targetID; self.reason = reason; self.strength = strength }
}
@Model final class InsightZone {
    var id: UUID; var title: String; var x: Double; var y: Double; var width: Double; var height: Double; var colorHex: String
    init(title: String, x: Double, y: Double, width: Double = 300, height: Double = 300, colorHex: String = "0000FF") { self.id = UUID(); self.title = title; self.x = x; self.y = y; self.width = width; self.height = height; self.colorHex = colorHex }
}
@Model final class InsightDrawing {
    var id: UUID; var data: Data
    init(data: Data) { self.id = UUID(); self.data = data }
}
