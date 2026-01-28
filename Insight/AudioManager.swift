import SwiftUI
import Foundation
import Speech
import AVFoundation

@Observable
class AudioManager: NSObject, SFSpeechRecognizerDelegate {
    var isRecording = false
    var transcript: String = ""
    var audioPermissionGranted = false
    
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.audioPermissionGranted = (status == .authorized)
            }
        }
    }
    
    func toggleRecording(onFinish: @escaping (String) -> Void) {
        if isRecording {
            stopRecording(onFinish: onFinish)
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // Reset
        transcript = ""
        
        // 1. Setup Audio Engine
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }
        
        // CRITICAL: Force Offline Recognition
        request.requiresOnDeviceRecognition = true
        
        // 2. Start Recognition Task
        task = recognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                // Update transcript live as you speak
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil {
                self.stopRecording(onFinish: { _ in })
            }
        }
        
        // 3. Install Tap on Mic
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        // 4. Start Engine
        audioEngine.prepare()
        try? audioEngine.start()
        
        withAnimation { isRecording = true }
    }
    
    private func stopRecording(onFinish: @escaping (String) -> Void) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        
        withAnimation { isRecording = false }
        
        // Send the final text back to the app to be saved
        if !transcript.isEmpty {
            onFinish(transcript)
        }
    }
}
