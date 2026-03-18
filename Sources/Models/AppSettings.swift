import SwiftUI
import AppKit

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int & 0xFF0000) >> 16) / 255
        let g = Double((int & 0x00FF00) >> 8) / 255
        let b = Double(int & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .green
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - AppSettings

class AppSettings: ObservableObject {

    static let shared = AppSettings()

    @AppStorage("overlayOpacity")   var overlayOpacity: Double = 0.30
    @AppStorage("yawThreshold")     var yawThreshold: Double  = 20.0
    @AppStorage("pitchThreshold")   var pitchThreshold: Double = 15.0
    @AppStorage("fallbackDelay")    var fallbackDelay: Double  = 3.0
    @AppStorage("defaultCameraID")  var defaultCameraID: String = ""

    @AppStorage("lookingColorHex") private var lookingColorHex: String = "#00FF7F"
    @AppStorage("awayColorHex")    private var awayColorHex: String   = "#FF3B30"

    var lookingColor: Color {
        get { Color(hex: lookingColorHex) }
        set { lookingColorHex = newValue.hexString }
    }

    var awayColor: Color {
        get { Color(hex: awayColorHex) }
        set { awayColorHex = newValue.hexString }
    }

    var lookingColorBinding: Binding<Color> {
        Binding(get: { self.lookingColor }, set: { self.lookingColor = $0 })
    }
    var awayColorBinding: Binding<Color> {
        Binding(get: { self.awayColor }, set: { self.awayColor = $0 })
    }

    @AppStorage("enabledCameraIDsJSON") private var enabledCameraIDsJSON: String = "[]"

    var enabledCameraIDs: [String] {
        get { AppSettings.decodeIDs(enabledCameraIDsJSON) }
        set { enabledCameraIDsJSON = AppSettings.encodeIDs(newValue) }
    }

    static func encodeIDs(_ ids: [String]) -> String {
        (try? String(data: JSONEncoder().encode(ids), encoding: .utf8)) ?? "[]"
    }

    static func decodeIDs(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return ids
    }
}
