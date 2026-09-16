import Foundation

extension String {
    var base64URLDecodedData: Data? {
        var normalized = self.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = normalized.count % 4
        if padding > 0 {
            normalized.append(String(repeating: "=", count: 4 - padding))
        }
        return Data(base64Encoded: normalized)
    }
}
