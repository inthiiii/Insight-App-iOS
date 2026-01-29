import SwiftUI
import SwiftData

// 1. The Types of Data we accept
enum InsightType: String, Codable {
    case note, audio, image, pdf
}

// 2. The "Atom"
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
    var zoneID: UUID? // <--- New: Belongs to a Zone
    
    @Relationship(deleteRule: .cascade)
    var outgoingLinks: [InsightLink]? = []
    
    var type: InsightType {
        get { InsightType(rawValue: typeString) ?? .note }
        set { typeString = newValue.rawValue }
    }
    
    init(type: InsightType, content: String, title: String? = nil, category: String? = nil, localFileName: String? = nil, lat: Double? = nil, long: Double? = nil, locLabel: String? = nil, sentiment: Double? = nil, x: Double? = nil, y: Double? = nil) {
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
        self.outgoingLinks = []
    }
}

// 3. The "Thread"
@Model
final class InsightLink {
    var reason: String
    var strength: Double
    var sourceID: UUID
    var targetID: UUID
    
    init(sourceID: UUID, targetID: UUID, reason: String, strength: Double) {
        self.sourceID = sourceID; self.targetID = targetID; self.reason = reason; self.strength = strength
    }
}

// 4. The "Zone" (Container) <-- NEW
@Model
final class InsightZone {
    var id: UUID
    var title: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var colorHex: String
    
    init(title: String, x: Double, y: Double, width: Double = 300, height: Double = 300, colorHex: String = "0000FF") {
        self.id = UUID()
        self.title = title
        self.x = x; self.y = y; self.width = width; self.height = height
        self.colorHex = colorHex
    }
}

// 5. The "Drawing" (PencilKit) <-- NEW (Single instance per app or per board)
@Model
final class InsightDrawing {
    var id: UUID
    var data: Data // PKDrawing data
    
    init(data: Data) {
        self.id = UUID()
        self.data = data
    }
}
