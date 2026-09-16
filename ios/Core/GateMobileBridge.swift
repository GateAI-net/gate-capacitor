import Foundation

/// Shared by the framework adapters. Only JSON strings cross isolation boundaries.
@MainActor
final class GateMobileBridge {
    private var clients: [String: GateAIClient] = [:]

    func execute(_ payload: String) async -> String {
        do {
            guard let args = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
                throw GateAIError.configuration("Expected a JSON object.")
            }
            let result = try await dispatch(args)
            return encode(["result": result])
        } catch let error as GateAIError {
            if case let .server(status, detail, headers) = error {
                var fields: [String: Any] = ["code": "http", "message": "HTTP \(status)", "status": status, "headers": headers ?? [:]]
                if let detail, let data = try? JSONEncoder().encode(detail) {
                    fields["body"] = String(decoding: data, as: UTF8.self)
                }
                return encode(["error": fields])
            }
            let code: String
            switch error {
            case .configuration: code = "configuration"
            case .network: code = "network"
            case .attestationUnavailable, .attestationFailed, .secureEnclaveUnavailable: code = "attestation"
            default: code = "native"
            }
            return encode(["error": ["code": code, "message": error.localizedDescription]])
        } catch {
            return encode(["error": ["code": "native", "message": error.localizedDescription]])
        }
    }

    private func dispatch(_ args: [String: Any]) async throws -> Any {
        let operation = try string(args, "operation")
        if operation == "configure" {
            guard let config = args["configuration"] as? [String: Any],
                  let ios = config["ios"] as? [String: Any] else {
                throw GateAIError.configuration("iOS configuration is required on iOS.")
            }
            let base = try string(config, "baseUrl")
            guard let url = URLComponents(string: base), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/" else {
                throw GateAIError.configuration("baseUrl must be an HTTPS origin.")
            }
            let configuration = try GateAIConfiguration(
                baseURLString: base, bundleIdentifier: ios["bundleIdentifier"] as? String,
                teamIdentifier: try string(ios, "teamIdentifier"))
            let id = UUID().uuidString
            clients[id] = GateAIClient(configuration: configuration)
            return ["clientId": id]
        }
        let id = try string(args, "clientId")
        guard let client = clients[id] else { throw GateAIError.configuration("Unknown or disposed client.") }
        switch operation {
        case "dispose":
            clients.removeValue(forKey: id)
            return NSNull()
        case "clearCachedState":
            await client.clearCachedState()
            return NSNull()
        case "request", "authorizationHeaders":
            let path = try string(args, "path")
            guard path.range(of: #"^[A-Za-z0-9_~-]+(?:/[A-Za-z0-9_~.-]+)*$"#, options: .regularExpression) != nil,
                  !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  let method = HTTPMethod(rawValue: try string(args, "method")) else {
                throw GateAIError.configuration("Invalid relative path or HTTP method.")
            }
            let headers = args["headers"] as? [String: String] ?? [:]
            for (name, value) in headers {
                guard !["authorization", "dpop", "host", "content-length", "connection"].contains(name.lowercased()),
                      name.range(of: #"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$"#, options: .regularExpression) != nil,
                      !value.contains("\r"), !value.contains("\n") else {
                    throw GateAIError.configuration("Invalid or reserved request header.")
                }
            }
            if operation == "authorizationHeaders" {
                var result = try await client.authorizationHeaders(for: path, method: method, nonce: args["nonce"] as? String)
                // Case-insensitive per-request overrides, excluding protected auth headers above.
                for (key, value) in headers {
                    for existing in Array(result.keys) where existing.lowercased() == key.lowercased() { result.removeValue(forKey: existing) }
                    result[key] = value
                }
                return result
            }
            let body = (args["body"] as? String).map { Data($0.utf8) }
            guard method != .get || body == nil else { throw GateAIError.configuration("GET cannot have a body.") }
            let (data, response) = try await client.performProxyRequest(path: path, method: method, body: body, additionalHeaders: headers)
            let responseHeaders = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            }
            return ["status": response.statusCode, "headers": responseHeaders, "body": String(decoding: data, as: UTF8.self)]
        default:
            throw GateAIError.configuration("Unknown operation.")
        }
    }

    private func string(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else { throw GateAIError.configuration("Missing \(key).") }
        return value
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return #"{"error":{"code":"invalid_response","message":"Could not encode native response."}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
