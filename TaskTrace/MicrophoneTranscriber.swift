//
//  MicrophoneTranscriber.swift
//  TaskTrace
//
//  Created by Codex on 3/14/26.
//

import AVFAudio
import CoreAudio
import Foundation
import Speech
import os

private struct RecognitionBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

private actor MicrophoneRecognitionBufferActor {
    private var drainTask: Task<Void, Never>?

    init(
        bufferStream: AsyncStream<RecognitionBuffer>,
        appendBuffer: @escaping @Sendable (RecognitionBuffer) async -> Void
    ) {
        drainTask = Task {
            for await buffer in bufferStream {
                guard !Task.isCancelled else {
                    break
                }

                await appendBuffer(buffer)
            }
        }
    }

    func stop() {
        drainTask?.cancel()
        drainTask = nil
    }
}

private final class WeakMicrophoneTranscriberBox: @unchecked Sendable {
    weak var transcriber: MicrophoneTranscriber?

    init(transcriber: MicrophoneTranscriber) {
        self.transcriber = transcriber
    }
}

@MainActor
protocol MicrophoneTranscribing: AnyObject {
    func start(
        onTranscript: @escaping @Sendable (String) -> Void,
        onFailure: @escaping @Sendable (_ name: String, _ message: String, _ description: String) -> Void
    )
    func stop()
}

protocol MicrophoneAudioCapturing: AnyObject {
    func startCapture(onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws
    func stopCapture()
}

protocol SystemAudioCapturing: AnyObject {
    func startCapture(onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws
    func stopCapture()
}

@MainActor
protocol SpeechRecognitionTasking: AnyObject {
    func cancel()
}

@MainActor
protocol SpeechRecognizing: AnyObject {
    var supportsOnDeviceRecognition: Bool { get }
    func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> any SpeechRecognitionTasking
}

extension SFSpeechRecognitionTask: SpeechRecognitionTasking {}

@MainActor
final class SpeechRecognizer: SpeechRecognizing {
    private let recognizer: SFSpeechRecognizer

    init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    var supportsOnDeviceRecognition: Bool {
        recognizer.supportsOnDeviceRecognition
    }

