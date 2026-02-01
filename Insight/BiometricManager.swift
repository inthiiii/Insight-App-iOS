import LocalAuthentication
import SwiftUI

// FIX: Removed ': ObservableObject' as we use callbacks, not listeners
class BiometricManager {
    static let shared = BiometricManager()
    
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        // Check availability
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            // Fallback to Device Passcode if FaceID fails or isn't set up
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                    DispatchQueue.main.async { completion(success) }
                }
            } else {
                // No security set up on device
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}
