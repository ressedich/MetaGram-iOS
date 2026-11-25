import Foundation
import TelegramCore

/// MetaGram "Voice Effect" for voice messages: changes the recorded voice before it is encoded, so the message is an
/// ordinary voice message that sounds changed for everyone. Runs on the device, sample by sample, keeping its state
/// across the recorder's 20 ms packets (16-bit mono PCM at 48 kHz).
final class MetaGramVoiceEffectProcessor {
    private let effect: MetaGramSettings.VoiceEffect
    private let sampleRate: Double = 48000.0

    // pitch shifting: two read heads move through a delay line at a different speed than the write head, each faded
    // in and out (sin² windows half a cycle apart, which always sum to 1), so the voice is heard higher or lower
    // without changing its length
    private var delayLine: [Float]
    private var writeIndex = 0
    private var phase: Double = 0.0
    private let pitchRatio: Double
    private let windowLength: Double = 2400.0 // 50 ms

    // robot: ring modulation
    private var modulatorPhase: Double = 0.0
    private let modulatorFrequency: Double = 50.0

    // echo: a delay with feedback
    private var echoLine: [Float]
    private var echoIndex = 0
    private let echoFeedback: Float = 0.38
    private let echoMix: Float = 0.45

    init?(effect: MetaGramSettings.VoiceEffect) {
        if effect == .none {
            return nil
        }
        self.effect = effect
        switch effect {
        case .low:
            self.pitchRatio = 0.72
        case .high:
            self.pitchRatio = 1.55
        default:
            self.pitchRatio = 1.0
        }
        self.delayLine = Array(repeating: 0.0, count: 8192)
        self.echoLine = Array(repeating: 0.0, count: Int(48000.0 * 0.25))
    }

    /// Changes `count` samples in place.
    func process(samples: UnsafeMutablePointer<Int16>, count: Int) {
        for i in 0 ..< count {
            let input = Float(samples[i]) / 32768.0
            let output: Float
            switch self.effect {
            case .low, .high:
                output = self.pitchShift(input)
            case .robot:
                output = self.robot(input)
            case .echo:
                output = self.echo(input)
            case .none:
                output = input
            }
            let clamped = max(-1.0, min(1.0, output))
            samples[i] = Int16(clamped * 32767.0)
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