    func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> any SpeechRecognitionTasking {
        recognizer.recognitionTask(with: request, resultHandler: resultHandler)
    }
}

final class MicrophoneAudioCaptureService: MicrophoneAudioCapturing, @unchecked Sendable {
    enum AudioCaptureError: LocalizedError {
        case noInputAvailable
        case captureStartFailed(OSStatus)
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .noInputAvailable:
                return "No audio input device available."
            case .captureStartFailed(let status):
                return "Failed to start microphone capture (\(status))."
            case .converterCreationFailed:
                return "Failed to create the microphone audio converter."
            }
        }
    }

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "microphone-capture")
    private let targetSampleRate: Double = 16_000
    private let audioQueue = DispatchQueue(label: "com.tasktrace.microphone.capture.device")
    private let listenerQueue = DispatchQueue(label: "com.tasktrace.microphone.capture.listener")
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceFormatListenerBlock: AudioObjectPropertyListenerBlock?
    private var isCapturing = false
    private var isReconfiguring = false
    private var audioConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var detectedSampleRate: Double = 0
    private var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    func startCapture(onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard !isCapturing else {
            logger.log("microphone capture start ignored because capture is already active")
            return
        }

        self.onAudioBuffer = onAudioBuffer

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                do {
                    try self.startCaptureOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopCapture() {
        guard isCapturing else {
            return
        }

        removePropertyListeners()

        let procID = self.ioProcID
        let deviceID = self.deviceID

        ioProcID = nil
        self.deviceID = kAudioObjectUnknown
        isCapturing = false
        isReconfiguring = false
        onAudioBuffer = nil
        audioConverter = nil
        inputFormat = nil
        targetFormat = nil
        detectedSampleRate = 0

        if let procID, deviceID != kAudioObjectUnknown {
            audioQueue.async {
                AudioDeviceStop(deviceID, procID)
                AudioDeviceDestroyIOProcID(deviceID, procID)
            }
        }

        logger.log("microphone capture stopped")
    }

    private func startCaptureOnQueue() throws {
        var inputDeviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &inputDeviceID
        )

        guard status == noErr, inputDeviceID != kAudioObjectUnknown else {
            throw AudioCaptureError.noInputAvailable
        }

        deviceID = inputDeviceID

        guard let streamFormat = getStreamFormat(for: deviceID) else {
            throw AudioCaptureError.noInputAvailable
        }

        detectedSampleRate = streamFormat.mSampleRate

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamFormat.mSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.converterCreationFailed
        }
        self.inputFormat = inputFormat

        guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1) else {
            throw AudioCaptureError.converterCreationFailed
        }
        self.targetFormat = targetFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        audioConverter = converter

        var ioProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, deviceID, nil) { [weak self] _, inputData, inputTime, _, _ in
            self?.handleAudioInput(inputData, timestamp: inputTime)
        }

        guard ioProcStatus == noErr, let ioProcID else {
            throw AudioCaptureError.captureStartFailed(ioProcStatus)
        }

        let startStatus = AudioDeviceStart(deviceID, ioProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            throw AudioCaptureError.captureStartFailed(startStatus)
        }

        self.ioProcID = ioProcID
        isCapturing = true
        installPropertyListeners()
        logger.log("microphone capture started deviceID=\(self.deviceID, privacy: .public)")
    }

    private func getStreamFormat(for deviceID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &format
        )

        return status == noErr ? format : nil
    }

    private func handleAudioInput(_ inputData: UnsafePointer<AudioBufferList>?, timestamp: UnsafePointer<AudioTimeStamp>?) {
        guard isCapturing,
              let inputData,
              let converter = audioConverter,
              let targetFormat,
              let inputFormat else {
            return
        }

        let inputBufferList = inputData.pointee
        let buffer = inputBufferList.mBuffers

        guard let data = buffer.mData, buffer.mDataByteSize > 0 else {
            return
        }

        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * buffer.mNumberChannels
        let frameCount = buffer.mDataByteSize / bytesPerFrame

        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount),
              let floatData = inputBuffer.floatChannelData else {
            return
        }

        inputBuffer.frameLength = frameCount

        let source = data.assumingMemoryBound(to: Float32.self)
        let mono = floatData[0]
        let channelCount = Int(buffer.mNumberChannels)

        if channelCount >= 2 {
            for index in 0..<Int(frameCount) {
                let left = source[index * channelCount]
                let right = source[index * channelCount + 1]
                mono[index] = (left + right) / 2
            }
        } else {
            memcpy(mono, source, Int(buffer.mDataByteSize))
        }

        let outputFrameCapacity = AVAudioFrameCount(ceil(Double(frameCount) * targetSampleRate / detectedSampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var conversionError: NSError?
        var consumedInput = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumedInput {
                status.pointee = .noDataNow
                return nil
            }

            consumedInput = true
            status.pointee = .haveData
            return inputBuffer
        }

        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

        if let conversionError {
            logger.error("microphone capture conversion failed error=\(String(describing: conversionError), privacy: .public)")
            return
        }

        onAudioBuffer?(outputBuffer)
    }

    private func installPropertyListeners() {
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.audioQueue.async {
                self?.handleConfigurationChange()
            }
        }
        defaultDeviceListenerBlock = deviceListenerBlock

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            listenerQueue,
            deviceListenerBlock
        )

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let formatListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.audioQueue.async {
                self?.handleConfigurationChange()
            }
        }
        deviceFormatListenerBlock = formatListenerBlock

        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &formatAddress,
            listenerQueue,
            formatListenerBlock
        )
    }

    private func removePropertyListeners() {
        if let defaultDeviceListenerBlock {
            var defaultDeviceAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultDeviceAddress,
                listenerQueue,
                defaultDeviceListenerBlock
            )

            self.defaultDeviceListenerBlock = nil
        }

        if let deviceFormatListenerBlock, deviceID != kAudioObjectUnknown {
            var formatAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamFormat,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &formatAddress,
                listenerQueue,
                deviceFormatListenerBlock
            )

            self.deviceFormatListenerBlock = nil
        }
    }

    private func handleConfigurationChange() {
        guard isCapturing, !isReconfiguring else {
            return
        }

        isReconfiguring = true
        logger.log("microphone capture configuration changed; rebuilding device pipeline")

        if let ioProcID, deviceID != kAudioObjectUnknown {
            AudioDeviceStop(deviceID, ioProcID)
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            self.ioProcID = nil
        }

        if let deviceFormatListenerBlock, deviceID != kAudioObjectUnknown {
            var formatAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamFormat,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &formatAddress,
                listenerQueue,
                deviceFormatListenerBlock
            )
            self.deviceFormatListenerBlock = nil
        }

        audioQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.reconfigureAfterChange(retryCount: 0)
        }
    }

    private func reconfigureAfterChange(retryCount: Int) {
        var newDeviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &newDeviceID
        )

        guard status == noErr, newDeviceID != kAudioObjectUnknown else {
            retryReconfiguration(after: retryCount)
            return
        }

        deviceID = newDeviceID

        guard let streamFormat = getStreamFormat(for: deviceID),
              streamFormat.mSampleRate > 0,
              streamFormat.mChannelsPerFrame > 0,
              let inputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: streamFormat.mSampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let targetFormat,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            retryReconfiguration(after: retryCount)
            return
        }

        detectedSampleRate = streamFormat.mSampleRate
        self.inputFormat = inputFormat
        audioConverter = converter

        var ioProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, deviceID, nil) { [weak self] _, inputData, inputTime, _, _ in
            self?.handleAudioInput(inputData, timestamp: inputTime)
        }

        guard ioProcStatus == noErr, let ioProcID else {
            retryReconfiguration(after: retryCount)
            return
        }

        let startStatus = AudioDeviceStart(deviceID, ioProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            retryReconfiguration(after: retryCount)
            return
        }

        self.ioProcID = ioProcID

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let formatListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.audioQueue.async {
                self?.handleConfigurationChange()
            }
        }
        deviceFormatListenerBlock = formatListenerBlock

        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &formatAddress,
            listenerQueue,
            formatListenerBlock
        )

        isReconfiguring = false
        logger.log("microphone capture device pipeline rebuilt deviceID=\(self.deviceID, privacy: .public)")
    }

    private func retryReconfiguration(after retryCount: Int) {
        let maxRetries = 3

        guard retryCount < maxRetries else {
            logger.error("microphone capture reconfiguration failed after \(retryCount + 1, privacy: .public) attempts")
            isReconfiguring = false
            return
        }

        let delay = Double(retryCount + 1)
        audioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reconfigureAfterChange(retryCount: retryCount + 1)
        }
    }

    deinit {
        guard isCapturing else {
            return
        }

        removePropertyListeners()

        if let ioProcID, deviceID != kAudioObjectUnknown {
            audioQueue.sync {
                AudioDeviceStop(deviceID, ioProcID)
                AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            }
        }
    }
}

