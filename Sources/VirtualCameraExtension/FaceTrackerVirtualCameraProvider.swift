import AVFoundation
import CoreMediaIO
import Foundation
import IOKit.audio
import os.log

private let stripeHeight = 10
private let frameRate = 30

final class FaceTrackerVirtualCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!

    private var streamSource: FaceTrackerVirtualCameraStreamSource!
    private var streamingCounter: UInt32 = 0
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(
        label: "com.facetracker.virtualcamera.timer",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .workItem,
        target: .global(qos: .userInteractive)
    )

    private var videoDescription: CMFormatDescription!
    private var bufferPool: CVPixelBufferPool!
    private var bufferAuxAttributes: NSDictionary!
    private var stripeStartRow: UInt32 = 0
    private var stripeAscending = false

    init(localizedName: String) {
        super.init()

        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: UUID(uuidString: "27B50A2C-4EC2-4B4F-8B57-EA8F6B6A7E10")!,
            legacyDeviceID: "com.facetracker.virtualcamera.device",
            source: self
        )

        let dimensions = CMVideoDimensions(width: 1280, height: 720)
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: dimensions.width,
            height: dimensions.height,
            extensions: nil,
            formatDescriptionOut: &videoDescription
        )

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: dimensions.width,
            kCVPixelBufferHeightKey: dimensions.height,
            kCVPixelBufferPixelFormatTypeKey: videoDescription.mediaSubType,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &bufferPool)

        let streamFormat = CMIOExtensionStreamFormat(
            formatDescription: videoDescription,
            maxFrameDuration: CMTime(value: 1, timescale: Int32(frameRate)),
            minFrameDuration: CMTime(value: 1, timescale: Int32(frameRate)),
            validFrameDurations: nil
        )
        bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 6]

        streamSource = FaceTrackerVirtualCameraStreamSource(
            localizedName: "FaceTracker Virtual Camera",
            streamID: UUID(uuidString: "E6AFA4C8-9693-4DB8-9EAF-A76B01A3E930")!,
            streamFormat: streamFormat,
            device: device
        )

        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("Failed to add FaceTracker virtual camera stream: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])

        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "FaceTracker Virtual Camera"
        }

        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    func startStreaming() {
        guard bufferPool != nil else { return }

        streamingCounter += 1
        guard streamingCounter == 1 else { return }

        let source = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        source.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate), leeway: .seconds(0))
        source.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        timer = source
        source.resume()
    }

    func stopStreaming() {
        guard streamingCounter > 0 else { return }

        streamingCounter -= 1
        guard streamingCounter == 0 else { return }

        timer?.cancel()
        timer = nil
    }

    private func emitFrame() {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            bufferPool,
            bufferAuxAttributes,
            &pixelBuffer
        )

        guard status == noErr, let pixelBuffer else {
            os_log(.error, "FaceTracker virtual camera ran out of pixel buffers: %{public}d", status)
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            drawTestPattern(
                baseAddress: baseAddress,
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
            )
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo()
        timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
        let createStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard createStatus == noErr, let sampleBuffer else {
            os_log(.error, "FaceTracker virtual camera failed to create a sample buffer: %{public}d", createStatus)
            return
        }

        streamSource.stream.send(
            sampleBuffer,
            discontinuity: [],
            hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
        )
    }

    private func drawTestPattern(baseAddress: UnsafeMutableRawPointer, width: Int, height: Int, rowBytes: Int) {
        memset(baseAddress, 0x12, rowBytes * height)

        let startRow = stripeStartRow
        if stripeAscending {
            stripeStartRow = startRow > 0 ? startRow - 1 : 0
            stripeAscending = stripeStartRow > 0
        } else {
            stripeStartRow = min(startRow + 1, UInt32(max(0, height - stripeHeight)))
            stripeAscending = stripeStartRow >= UInt32(max(0, height - stripeHeight))
        }

        var rowPointer = baseAddress.advanced(by: Int(startRow) * rowBytes)
        for _ in 0..<stripeHeight {
            var pixelPointer = rowPointer
            for _ in 0..<width {
                var pixel: UInt32 = 0xFF5CE1E6
                memcpy(pixelPointer, &pixel, MemoryLayout<UInt32>.size)
                pixelPointer += MemoryLayout<UInt32>.size
            }
            rowPointer += rowBytes
        }
    }
}

final class FaceTrackerVirtualCameraStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!

    let device: CMIOExtensionDevice
    private let streamFormat: CMIOExtensionStreamFormat
    private var activeFormatIndex = 0

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self.device = device
        self.streamFormat = streamFormat
        super.init()
        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] {
        [streamFormat]
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])

        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = activeFormatIndex
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        }

        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let requestedIndex = streamProperties.activeFormatIndex, requestedIndex == 0 {
            activeFormatIndex = requestedIndex
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        guard let deviceSource = device.source as? FaceTrackerVirtualCameraDeviceSource else {
            fatalError("Unexpected device source: \(String(describing: device.source))")
        }
        deviceSource.startStreaming()
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? FaceTrackerVirtualCameraDeviceSource else {
            fatalError("Unexpected device source: \(String(describing: device.source))")
        }
        deviceSource.stopStreaming()
    }
}

final class FaceTrackerVirtualCameraProviderSource: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: FaceTrackerVirtualCameraDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()

        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = FaceTrackerVirtualCameraDeviceSource(localizedName: "FaceTracker Virtual Camera")

        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to register FaceTracker virtual camera device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "FaceTracker"
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
