import SwiftUI
import Foundation
import Speech
import AVFoundation

@Observable
class AudioManager: NSObject, SFSpeechRecognizerDelegate {
    var isRecording = false
    var liveTranscript: String = "" // <--- FIXED: This was missing
    var liveSamples: [Float] = []
    var audioPermissionGranted = false
    
    // Internal Data
    private var recordedWords: [TranscriptWord] = []
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    // File saving
    private var audioRecorder: AVAudioRecorder?
    private var tempURL: URL?
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { self.audioPermissionGranted = (status == .authorized) }
        }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }
    
    // FIXED: Updated signature to return all data needed for Echo
    func toggleRecording(onFinish: @escaping (String, URL?, [TranscriptWord], [Float]) -> Void) {
        if isRecording {
            stopRecording(onFinish: onFinish)
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // Reset
        liveTranscript = ""
        liveSamples = []
        recordedWords = []
        
        // 1. Setup Session
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        
        // 2. Setup File Recording
        let fileName = UUID().uuidString + ".m4a"
        let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docPath.appendingPathComponent(fileName)
        self.tempURL = url
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
        
        // 3. Setup Recognition
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }
        request.shouldReportPartialResults = true
        
        task = recognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                self.liveTranscript = result.bestTranscription.formattedString // <--- Populates the UI
                self.recordedWords = result.bestTranscription.segments.map { segment in
                    TranscriptWord(text: segment.substring, startTime: segment.timestamp, endTime: segment.timestamp + segment.duration)
                }
            }
            if error != nil { self.stopRecording(onFinish: { _,_,_,_ in }) }
        }
        
        // 4. Install Tap for Buffer (Speech + Metering)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request?.append(buffer)
            
            // Calculate Metering (RMS)
            let channelData = buffer.floatChannelData?[0]
            let frameLength = UInt(buffer.frameLength)
            
            if let data = channelData {
                var sum: Float = 0
                for i in 0..<Int(frameLength) { sum += abs(data[i]) }
                let avg = sum / Float(frameLength)
                
                DispatchQueue.main.async {
                    self.liveSamples.append(min(avg * 5.0, 1.0))
                }
            }
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        withAnimation { isRecording = true }
    }
    
    private func stopRecording(onFinish: @escaping (String, URL?, [TranscriptWord], [Float]) -> Void) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        audioRecorder?.stop()
        
        withAnimation { isRecording = false }
        
        if !liveTranscript.isEmpty {
            let samples = compressSamples(liveSamples, targetCount: 100)
            onFinish(liveTranscript, tempURL, recordedWords, samples)
        }
    }
    
    private func compressSamples(_ samples: [Float], targetCount: Int) -> [Float] {
        guard samples.count > targetCount else { return samples }
        let chunkSize = samples.count / targetCount
        var result: [Float] = []
        for i in 0..<targetCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            let chunk = samples[start..<end]
            let avg = chunk.reduce(0, +) / Float(chunk.count)
            result.append(avg)
        }
        return result
    }
}