@available(macOS 14.4, *)
final class SystemAudioCaptureService: SystemAudioCapturing, @unchecked Sendable {
    enum AudioCaptureError: LocalizedError {
        case tapCreationFailed(OSStatus)
        case aggregateDeviceFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case formatError
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let status):
                return "Failed to create the system audio tap (\(status))."
            case .aggregateDeviceFailed(let status):
                return "Failed to create the system audio aggregate device (\(status))."
            case .ioProcCreationFailed(let status):
                return "Failed to create the system audio callback (\(status))."
            case .deviceStartFailed(let status):
                return "Failed to start system audio capture (\(status))."
            case .formatError:
                return "Failed to read the system audio format."
            case .converterCreationFailed:
                return "Failed to create the system audio converter."
            }
        }
    }

    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "system-audio-capture")
    private let targetSampleRate: Double = 16_000
    private let tapUUID = UUID()
    private let audioQueue = DispatchQueue(label: "com.tasktrace.system-audio.capture.device")
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var isCapturing = false
    private var audioConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var detectedSampleRate: Double = 0
    private var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    func startCapture(onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard !isCapturing else {
            logger.log("system audio capture start ignored because capture is already active")
            return
        }

        self.onAudioBuffer = onAudioBuffer

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                do {
                    try self.startCaptureOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopCapture() {
        guard isCapturing else {
            return
        }

        let procID = self.ioProcID
        let aggregateDeviceID = self.aggregateDeviceID
        let tapID = self.tapID

        self.ioProcID = nil
        self.aggregateDeviceID = kAudioObjectUnknown
        self.tapID = kAudioObjectUnknown
        self.isCapturing = false
        self.onAudioBuffer = nil
        self.audioConverter = nil
        self.inputFormat = nil
        self.targetFormat = nil
        self.detectedSampleRate = 0

        audioQueue.async {
            if let procID, aggregateDeviceID != kAudioObjectUnknown {
                AudioDeviceStop(aggregateDeviceID, procID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            }

            if aggregateDeviceID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            }

            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }

        logger.log("system audio capture stopped")
    }

    private func startCaptureOnQueue() throws {
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = tapUUID
        tapDescription.name = "TaskTrace System Audio Tap"
        tapDescription.muteBehavior = .unmuted

        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapStatus == noErr else {
            throw AudioCaptureError.tapCreationFailed(tapStatus)
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "TaskTrace System Audio Tap Device",
            kAudioAggregateDeviceUIDKey as String: "tasktrace.systemaudio.\(tapUUID.uuidString)",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey as String: NSNumber(value: 1),
                    kAudioSubTapDriftCompensationQualityKey as String: NSNumber(value: kAudioAggregateDriftCompensationMaxQuality)
                ]
            ],
            kAudioAggregateDeviceTapAutoStartKey as String: true
        ]

        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateDeviceID
        )
        guard aggregateStatus == noErr else {
            cleanup()
            throw AudioCaptureError.aggregateDeviceFailed(aggregateStatus)
        }

        guard let streamFormat = getStreamFormat(for: aggregateDeviceID) else {
            cleanup()
            throw AudioCaptureError.formatError
        }

        detectedSampleRate = streamFormat.mSampleRate

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamFormat.mSampleRate,
            channels: AVAudioChannelCount(max(1, streamFormat.mChannelsPerFrame)),
            interleaved: false
        ) else {
            cleanup()
            throw AudioCaptureError.formatError
        }
        self.inputFormat = inputFormat

        guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1) else {
            cleanup()
            throw AudioCaptureError.converterCreationFailed
        }
        self.targetFormat = targetFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            cleanup()
            throw AudioCaptureError.converterCreationFailed
        }
        self.audioConverter = converter

        var ioProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil) { [weak self] _, inputData, inputTime, _, _ in
            self?.handleAudioInput(inputData, timestamp: inputTime)
        }
        guard ioProcStatus == noErr, let ioProcID else {
            cleanup()
            throw AudioCaptureError.ioProcCreationFailed(ioProcStatus)
        }

        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            cleanup()
            throw AudioCaptureError.deviceStartFailed(startStatus)
        }

        self.ioProcID = ioProcID
        self.isCapturing = true
        logger.log("system audio capture started deviceID=\(self.aggregateDeviceID, privacy: .public)")
    }

    private func getStreamFormat(for deviceID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &format
        )

        return status == noErr ? format : nil
    }

    private func handleAudioInput(_ inputData: UnsafePointer<AudioBufferList>?, timestamp: UnsafePointer<AudioTimeStamp>?) {
        guard isCapturing,
              let inputData,
              let converter = audioConverter,
              let inputFormat,
              let targetFormat else {
            return
        }

        let inputBufferList = inputData.pointee
        let buffer = inputBufferList.mBuffers

        guard let data = buffer.mData, buffer.mDataByteSize > 0 else {
            return
        }

        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * buffer.mNumberChannels
        let frameCount = buffer.mDataByteSize / bytesPerFrame

        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount),
              let floatData = inputBuffer.floatChannelData else {
            return
        }

        inputBuffer.frameLength = frameCount

        let source = data.assumingMemoryBound(to: Float32.self)
        let mono = floatData[0]
        let channelCount = Int(buffer.mNumberChannels)

        if channelCount >= 2 {
            for index in 0..<Int(frameCount) {
                let left = source[index * channelCount]
                let right = source[index * channelCount + 1]
                mono[index] = (left + right) / 2
            }
        } else {
            memcpy(mono, source, Int(buffer.mDataByteSize))
        }

        let outputFrameCapacity = AVAudioFrameCount(ceil(Double(frameCount) * targetSampleRate / detectedSampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var conversionError: NSError?
        var consumedInput = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumedInput {
                status.pointee = .noDataNow
                return nil
            }

            consumedInput = true
            status.pointee = .haveData
            return inputBuffer
        }

        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

        if let conversionError {
            logger.error("system audio capture conversion failed error=\(String(describing: conversionError), privacy: .public)")
            return
        }

        onAudioBuffer?(outputBuffer)
    }

    private func cleanup() {
        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }

        audioConverter = nil
        inputFormat = nil
        targetFormat = nil
        detectedSampleRate = 0
    }

    deinit {
        let procID = self.ioProcID
        let aggregateDeviceID = self.aggregateDeviceID
        let tapID = self.tapID

        guard procID != nil || aggregateDeviceID != kAudioObjectUnknown || tapID != kAudioObjectUnknown else {
            return
        }

        audioQueue.sync {
            if let procID, aggregateDeviceID != kAudioObjectUnknown {
                AudioDeviceStop(aggregateDeviceID, procID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            }

            if aggregateDeviceID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            }

            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }
}

