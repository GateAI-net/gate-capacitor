import Foundation

struct HTTPHeaders: Sendable {
    private(set) var storage: [String: String]

    init(_ headers: [String: String] = [:]) {
        self.storage = headers
    }

    subscript(name: String) -> String? {
        get { storage[name] }
        set { storage[name] = newValue }
    }

    var asDictionary: [String: String] { storage }
}

/// HTTP methods supported by the Gate/AI SDK.
///
/// Currently supports GET and POST methods for making authenticated requests.
public enum HTTPMethod: String, Sendable {
    /// The HTTP GET method.
    case get = "GET"

    /// The HTTP POST method.
    case post = "POST"
}

struct HTTPRequest<Body: Encodable & Sendable>: Sendable {
    let method: HTTPMethod
    let path: String
    let body: Body?
    let headers: HTTPHeaders

    init(method: HTTPMethod, path: String, body: Body? = nil, headers: HTTPHeaders = HTTPHeaders()) {
        self.method = method
        self.path = path
        self.body = body
        self.headers = headers
    }
}

final class GateAIHTTPClient: @unchecked Sendable {
    private let session: URLSession
    private let configuration: GateAIConfiguration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: GateAILoggerProtocol

    init(configuration: GateAIConfiguration, session: URLSession = .shared, logger: GateAILoggerProtocol = GateAILogger.shared) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
        // Note: Not using .convertFromSnakeCase since we have explicit CodingKeys
        self.logger = logger

        // Configure logger with the provided log level
        if let gateAILogger = logger as? GateAILogger {
            gateAILogger.setLogLevel(configuration.logLevel)
        }
    }

    func send<RequestBody: Encodable, ResponseBody: Decodable>(
        _ request: HTTPRequest<RequestBody>,
        expecting type: ResponseBody.Type
    ) async throws -> ResponseBody {
        let url = configuration.baseURL.appendingPathComponent(request.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in request.headers.asDictionary {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body = request.body {
            do {
                urlRequest.httpBody = try encoder.encode(body)
            } catch {
                throw GateAIError.configuration("Failed to encode request body for \(request.path): \(error.localizedDescription)")
            }
        }

        // Log the outgoing request
        logger.logRequest(urlRequest, body: urlRequest.httpBody)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GateAIError.invalidResponse
            }

            let headerFields = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, header in
                if let key = header.key as? String, let value = header.value as? String {
                    partialResult[key] = value
                }
            }

            // Log the response
            logger.logResponse(httpResponse, data: data, error: nil)

            switch httpResponse.statusCode {
            case 200..<300:
                do {
                    return try decoder.decode(ResponseBody.self, from: data)
                } catch {
                    // Do not log the raw body here: on a 2xx /token response it contains the
                    // access token, and error-level logs are public in the unified log. The
                    // body was already logged (redacted, at debug) by logResponse above.
                    logger.error("Failed to decode response as \(ResponseBody.self) (\(data.count) bytes): \(error)")
                    throw GateAIError.decoding(underlying: error)
                }
            default:
                let serverError = try? decoder.decode(ServerErrorResponse.self, from: data)
                let gateError = GateAIError.server(statusCode: httpResponse.statusCode, error: serverError, headers: headerFields)
                logger.error("Server error: \(gateError)")
                throw gateError
            }
        } catch let error as GateAIError {
            logger.logResponse(nil, data: nil, error: error)
            throw error
        } catch {
            let gateError = GateAIError.network(underlying: error)
            logger.logResponse(nil, data: nil, error: gateError)
            throw gateError
        }
    }
}
