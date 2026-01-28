import Foundation
import EventKit
import SwiftUI

class SmartActionManager {
    static let shared = SmartActionManager()
    let eventStore = EKEventStore()
    
    // 1. The Detector: Finds dates in text
    func detectDates(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        // Return the first valid date found
        return matches?.first?.date
    }
    
    // 2. The Actor: Adds to Calendar
    func addEvent(title: String, date: Date, completion: @escaping (Bool, String?) -> Void) {
        // Request Access first
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            guard granted, let self = self else {
                DispatchQueue.main.async { completion(false, "Permission Denied") }
                return
            }
            
            let event = EKEvent(eventStore: self.eventStore)
            event.title = "Insight: \(title.prefix(20))..." // Short title
            event.startDate = date
            event.endDate = date.addingTimeInterval(3600) // Default 1 hour
            event.calendar = self.eventStore.defaultCalendarForNewEvents
            
            // Add Note link
            event.notes = "Generated from Insight:\n\(title)"
            
            do {
                try self.eventStore.save(event, span: .thisEvent)
                DispatchQueue.main.async { completion(true, nil) }
            } catch {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }
}