final class AudioCaptureMixer: @unchecked Sendable {
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    private let lock = NSLock()
    private let minimumFrameCount = 1_600
    private let maximumFrameCount = 16_000
    private var onMixedBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var isRunning = false
    private var microphoneSamples: [Float] = []
    private var systemSamples: [Float] = []

    func start(onMixedBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        self.onMixedBuffer = onMixedBuffer
        self.isRunning = true
        self.microphoneSamples = []
        self.systemSamples = []
        lock.unlock()
    }

    func stop() {
        lock.lock()
        isRunning = false
        processLocked(flush: true)
        microphoneSamples = []
        systemSamples = []
        onMixedBuffer = nil
        lock.unlock()
    }

    func appendMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else {
            return
        }

        append(buffer, to: &microphoneSamples)
        trimIfNeeded(&microphoneSamples)
        processLocked()
    }

    func appendSystemBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else {
            return
        }

        append(buffer, to: &systemSamples)
        trimIfNeeded(&systemSamples)
        processLocked()
    }

    private func append(_ buffer: AVAudioPCMBuffer, to storage: inout [Float]) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return
        }

        storage.append(contentsOf: UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    private func trimIfNeeded(_ storage: inout [Float]) {
        let maximumBufferedFrames = maximumFrameCount * 2

        guard storage.count > maximumBufferedFrames else {
            return
        }

        storage.removeFirst(storage.count - maximumBufferedFrames)
    }

    private func processLocked(flush: Bool = false) {
        guard isRunning || flush else {
            return
        }

        let minimumSharedFrames = min(microphoneSamples.count, systemSamples.count)
        let maximumAvailableFrames = max(microphoneSamples.count, systemSamples.count)

        let framesToProcess = {
            if flush {
                return maximumAvailableFrames
            }

            if minimumSharedFrames >= minimumFrameCount {
                return min(minimumSharedFrames, maximumFrameCount)
            }

            if maximumAvailableFrames >= maximumFrameCount {
                return maximumFrameCount
            }

            return 0
        }()

        guard framesToProcess > 0,
              let outputBuffer = AVAudioPCMBuffer(
                  pcmFormat: outputFormat,
                  frameCapacity: AVAudioFrameCount(framesToProcess)
              ),
              let outputChannel = outputBuffer.floatChannelData?[0] else {
            return
        }

        outputBuffer.frameLength = AVAudioFrameCount(framesToProcess)

        for index in 0..<framesToProcess {
            let microphoneSample = index < microphoneSamples.count ? microphoneSamples[index] : 0
            let systemSample = index < systemSamples.count ? systemSamples[index] : 0
            outputChannel[index] = max(-1, min(1, microphoneSample + systemSample))
        }

        if !microphoneSamples.isEmpty {
            microphoneSamples.removeFirst(min(framesToProcess, microphoneSamples.count))
        }

        if !systemSamples.isEmpty {
            systemSamples.removeFirst(min(framesToProcess, systemSamples.count))
        }

        onMixedBuffer?(outputBuffer)
    }
}

