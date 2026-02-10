import LocalAuthentication
import SwiftUI

class BiometricManager {
    static let shared = BiometricManager()
    
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        // Fix: Use .deviceOwnerAuthentication (No "WithBiometrics" suffix).
        // This policy automatically handles: FaceID -> Fail -> Enter Passcode.
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        completion(true)
                    } else {
                        // If user cancels or fails too many times
                        completion(false)
                    }
                }
            }
        } else {
            // No security set up on device (e.g. Simulator or no passcode)
            // In a real secure app, we might default to false, but for usability here:
            print("Biometrics not available: \(error?.localizedDescription ?? "Unknown")")
            DispatchQueue.main.async { completion(true) } // Allow access if no security exists
        }
    }
}
