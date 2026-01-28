import SwiftUI
import Vision
import VisionKit

class VisionManager {
    
    // 1. The Reader (OCR)
    // Takes an image, returns the text found on it
    static func extractText(from image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }
        
        // Setup the request
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                completion("")
                return
            }
            
            // Combine all the lines of text into one string
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            
            DispatchQueue.main.async {
                completion(text)
            }
        }
        
        // Configure for accuracy
        request.recognitionLevel = .accurate
        
        // Run the handler
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    // 2. The Storage (File System)
    // Saves the image to the app's "Documents" folder and returns the filename
    static func saveImageToDisk(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        let filename = UUID().uuidString + ".jpg"
        let url = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try data.write(to: url)
            return filename
        } catch {
            print("Error saving image: \(error)")
            return nil
        }
    }
    
    // Helper to find where to save
    static func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // Helper to load image back (for display later)
    static func loadImageFromDisk(filename: String) -> UIImage? {
        let url = getDocumentsDirectory().appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }
}