final class MixedAudioCaptureService: MicrophoneAudioCapturing, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "audio-capture")
    private let microphoneCapture: any MicrophoneAudioCapturing
    private let systemAudioCapture: (any SystemAudioCapturing)?
    private let mixer: AudioCaptureMixer
    private let systemAudioEnabled: Bool
    private var isCapturing = false
    private var shouldMixSystemAudio = false

    init(
        microphoneCapture: any MicrophoneAudioCapturing = MicrophoneAudioCaptureService(),
        systemAudioCapture: (any SystemAudioCapturing)? = nil,
        mixer: AudioCaptureMixer = AudioCaptureMixer(),
        systemAudioEnabled: Bool = !UserDefaults.standard.bool(forKey: "disableSystemAudioCapture")
    ) {
        self.microphoneCapture = microphoneCapture
        self.systemAudioCapture = systemAudioCapture ?? {
            if #available(macOS 14.4, *) {
                return SystemAudioCaptureService()
            }

            return nil
        }()
        self.mixer = mixer
        self.systemAudioEnabled = systemAudioEnabled
    }

    func startCapture(onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard !isCapturing else {
            logger.log("mixed audio capture start ignored because capture is already active")
            return
        }

        isCapturing = true
        shouldMixSystemAudio = false

        if systemAudioEnabled, systemAudioCapture != nil {
            mixer.start(onMixedBuffer: onAudioBuffer)
            shouldMixSystemAudio = true
        }

        do {
            try await microphoneCapture.startCapture { [weak self] buffer in
                guard let self else {
                    return
                }

                if self.shouldMixSystemAudio {
                    self.mixer.appendMicrophoneBuffer(buffer)
                } else {
                    onAudioBuffer(buffer)
                }
            }
        } catch {
            isCapturing = false
            shouldMixSystemAudio = false
            mixer.stop()
            throw error
        }

        guard shouldMixSystemAudio, let systemAudioCapture else {
            if !systemAudioEnabled {
                logger.log("system audio capture disabled by user preference")
            } else {
                logger.log("system audio capture unavailable on this macOS version")
            }
            return
        }

        do {
            try await systemAudioCapture.startCapture { [weak self] buffer in
                self?.mixer.appendSystemBuffer(buffer)
            }
            logger.log("mixed audio capture started with microphone and system audio")
        } catch {
            shouldMixSystemAudio = false
            systemAudioCapture.stopCapture()
            mixer.stop()
            logger.error("system audio capture failed; continuing with microphone only error=\(String(describing: error), privacy: .public)")
        }
    }

    func stopCapture() {
        guard isCapturing else {
            return
        }

        isCapturing = false
        shouldMixSystemAudio = false
        microphoneCapture.stopCapture()
        systemAudioCapture?.stopCapture()
        mixer.stop()
        logger.log("mixed audio capture stopped")
    }
}

