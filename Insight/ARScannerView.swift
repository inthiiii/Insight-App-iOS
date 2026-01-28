import SwiftUI
import Vision
import VisionKit

struct ARScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        // Use Apple's native DataScanner
        // It automatically handles Text highlighting (Yellow boxes)
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false, // Focus on one block at a time
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        
        scanner.delegate = context.coordinator
        
        try? scanner.startScanning()
        
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: ARScannerView
        var lastFoundTime: Date = Date()
        
        init(_ parent: ARScannerView) {
            self.parent = parent
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(addedItems)
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(updatedItems)
        }
        
        func processItems(_ items: [RecognizedItem]) {
            // Throttle results: Only process once every 0.5 seconds to prevent UI flickering
            guard Date().timeIntervalSince(lastFoundTime) > 0.5 else { return }
            
            for item in items {
                switch item {
                case .text(let text):
                    // Pass the transcript to the smart matcher
                    parent.onFound(text.transcript)
                    lastFoundTime = Date()
                default: break
                }
            }
        }
    }
}
