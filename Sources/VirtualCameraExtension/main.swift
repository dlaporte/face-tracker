import CoreMediaIO
import Foundation

let providerSource = FaceTrackerVirtualCameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