@MainActor
final class MicrophoneTranscriber: MicrophoneTranscribing {
    private let audioCapture: any MicrophoneAudioCapturing
    private let speechRecognizer: (any SpeechRecognizing)?
    private let restartDelay: Duration
    private let maximumRestartDelay: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: (any SpeechRecognitionTasking)?
    private var isRunning = false
    private var lastTranscript = ""
    private var onTranscript: (@Sendable (String) -> Void)?
    private var onFailure: (@Sendable (String, String, String) -> Void)?
    private var scheduledRestartTask: Task<Void, Never>?
    private var captureStartTask: Task<Void, Never>?
    private var recognitionGeneration = 0
    private var restartAttempt = 0
    private var bufferContinuation: AsyncStream<RecognitionBuffer>.Continuation?
    private var bufferAppender: MicrophoneRecognitionBufferActor?

    nonisolated static func transcriptDelta(previousTranscript: String, nextTranscript: String) -> String {
        let trimmedNextTranscript = nextTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedNextTranscript.isEmpty else {
            return ""
        }

        if previousTranscript.isEmpty {
            return trimmedNextTranscript
        }

        if trimmedNextTranscript.hasPrefix(previousTranscript) {
            return String(trimmedNextTranscript.dropFirst(previousTranscript.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let sharedPrefixCharacterCount = zip(previousTranscript, trimmedNextTranscript)
            .prefix { $0 == $1 }
            .count

        guard sharedPrefixCharacterCount > 0 else {
            return trimmedNextTranscript
        }

        let boundaryIndex = {
            let sharedPrefix = trimmedNextTranscript.prefix(sharedPrefixCharacterCount)

            if let whitespaceIndex = sharedPrefix.lastIndex(where: \.isWhitespace) {
                return trimmedNextTranscript.index(after: whitespaceIndex)
            }

            return trimmedNextTranscript.startIndex
        }()

        return String(trimmedNextTranscript[boundaryIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(locale: Locale = .current) {
        self.audioCapture = MixedAudioCaptureService()
        self.speechRecognizer = SFSpeechRecognizer(locale: locale).map(SpeechRecognizer.init)
        self.restartDelay = .milliseconds(750)
        self.maximumRestartDelay = .seconds(8)
        self.sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    }

    init(
        audioCapture: any MicrophoneAudioCapturing,
        speechRecognizer: (any SpeechRecognizing)?,
        restartDelay: Duration = .milliseconds(750),
        maximumRestartDelay: Duration = .seconds(8),
        sleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.audioCapture = audioCapture
        self.speechRecognizer = speechRecognizer
        self.restartDelay = restartDelay
        self.maximumRestartDelay = maximumRestartDelay
        self.sleep = sleep
    }

    func start(
        onTranscript: @escaping @Sendable (String) -> Void,
        onFailure: @escaping @Sendable (_ name: String, _ message: String, _ description: String) -> Void
    ) {
        guard !isRunning else {
            return
        }

        guard speechRecognizer != nil else {
            onFailure(
                "SpeechRecognitionUnavailable",
                "Speech recognition is not available for the current locale.",
                "TaskTrace could not create a speech recognizer for the current locale."
            )
            return
        }

        self.onTranscript = onTranscript
        self.onFailure = onFailure
        isRunning = true
        lastTranscript = ""
        restartAttempt = 0

        do {
            try replaceRecognitionTask()
        } catch {
            let onFailure = self.onFailure
            stop()
            onFailure?(
                "MicrophoneCaptureFailed",
                "TaskTrace could not start microphone capture.",
                String(describing: error)
            )
            return
        }

        let bufferStream = AsyncStream<RecognitionBuffer>(bufferingPolicy: .bufferingNewest(8)) { continuation in
            bufferContinuation = continuation
        }
        let transcriberBox = WeakMicrophoneTranscriberBox(transcriber: self)
        bufferAppender = MicrophoneRecognitionBufferActor(bufferStream: bufferStream) { recognitionBuffer in
            await MainActor.run {
                guard let transcriber = transcriberBox.transcriber,
                      transcriber.isRunning else {
                    return
                }

                transcriber.recognitionRequest?.append(recognitionBuffer.buffer)
            }
        }
        let continuation = bufferContinuation

        captureStartTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.audioCapture.startCapture { buffer in
                    continuation?.yield(RecognitionBuffer(buffer: buffer))
                }
            } catch {
                await MainActor.run {
                    guard self.isRunning else {
                        return
                    }

                    let onFailure = self.onFailure
                    self.stop()
                    onFailure?(
                        "MicrophoneCaptureFailed",
                        "TaskTrace could not start microphone capture.",
                        String(describing: error)
                    )
                }
            }
        }
    }

    func stop() {
        guard isRunning else {
            return
        }

        isRunning = false
        scheduledRestartTask?.cancel()
        scheduledRestartTask = nil
        captureStartTask?.cancel()
        captureStartTask = nil
        bufferContinuation?.finish()
        bufferContinuation = nil

        if let bufferAppender {
            Task {
                await bufferAppender.stop()
            }
            self.bufferAppender = nil
        }

        audioCapture.stopCapture()
        recognitionGeneration += 1
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        restartAttempt = 0
        lastTranscript = ""
        onTranscript = nil
        onFailure = nil
    }

    private func replaceRecognitionTask() throws {
        guard let speechRecognizer else {
            throw NSError(
                domain: "TaskTrace.MicrophoneTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available for the current locale."]
            )
        }

        recognitionGeneration += 1
        let generation = recognitionGeneration
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self,
                      self.isRunning,
                      self.recognitionGeneration == generation else {
                    return
                }

                if let result {
                    let transcript = result.bestTranscription.formattedString
                    let trimmedDelta = Self.transcriptDelta(
                        previousTranscript: self.lastTranscript,
                        nextTranscript: transcript
                    )

                    if !trimmedDelta.isEmpty {
                        self.onTranscript?(trimmedDelta)
                    }

                    self.lastTranscript = transcript

                    if result.isFinal {
                        self.lastTranscript = ""

                        do {
                            try self.replaceRecognitionTask()
                        } catch {
                            self.scheduleRestart(after: self.restartDelay)
                        }
                    }

                    return
                }

                if error != nil {
                    self.lastTranscript = ""
                    self.scheduleRestart(after: self.restartDelay)
                }
            }
        }
    }

    private func scheduleRestart(after delay: Duration) {
        guard isRunning else {
            return
        }

        scheduledRestartTask?.cancel()
        scheduledRestartTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.sleep(delay)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self.performScheduledRestart()
            }
        }
    }

    private func performScheduledRestart() {
        guard isRunning else {
            return
        }

        scheduledRestartTask = nil

        do {
            try replaceRecognitionTask()
            restartAttempt = 0
        } catch {
            restartAttempt += 1

            if restartAttempt == 1 {
                scheduleRestart(after: .seconds(2))
            } else if restartAttempt == 2 {
                scheduleRestart(after: .seconds(4))
            } else {
                scheduleRestart(after: maximumRestartDelay)
            }
        }
    }
}
