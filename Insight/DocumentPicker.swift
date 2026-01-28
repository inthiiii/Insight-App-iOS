import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var fileContent: String
    @Binding var fileName: String
    var onPick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedUrl = urls.first else { return }
            
            // 1. Secure Access
            guard selectedUrl.startAccessingSecurityScopedResource() else { return }
            
            defer { selectedUrl.stopAccessingSecurityScopedResource() }
            
            // 2. CRITICAL FIX: Copy to a temp location before reading
            // This prevents "Permission Denied" errors from PDFKit
            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(selectedUrl.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: tempUrl.path) {
                    try FileManager.default.removeItem(at: tempUrl)
                }
                try FileManager.default.copyItem(at: selectedUrl, to: tempUrl)
                
                // 3. Read from the Temp File
                if let pdfDocument = PDFDocument(url: tempUrl) {
                    var fullText = ""
                    let pageCount = pdfDocument.pageCount
                    
                    for i in 0..<pageCount {
                        if let page = pdfDocument.page(at: i) {
                            fullText += (page.string ?? "") + "\n"
                        }
                    }
                    
                    parent.fileName = selectedUrl.lastPathComponent
                    parent.fileContent = fullText
                    parent.onPick()
                }
                
                // Cleanup temp file
                try? FileManager.default.removeItem(at: tempUrl)
                
            } catch {
                print("Error processing PDF: \(error)")
            }
        }
    }
}
