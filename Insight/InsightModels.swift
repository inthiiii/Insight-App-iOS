import SwiftUI
import SwiftData

// 1. The Types of Data we accept
enum InsightType: String, Codable {
    case note       // Just text
    case audio      // Voice recordings
    case image      // Photos/Screenshots
    case pdf        // Documents
}

// 2. The "Atom" - Represents one piece of knowledge
@Model
final class InsightItem {
    var id: UUID
    var typeString: String
    var content: String
    var dateCreated: Date
    var embedding: [Float]?
    var localFileName: String?
    
    // META FIELDS
    var title: String?
    var category: String?
    
    // LOCUS FIELDS (New)
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String? // e.g., "SLIIT Campus"
    
    // EMPATHY FIELD (New)
    var sentimentScore: Double? // -1.0 (Sad) to 1.0 (Happy)
    
    @Relationship(deleteRule: .cascade)
    var outgoingLinks: [InsightLink]? = []
    
    var type: InsightType {
        get { InsightType(rawValue: typeString) ?? .note }
        set { typeString = newValue.rawValue }
    }
    
    init(type: InsightType, content: String, title: String? = nil, category: String? = nil, localFileName: String? = nil, lat: Double? = nil, long: Double? = nil, locLabel: String? = nil, sentiment: Double? = nil) {
        self.id = UUID()
        self.typeString = type.rawValue
        self.content = content
        self.title = title
        self.category = category
        self.dateCreated = Date()
        self.localFileName = localFileName
        
        // New Init Values
        self.latitude = lat
        self.longitude = long
        self.locationLabel = locLabel
        self.sentimentScore = sentiment
        
        self.outgoingLinks = []
    }
}

// 3. The "Thread" - Represents the connection between two atoms
@Model
final class InsightLink {
    var reason: String
    var strength: Double
    
    var sourceID: UUID
    var targetID: UUID
    
    init(sourceID: UUID, targetID: UUID, reason: String, strength: Double) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.reason = reason
        self.strength = strength
    }
}
