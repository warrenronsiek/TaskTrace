//
//  MicrophoneTranscriberTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/30/26.
//

import AVFAudio
import Foundation
import Speech
import Testing
@testable import TaskTrace

@MainActor
struct MicrophoneTranscriberTests {
    @Test("starting the transcriber starts passive microphone capture")
    func startStartsMicrophoneCapture() async {
        let capture = FakeMicrophoneAudioCapture()
        let transcriber = MicrophoneTranscriber(
            audioCapture: capture,
            speechRecognizer: FakeSpeechRecognizer(),
            restartDelay: .milliseconds(1),
            maximumRestartDelay: .seconds(1),
            sleep: { _ in }
        )

        transcriber.start(onTranscript: { _ in }, onFailure: { _, _, _ in })
        try? await Task.sleep(for: .milliseconds(20))

        #expect(capture.startCount == 1)
    }

    @Test("stopping the transcriber stops passive microphone capture")
    func stopStopsMicrophoneCapture() async {
        let capture = FakeMicrophoneAudioCapture()
        let transcriber = MicrophoneTranscriber(
            audioCapture: capture,
            speechRecognizer: FakeSpeechRecognizer(),
            restartDelay: .milliseconds(1),
            maximumRestartDelay: .seconds(1),
            sleep: { _ in }
        )

        transcriber.start(onTranscript: { _ in }, onFailure: { _, _, _ in })
        try? await Task.sleep(for: .milliseconds(20))
        transcriber.stop()

        #expect(capture.stopCount == 1)
    }

    @Test("speech recognition errors replace the recognition task without restarting capture")
    func speechRecognitionErrorReplacesRecognitionTask() async {
        let capture = FakeMicrophoneAudioCapture()
        let recognizer = FakeSpeechRecognizer()
        let transcriber = MicrophoneTranscriber(
            audioCapture: capture,
            speechRecognizer: recognizer,
            restartDelay: .milliseconds(1),
            maximumRestartDelay: .seconds(1),
            sleep: { _ in }
        )

        transcriber.start(onTranscript: { _ in }, onFailure: { _, _, _ in })
        try? await Task.sleep(for: .milliseconds(20))
        recognizer.emitError(NSError(domain: "TaskTraceTests", code: 42))
        try? await Task.sleep(for: .milliseconds(20))

        #expect(recognizer.taskCreationCount == 2)
    }

    @Test("mixed audio capture starts system audio when available")
    func mixedAudioCaptureStartsSystemAudio() async throws {
        let microphoneCapture = FakeMicrophoneAudioCapture()
        let systemCapture = FakeSystemAudioCapture()
        let mixedCapture = MixedAudioCaptureService(
            microphoneCapture: microphoneCapture,
            systemAudioCapture: systemCapture,
            mixer: AudioCaptureMixer(),
            systemAudioEnabled: true
        )

        try await mixedCapture.startCapture { _ in }

        #expect(systemCapture.startCount == 1)
    }

    @Test("mixed audio capture keeps microphone capture running when system audio fails")
    func mixedAudioCaptureFallsBackToMicrophone() async throws {
        let microphoneCapture = FakeMicrophoneAudioCapture()
        let systemCapture = FakeSystemAudioCapture(startError: NSError(domain: "TaskTraceTests", code: 7))
        let mixedCapture = MixedAudioCaptureService(
            microphoneCapture: microphoneCapture,
            systemAudioCapture: systemCapture,
            mixer: AudioCaptureMixer(),
            systemAudioEnabled: true
        )

        try await mixedCapture.startCapture { _ in }

        #expect(microphoneCapture.startCount == 1)
    }

    @Test("audio mixer sums microphone and system audio into one mono stream")
    func audioMixerSumsMicrophoneAndSystemAudio() {
        let mixer = AudioCaptureMixer()
        var renderedFirstSample: Float?
        mixer.start { buffer in
            renderedFirstSample = buffer.floatChannelData?[0][0]
        }

        mixer.appendMicrophoneBuffer(makeBuffer(repeating: 0.25, frameCount: 1_600))
        mixer.appendSystemBuffer(makeBuffer(repeating: 0.25, frameCount: 1_600))

        #expect(renderedFirstSample == 0.5)
    }

    @Test("transcript delta emits only the revised tail when a partial result edits one word")
    func transcriptDeltaEmitsOnlyTheRevisedTail() {
        let previousTranscript = "A few years later this is another computer that was built and this generalize the work that was"
        let nextTranscript = "A few years later this is another computer that was built and this generalized the work that was done on the Harvard mark one"

        let delta = MicrophoneTranscriber.transcriptDelta(
            previousTranscript: previousTranscript,
            nextTranscript: nextTranscript
        )

        #expect(delta == "generalized the work that was done on the Harvard mark one")
    }

    @Test("transcript delta returns the full transcript when no shared prefix exists")
    func transcriptDeltaReturnsFullTranscriptWhenNoSharedPrefixExists() {
        let delta = MicrophoneTranscriber.transcriptDelta(
            previousTranscript: "vacuum tubes and relays",
            nextTranscript: "IBM made something called the 1401"
        )

        #expect(delta == "IBM made something called the 1401")
    }
}

private final class FakeMicrophoneAudioCapture: MicrophoneAudioCapturing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    private let startError: Error?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func startCapture(onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        if let startError {
            throw startError
        }

        startCount += 1
        self.onAudioBuffer = onAudioBuffer
    }

    func stopCapture() {
        stopCount += 1
        onAudioBuffer = nil
    }
}

private final class FakeSystemAudioCapture: SystemAudioCapturing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    private let startError: Error?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func startCapture(onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        if let startError {
            throw startError
        }

        startCount += 1
        self.onAudioBuffer = onAudioBuffer
    }

    func stopCapture() {
        stopCount += 1
        onAudioBuffer = nil
    }
}

@MainActor
private final class FakeSpeechRecognitionTask: SpeechRecognitionTasking {
    func cancel() {}
}

@MainActor
private final class FakeSpeechRecognizer: SpeechRecognizing {
    let supportsOnDeviceRecognition = false
    private var handlers: [(SFSpeechRecognitionResult?, Error?) -> Void] = []
    private(set) var taskCreationCount = 0

    func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> any SpeechRecognitionTasking {
        taskCreationCount += 1
        handlers.append(resultHandler)
        return FakeSpeechRecognitionTask()
    }

    func emitError(_ error: Error) {
        handlers.last?(nil, error)
    }
}

private func makeBuffer(repeating sample: Float, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let channel = buffer.floatChannelData![0]

    for index in 0..<Int(frameCount) {
        channel[index] = sample
    }

    return buffer
}
