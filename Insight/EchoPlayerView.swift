import SwiftUI
import AVFoundation

struct EchoPlayerView: View {
    let item: InsightItem
    let audioURL: URL
    
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var timer: Timer?
    @State private var playbackRate: Float = 1.0
    
    // Extract samples or use a default flat line if empty
    var samples: [Float] {
        if let s = item.waveformSamples, !s.isEmpty { return s }
        return Array(repeating: 0.1, count: 50) // Fallback flat line
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            
            // 1. HEADER (Title & Time)
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue.gradient)
                    .font(.caption)
                    .padding(6)
                    .background(.blue.opacity(0.1))
                    .clipShape(Circle())
                
                Text(item.title ?? "Voice Note")
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal)
            .padding(.top, 15)
            
            // 2. LIQUID WAVEFORM VISUALIZER
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // A. Inactive Wave (Dark Track)
                    MirroredWaveform(samples: samples)
                        .fill(Color.white.opacity(0.1))
                    
                    // B. Active Wave (Neon Gradient) - Masked by Time
                    MirroredWaveform(samples: samples)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .mask(
                            GeometryReader { maskGeo in
                                Rectangle()
                                    .frame(width: maskGeo.size.width * CGFloat(currentTime / duration))
                            }
                        )
                        .shadow(color: .blue.opacity(0.5), radius: 8) // Neon Glow
                    
                    // C. The Glowing Dot (Scrubber)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .white, radius: 5)
                        .offset(x: (geo.size.width * CGFloat(currentTime / duration)) - 6)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let progress = value.location.x / geo.size.width
                                    let time = Double(progress) * duration
                                    seek(to: time)
                                }
                        )
                }
            }
            .frame(height: 50) // Compact Height
            .padding(.horizontal)
            
            // 3. CONTROLS (Compact Row)
            HStack(spacing: 20) {
                // Speed
                Button(action: toggleSpeed) {
                    Text("\(String(format: "%.1f", playbackRate))x")
                        .font(.caption).bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Rewind 10s
                Button(action: { seek(to: currentTime - 10) }) {
                    Image(systemName: "gobackward.10")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                // Play/Pause (Center Stage)
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue.gradient)
                        .shadow(color: .blue.opacity(0.3), radius: 10)
                        .contentTransition(.symbolEffect(.replace))
                }
                
                // Forward 10s
                Button(action: { seek(to: currentTime + 10) }) {
                    Image(systemName: "goforward.10")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Total Duration
                Text(formatTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 15)
        }
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear(perform: setupAudio)
        .onDisappear(perform: stopAudio)
    }
    
    // --- VISUALIZER SHAPE ---
    // Creates a mirrored "Soundcloud" style wave
    struct MirroredWaveform: Shape {
        let samples: [Float]
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let midY = rect.height / 2
            let width = rect.width
            let count = samples.count
            let step = width / CGFloat(max(count, 1))
            
            // Draw Top Half
            path.move(to: CGPoint(x: 0, y: midY))
            for (i, sample) in samples.enumerated() {
                let x = CGFloat(i) * step
                // Smooth the amplitude visually
                let amp = CGFloat(sample) * (rect.height * 0.8)
                // Use Curve for liquid look
                path.addLine(to: CGPoint(x: x, y: midY - amp / 2))
            }
            path.addLine(to: CGPoint(x: width, y: midY))
            
            // Draw Bottom Half (Mirrored)
            for (i, sample) in samples.reversed().enumerated() {
                let x = width - (CGFloat(i) * step)
                let amp = CGFloat(sample) * (rect.height * 0.8)
                path.addLine(to: CGPoint(x: x, y: midY + amp / 2))
            }
            path.closeSubpath()
            
            return path
        }
    }
    
    // --- AUDIO LOGIC ---
    
    func setupAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        
        do {
            player = try AVAudioPlayer(contentsOf: audioURL)
            player?.enableRate = true
            player?.prepareToPlay()
            duration = player?.duration ?? 1
        } catch {
            print("Audio Load Error: \(error)")
        }
    }
    
    func togglePlay() {
        guard let player = player else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        if player.isPlaying {
            player.pause()
            timer?.invalidate()
            isPlaying = false
        } else {
            player.rate = playbackRate
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.timer?.invalidate()
                }
            }
        }
    }
    
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let safeTime = max(0, min(time, duration))
        player.currentTime = safeTime
        currentTime = safeTime
        // Haptic feedback for seeking
        if abs(currentTime - safeTime) > 0.1 {
             UISelectionFeedbackGenerator().selectionChanged()
        }
    }
    
    func toggleSpeed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if playbackRate == 1.0 { playbackRate = 1.5 }
        else if playbackRate == 1.5 { playbackRate = 2.0 }
        else { playbackRate = 1.0 }
        
        if isPlaying { player?.rate = playbackRate }
    }
    
    func stopAudio() {
        player?.stop()
        timer?.invalidate()
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
