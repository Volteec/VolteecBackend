import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix

/// NUT (Network UPS Tools) TCP client using Swift NIO
actor NUTClient {
    private let host: String
    private let port: Int
    private let username: String?
    private let password: String?
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private var channel: (any Channel)?
    private let timeout: TimeAmount = .seconds(10)
    private var isConnecting = false

    /// Initialize NUT client
    /// - Parameters:
    ///   - host: NUT server hostname or IP
    ///   - port: NUT server port
    ///   - username: Optional username for authentication
    ///   - password: Optional password for authentication
    init(host: String, port: Int, username: String? = nil, password: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        // Note: Cannot call async disconnect() from deinit
        // Cleanup will happen when event loop group shuts down
        try? eventLoopGroup.syncShutdownGracefully()
    }

    /// Connect to NUT server and optionally authenticate
    func connect() async throws {
        // Prevent reentrancy
        guard !isConnecting else {
            throw NUTError.connectionFailed("Connection already in progress")
        }
        
        // Return if already connected
        if channel != nil && channel!.isActive {
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        // Close existing connection if any (zombie check)
        if channel != nil {
            await disconnect()
        }

        do {
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelOption(ChannelOptions.connectTimeout, value: timeout)
                .channelInitializer { channel in
                    channel.pipeline.addHandlers([
                        NUTLineHandler(),
                        NUTResponseHandler()
                    ])
                }

            channel = try await bootstrap.connect(host: host, port: port).get()

            // Authenticate if credentials provided
            if let username = username {
                try await authenticate(username: username, password: password)
            }
        } catch {
            // Ensure we clean up on failure
            await disconnect()
            throw NUTError.connectionFailed("Could not connect to \(host):\(port) - \(error.localizedDescription)")
        }
    }

    /// Disconnect from NUT server
    func disconnect() async {
        if let channel = channel {
            try? await channel.close()
        }
        self.channel = nil
    }

    /// Authenticate with NUT server
    private func authenticate(username: String, password: String?) async throws {
        guard let channel = channel else {
            throw NUTError.connectionClosed
        }

        // Send USERNAME command
        let usernameCommand = "USERNAME \(username)\n"
        try await sendCommand(usernameCommand, on: channel)
        let usernameResponse = try await readResponse(on: channel)

        guard usernameResponse.starts(with: "OK") else {
            throw NUTError.authFailed("USERNAME command failed: \(usernameResponse)")
        }

        // Send PASSWORD command if provided
        if let password = password {
            let passwordCommand = "PASSWORD \(password)\n"
            try await sendCommand(passwordCommand, on: channel)
            let passwordResponse = try await readResponse(on: channel)

            guard passwordResponse.starts(with: "OK") else {
                throw NUTError.authFailed("PASSWORD command failed: \(passwordResponse)")
            }
        }
    }

    /// Fetch all variables for a specific UPS
    /// - Parameter upsName: Name of the UPS device
    /// - Returns: Dictionary mapping variable names to their string values
    func fetchVariables(upsName: String) async throws -> [String: String] {
        // Ensure connection is established
        if channel == nil || channel?.isActive == false {
            try await connect()
        }

        guard let channel = channel else {
            throw NUTError.connectionFailed("No active connection")
        }

        // Send LIST VAR command
        let command = "LIST VAR \(upsName)\n"
        try await sendCommand(command, on: channel)

        // Read and parse response lines
        var variables: [String: String] = [:]
        
        // Safety timeout for the read loop
        let deadline = Date().addingTimeInterval(30) // 30s max for full list

        // Read lines until we get the END marker
        while true {
            // Check deadline
            if Date() > deadline {
                throw NUTError.connectionFailed("Timeout waiting for variable list")
            }
            
            let line = try await readResponse(on: channel)

            // Check for end marker
            if line.starts(with: "END LIST VAR") {
                break
            }

            // Check for error responses
            if line.starts(with: "ERR UNKNOWN-UPS") {
                throw NUTError.upsNotFound(upsName)
            }

            if line.starts(with: "ERR ") {
                throw NUTError.invalidResponse(line)
            }

            // Parse VAR line: VAR <upsname> <varname> "<value>"
            if line.starts(with: "VAR ") {
                if let parsed = parseVarLine(line, expectedUPS: upsName) {
                    variables[parsed.name] = parsed.value
                }
            }
        }

        return variables
    }

    /// Parse a VAR response line
    /// - Parameters:
    ///   - line: Response line from NUT server
    ///   - expectedUPS: Expected UPS name for validation
    /// - Returns: Tuple of (variable name, value) or nil if parse fails
    private func parseVarLine(_ line: String, expectedUPS: String) -> (name: String, value: String)? {
        // Format: VAR <upsname> <varname> "<value>"
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)

        guard parts.count == 4,
              parts[0] == "VAR",
              parts[1] == expectedUPS else {
            return nil
        }

        let varName = String(parts[2])
        var value = String(parts[3])

        // Remove surrounding quotes if present
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value.removeFirst()
            value.removeLast()
        }

        return (name: varName, value: value)
    }

    /// Send a command to the NUT server
    private func sendCommand(_ command: String, on channel: any Channel) async throws {
        let buffer = channel.allocator.buffer(string: command)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.writeAndFlush(buffer).whenComplete { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Read a single response line from the NUT server
    private func readResponse(on channel: any Channel) async throws -> String {
        let handler = try await channel.pipeline.handler(type: NUTResponseHandler.self).get()
        return try await handler.readLine(on: channel.eventLoop).get()
    }
}

// MARK: - NIO Handlers

/// Decodes byte stream into line-based messages
private final class NUTLineHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = String

    private var buffer: String = ""

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var byteBuffer = unwrapInboundIn(data)
        guard let chunk = byteBuffer.readString(length: byteBuffer.readableBytes) else {
            return
        }

        buffer.append(chunk)

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex])
            buffer.removeSubrange(...newlineIndex)
            context.fireChannelRead(wrapInboundOut(line))
        }
    }
}

/// Handles NUT protocol responses
private final class NUTResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = String
    typealias InboundOut = Never

    private var lineQueue: [String] = []
    private var waiters: [EventLoopPromise<String>] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let line = unwrapInboundIn(data)

        // If there's a waiter, deliver immediately
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.succeed(line)
        } else {
            // Otherwise queue the line
            lineQueue.append(line)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        // Fail all waiters
        for waiter in waiters {
            waiter.fail(error)
        }
        waiters.removeAll()

        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        // Fail all waiters with channel closed error
        for waiter in waiters {
            waiter.fail(NUTError.channelClosed)
        }
        waiters.removeAll()

        context.fireChannelInactive()
    }

    /// Read a line from the response stream
    func readLine(on eventLoop: any EventLoop) -> EventLoopFuture<String> {
        if eventLoop.inEventLoop {
            return readLineInEventLoop(on: eventLoop)
        }

        return eventLoop.flatSubmit {
            self.readLineInEventLoop(on: eventLoop)
        }
    }

    private func readLineInEventLoop(on eventLoop: any EventLoop) -> EventLoopFuture<String> {
        // Return queued line if available
        if !lineQueue.isEmpty {
            return eventLoop.makeSucceededFuture(lineQueue.removeFirst())
        }

        // Otherwise wait for next line
        let promise = eventLoop.makePromise(of: String.self)
        waiters.append(promise)
        return promise.futureResult
    }
}

// MARK: - Additional Error

extension NUTError {
    static let connectionClosed = NUTError.channelClosed
}
