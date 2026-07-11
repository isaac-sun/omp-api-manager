import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

public actor LocalGatewayServer {
    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?
    private var status: GatewayStatus?

    public init() {}

    public func start(processor: GatewayProxyProcessor, port: Int = 0) async throws -> GatewayStatus {
        guard channel == nil else { throw AppError.gatewayStartFailed }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(LocalGatewayHTTPHandler(processor: processor))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            guard let actualPort = channel.localAddress?.port else {
                try await channel.close().get()
                try await group.shutdownGracefully()
                throw AppError.gatewayStartFailed
            }
            self.channel = channel
            self.group = group
            let status = GatewayStatus(port: actualPort)
            self.status = status
            return status
        } catch {
            try? await group.shutdownGracefully()
            throw AppError.gatewayStartFailed
        }
    }

    public func stop() async {
        if let channel { try? await channel.close().get() }
        if let group { try? await group.shutdownGracefully() }
        channel = nil
        group = nil
        status = nil
    }

    public func currentStatus() -> GatewayStatus? { status }
}

private final class LocalGatewayHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let processor: GatewayProxyProcessor
    private var head: HTTPRequestHead?
    private var body: ByteBuffer?

    init(processor: GatewayProxyProcessor) { self.processor = processor }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
            body = context.channel.allocator.buffer(capacity: 0)
        case .body(var fragment):
            body?.writeBuffer(&fragment)
        case .end:
            guard let head else { return }
            let content = body.map { Data($0.readableBytesView) } ?? Data()
            let headers = Dictionary(uniqueKeysWithValues: head.headers.map { ($0.name.lowercased(), $0.value) })
            let request = GatewayRequest(method: head.method.rawValue, target: head.uri, headers: headers, body: content)
            let contextBox = GatewayContextBox(context)
            Task { [processor, contextBox, handler = self] in
                do {
                    try await processor.proxyStreaming(
                        request,
                        onResponse: { head in contextBox.write(head: head, handler: handler) },
                        onChunk: { chunk in contextBox.write(chunk: chunk, handler: handler) }
                    )
                    contextBox.finish(handler: handler)
                } catch is GatewayAuthorizationError {
                    contextBox.finishWithError(status: .unauthorized, handler: handler)
                } catch {
                    contextBox.finishWithError(status: .badGateway, handler: handler)
                }
            }
            self.head = nil
            self.body = nil
        }
    }

    private func write(response: GatewayResponse, context: ChannelHandlerContext) {
        var headers = HTTPHeaders(response.headers.map { ($0.key, $0.value) })
        headers.replaceOrAdd(name: "content-length", value: "\(response.body.count)")
        let head = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: response.statusCode), headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var body = context.channel.allocator.buffer(capacity: response.body.count)
        body.writeBytes(response.body)
        context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    fileprivate func write(head response: GatewayResponseHead, context: ChannelHandlerContext) {
        let headers = HTTPHeaders(response.headers.map { ($0.key, $0.value) })
        let head = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: response.statusCode), headers: headers)
        context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)
    }

    fileprivate func write(chunk: Data, context: ChannelHandlerContext) {
        var body = context.channel.allocator.buffer(capacity: chunk.count)
        body.writeBytes(chunk)
        context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
    }

    fileprivate func finish(context: ChannelHandlerContext) {
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    fileprivate func writeError(status: HTTPResponseStatus, context: ChannelHandlerContext) {
        let response = GatewayResponse(statusCode: Int(status.code), headers: ["content-type": "application/json"], body: Data("{\"error\":\"gateway request failed\"}".utf8))
        write(response: response, context: context)
    }
}

private final class GatewayContextBox: @unchecked Sendable {
    let context: ChannelHandlerContext
    private var wroteHead = false
    init(_ context: ChannelHandlerContext) { self.context = context }

    func write(head: GatewayResponseHead, handler: LocalGatewayHTTPHandler) {
        context.eventLoop.execute {
            guard !self.wroteHead else { return }
            self.wroteHead = true
            handler.write(head: head, context: self.context)
        }
    }

    func write(chunk: Data, handler: LocalGatewayHTTPHandler) {
        context.eventLoop.execute { guard self.wroteHead else { return }; handler.write(chunk: chunk, context: self.context) }
    }

    func finish(handler: LocalGatewayHTTPHandler) {
        context.eventLoop.execute { guard self.wroteHead else { return }; handler.finish(context: self.context) }
    }

    func finishWithError(status: HTTPResponseStatus, handler: LocalGatewayHTTPHandler) {
        context.eventLoop.execute {
            if self.wroteHead { handler.finish(context: self.context) }
            else { handler.writeError(status: status, context: self.context) }
        }
    }
}
