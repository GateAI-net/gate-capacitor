import Foundation

extension Dictionary where Key == String, Value == String {
    subscript(caseInsensitive key: String) -> String? {
        let lowercasedKey = key.lowercased()
        return first { $0.key.lowercased() == lowercasedKey }?.value
    }
}
