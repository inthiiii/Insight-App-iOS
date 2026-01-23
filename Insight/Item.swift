//
//  Item.swift
//  Insight
//
//  Created by M.Ihthisham Irshad on 1/23/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
