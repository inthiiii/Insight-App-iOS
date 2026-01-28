import Foundation
import CoreLocation
import SwiftUI


@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    var currentLocation: CLLocation?
    var currentLabel: String = "Unknown Location"
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        self.currentLocation = loc
        
        // Reverse Geocode to get a readable name (only if moved significantly)
        // We do this throttled to save battery/data
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, error in
            if let place = placemarks?.first {
                // Try to get a specific name (e.g., SLIIT), or fall back to City
                self.currentLabel = place.name ?? place.locality ?? "Unknown Location"
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("GPS Error: \(error.localizedDescription)")
    }
}
