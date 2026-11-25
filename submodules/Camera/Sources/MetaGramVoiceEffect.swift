import Foundation
import CoreMedia
import AVFoundation

/// MetaGram "Voice Effect": changes a recorded voice as it is captured, for voice messages (the audio recorder) and
/// round video messages (the camera's audio track). The message is an ordinary one that sounds changed for everyone.
/// Runs on the device, sample by sample, keeping its state across buffers.
///
/// The effect is the app's MetaGram setting `metagram.voice.effect` (TelegramCore's `MetaGramSettings.VoiceEffect`):
/// 0 none, 1 low, 2 high, 3 robot, 4 echo, 5 female.
public final class MetaGramVoiceEffectProcessor {
    public static let settingsKey = "metagram.voice.effect"

    /// The effect currently chosen in MetaGram's settings.
    public static var currentEffectRawValue: Int {
        return UserDefaults.standard.integer(forKey: settingsKey)
    }

    private enum Effect: Int {
        case low = 1
        case high = 2
        case robot = 3
        case echo = 4
        case female = 5
    }

    private let effect: Effect
    private let sampleRate: Double

    // pitch shifting: two read heads move through a delay line at a different speed than the write head, each faded
    // in and out (sin² windows half a cycle apart, which always sum to 1), so the voice is heard higher or lower
    // without changing its length
    private var delayLine: [Float]
    private var writeIndex = 0
    private var phase: Double = 0.0
    private let pitchRatio: Double
    private let windowLength: Double

    // female: a gentle high-shelf (the pitch shift alone darkens a raised voice) and a little breath
    private var shelfState: Float = 0.0

    // robot: ring modulation
    private var modulatorPhase: Double = 0.0
    private let modulatorFrequency: Double = 50.0

    // echo: a delay with feedback
    private var echoLine: [Float]
    private var echoIndex = 0
    private let echoFeedback: Float = 0.38
    private let echoMix: Float = 0.45

    /// Nil for "none" or an unknown value.
    public init?(effectRawValue: Int, sampleRate: Double) {
        guard let effect = Effect(rawValue: effectRawValue), sampleRate > 0.0 else {
            return nil
        }
        self.effect = effect
        self.sampleRate = sampleRate
        switch effect {
        case .low:
            self.pitchRatio = 0.72
        case .high:
            self.pitchRatio = 1.55
        case .female:
            self.pitchRatio = 1.34
        default:
            self.pitchRatio = 1.0
        }
        // 50 ms windows; shorter for the female voice, which keeps it smoother
        self.windowLength = sampleRate * (effect == .female ? 0.035 : 0.05)
        self.delayLine = Array(repeating: 0.0, count: max(8192, Int(sampleRate * 0.2)))
        self.echoLine = Array(repeating: 0.0, count: max(1, Int(sampleRate * 0.25)))
    }

    /// Changes `count` 16-bit samples in place, one channel (`stride` 1) or the first of interleaved channels, copied
    /// to the others.
    public func process(samples: UnsafeMutablePointer<Int16>, count: Int, channels: Int = 1) {
        let channels = max(1, channels)
        var i = 0
        while i < count {
            let input = Float(samples[i]) / 32768.0
            let output = max(-1.0, min(1.0, self.processSample(input)))
            let value = Int16(output * 32767.0)
            for c in 0 ..< channels where i + c < count {
                samples[i + c] = value
            }
            i += channels
        }
    }

    /// As `process(samples:)`, for 32-bit float samples.
    public func process(floatSamples: UnsafeMutablePointer<Float>, count: Int, channels: Int = 1) {
        let channels = max(1, channels)
        var i = 0
        while i < count {
            let output = max(-1.0, min(1.0, self.processSample(floatSamples[i])))
            for c in 0 ..< channels where i + c < count {
                floatSamples[i + c] = output
            }
            i += channels
        }
    }

    /// Changes the linear PCM audio of a capture sample buffer in place (16-bit integer or 32-bit float, interleaved).
    /// Other formats are left as they are.
    public func process(sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), let description = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee, description.mFormatID == kAudioFormatLinearPCM else {
            return
        }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr, let dataPointer else {
            return
        }
        let isNonInterleaved = (description.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = isNonInterleaved ? 1 : Int(description.mChannelsPerFrame)
        let isFloat = (description.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if isFloat && description.mBitsPerChannel == 32 {
            dataPointer.withMemoryRebound(to: Float.self, capacity: length / 4) { pointer in
                self.process(floatSamples: pointer, count: length / 4, channels: channels)
            }
        } else if !isFloat && description.mBitsPerChannel == 16 {
            dataPointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { pointer in
                self.process(samples: pointer, count: length / 2, channels: channels)
            }
        }
    }

    private func processSample(_ input: Float) -> Float {
        switch self.effect {
        case .low, .high:
            return self.pitchShift(input)
        case .female:
            let shifted = self.pitchShift(input)
            // high-shelf: add back some of what a one-pole low-pass removes
            self.shelfState += 0.25 * (shifted - self.shelfState)
            return shifted + (shifted - self.shelfState) * 0.35
        case .robot:
            return self.robot(input)
        case .echo:
            return self.echo(input)
        }
    }

    private func readDelayed(_ delay: Double) -> Float {
        let size = self.delayLine.count
        var position = Double(self.writeIndex) - delay
        while position < 0.0 {
            position += Double(size)
        }
        let index = Int(position)
        let fraction = Float(position - Double(index))
        let a = self.delayLine[index % size]
        let b = self.delayLine[(index + 1) % size]
        return a + (b - a) * fraction
    }

    private func pitchShift(_ input: Float) -> Float {
        self.delayLine[self.writeIndex] = input

        // the delay grows (lower voice) or shrinks (higher voice) by (1 - ratio) samples per sample
        self.phase += (1.0 - self.pitchRatio) / self.windowLength
        self.phase -= floor(self.phase)

        let phaseA = self.phase
        var phaseB = self.phase + 0.5
        phaseB -= floor(phaseB)

        let minimumDelay = 8.0
        let delayA = minimumDelay + phaseA * self.windowLength
        let delayB = minimumDelay + phaseB * self.windowLength
        let gainA = Float(sin(Double.pi * phaseA) * sin(Double.pi * phaseA))
        let gainB = Float(sin(Double.pi * phaseB) * sin(Double.pi * phaseB))

        let output = self.readDelayed(delayA) * gainA + self.readDelayed(delayB) * gainB

        self.writeIndex = (self.writeIndex + 1) % self.delayLine.count
        return output
    }

    private func robot(_ input: Float) -> Float {
        let modulator = Float(sin(2.0 * Double.pi * self.modulatorPhase))
        self.modulatorPhase += self.modulatorFrequency / self.sampleRate
        self.modulatorPhase -= floor(self.modulatorPhase)
        // ring modulation, with a little of the dry voice to keep words clear
        return (input * modulator) * 1.4 + input * 0.15
    }

    private func echo(_ input: Float) -> Float {
        let delayed = self.echoLine[self.echoIndex]
        self.echoLine[self.echoIndex] = input + delayed * self.echoFeedback
        self.echoIndex = (self.echoIndex + 1) % self.echoLine.count
        return input + delayed * self.echoMix
    }
}
