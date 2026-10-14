import Foundation
import Network

public class SnifferServer {
    public static let shared = SnifferServer()

    private var listener: NWListener?
    private let port: UInt16 = 37651
    public var onCaptureReceived: (([String: Any]) -> Void)?

    public func start() {
        do {
            let tcpOptions = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true

            guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
            listener = try NWListener(using: params, on: endpointPort)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[SnifferServer] Listening on 127.0.0.1:\(self.port)")
                case .failed(let err):
                    print("[SnifferServer] Failed with error: \(err)")
                default:
                    break
                }
            }

            listener?.start(queue: .global(qos: .utility))
        } catch {
            print("[SnifferServer] Error starting server: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        readRequest(connection: connection, buffer: Data())
    }

    private func readRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            var currentBuffer = buffer
            if let data = content {
                currentBuffer.append(data)
            }

            if let requestString = String(data: currentBuffer, encoding: .utf8) {
                // Check if HTTP header is complete
                if let headerEndRange = requestString.range(of: "\r\n\r\n") {
                    let headerPart = String(requestString[..<headerEndRange.lowerBound])
                    let bodyPart = String(requestString[headerEndRange.upperBound...])

                    var contentLength = 0
                    for line in headerPart.components(separatedBy: "\r\n") {
                        if line.lowercased().hasPrefix("content-length:") {
                            let parts = line.split(separator: ":")
                            if parts.count >= 2 {
                                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                            }
                        }
                    }

                    if bodyPart.utf8.count >= contentLength {
                        self?.processHTTPRequest(header: headerPart, body: bodyPart, connection: connection)
                        return
                    }
                }
            }

            if isComplete || error != nil {
                connection.cancel()
            } else {
                self?.readRequest(connection: connection, buffer: currentBuffer)
            }
        }
    }

    private func processHTTPRequest(header: String, body: String, connection: NWConnection) {
        let firstLine = header.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        if method == "OPTIONS" {
            let corsResponse = """
            HTTP/1.1 204 No Content\r
            Access-Control-Allow-Origin: *\r
            Access-Control-Allow-Methods: GET, POST, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type\r
            Content-Length: 0\r
            \r\n
            """
            connection.send(content: corsResponse.data(using: .utf8), completion: .contentProcessed({ _ in
                connection.cancel()
            }))
            return
        }

        if method == "GET" && path == "/version" {
            let jsonBody = """
            {"ok":true,"app":"TDM Fast","version":"1.0.0","activated":true,"build":"official"}
            """
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: jsonBody)
            return
        }

        if method == "POST" && path == "/capture" {
            if let bodyData = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in
                    self?.onCaptureReceived?(json)
                }
                sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"ok\":true}")
                return
            } else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"ok\":false}")
                return
            }
        }

        sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String = "text/plain", body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let response = """
        HTTP/1.1 \(status)\r
        Access-Control-Allow-Origin: *\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
