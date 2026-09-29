// Copyright (c) 2010-2026 Contributors to the openHAB project
//
// See the NOTICE file(s) distributed with this work for additional
// information.
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0
//
// SPDX-License-Identifier: EPL-2.0

@preconcurrency import Foundation
import os

public enum HTTPClientError: Error {
    case noDataforItem
    case noDataForProperties
    case baseURLIsNil
    case httpError(Int)
    case failedtoFetchMJPEG
    case noConfiguration

    var debugDescription: String {
        switch self {
        case .noDataforItem:
            "No data for item"
        case .noDataForProperties:
            "No data for properties"
        case .baseURLIsNil:
            "Base URL is nil"
        case let .httpError(statusCode):
            "HTTP error \(statusCode)"
        case .failedtoFetchMJPEG:
            "Failed to fetch MJPEG"
        case .noConfiguration:
            "No configuration"
        }
    }
}

public final class HTTPClient: NSObject, Sendable {
    // MARK: - Properties

    public enum SessionType {
        case download
        case data
        case bytes
        case mjpegStream
    }

    /// this can be changed if we detect another server
    public let baseURL: URL?

    private let connectionConfiguration: ConnectionConfiguration
    public let session: URLSession
    public let sessionConfiguration: URLSessionConfiguration
    public let delegate: (any URLSessionDelegate)?

    /// Creates HTTPClient with default session configuration and HTTPClientDelegate
    public convenience init(baseURL: URL? = nil, connectionConfiguration: ConnectionConfiguration) {
        self.init(
            baseURL: baseURL,
            connectionConfiguration: connectionConfiguration,
            sessionConfiguration: .default,
            delegate: HTTPClientDelegate(with: connectionConfiguration)
        )
    }

    /// Creates HTTPClient with custom session configuration and optional delegate
    public init(baseURL: URL? = nil, connectionConfiguration: ConnectionConfiguration, sessionConfiguration: URLSessionConfiguration,
                delegate: (any URLSessionDelegate)? = nil) {
        self.baseURL = baseURL
        self.delegate = delegate
        self.connectionConfiguration = connectionConfiguration
        self.sessionConfiguration = sessionConfiguration
        session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        super.init()
    }

    /// Creates HTTPClient optimized for streaming with modified session configuration
    public convenience init(streamingWith sessionConfiguration: URLSessionConfiguration,
                            baseURL: URL? = nil,
                            connectionConfiguration: ConnectionConfiguration,
                            delegate: (any URLSessionDelegate)? = nil) {
        let streamingSessionConfiguration = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
        streamingSessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        streamingSessionConfiguration.timeoutIntervalForRequest = 0
        streamingSessionConfiguration.waitsForConnectivity = true
        streamingSessionConfiguration.urlCache = nil

        self.init(
            baseURL: baseURL,
            connectionConfiguration: connectionConfiguration,
            sessionConfiguration: streamingSessionConfiguration,
            delegate: delegate
        )
    }

    public func processStream(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await doRequest(baseURL: url, type: .mjpegStream)
        } catch {
            Logger.httpClient.error("Failed to fetch MJPEG stream: \(error.localizedDescription)")
            throw HTTPClientError.failedtoFetchMJPEG
        }
    }

    /*
      Initiates a download request to a specified base URL for a specified path and returns the file URL via a completion handler.

      - Parameters:
     - url
      - Returns:
      - response: The URL response object providing response metadata, such as HTTP headers and status code.
      - error: An error object that indicates why the request failed, or `nil` if the request was successful.
      */

    public func downloadFile(url: URL) async throws -> (URL, URLResponse) {
        let (fileURL, response): (URL, URLResponse) = try await doRequest(baseURL: url, path: nil, type: .download)

        return (fileURL, response)
    }

    public func doRequest<T>(baseURL: URL?,
                             path: String? = nil,
                             headers: [String: String]? = nil,
                             timeout: TimeInterval = 60.0,
                             body: String? = nil,
                             method: String = "GET",
                             type: SessionType,
                             cacheingPolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> (T, URLResponse) {
        guard var url = baseURL ?? self.baseURL else {
            Logger.httpClient.info("doRequest ERROR: Base URL is nil")
            throw HTTPClientError.baseURLIsNil
        }

        if let path {
            url.appendPathComponent(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let body {
            request.httpBody = body.data(using: .utf8)
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        }

        if type == .mjpegStream {
            request.setValue("multipart/x-mixed-replace", forHTTPHeaderField: "Accept")
        }

        if cacheingPolicy != .useProtocolCachePolicy {
            request.cachePolicy = cacheingPolicy
        }

        let (result, response): (T, URLResponse) = try await performRequest(request: request, type: type)
        if let response = response as? HTTPURLResponse {
            if (400 ... 599).contains(response.statusCode) {
                Logger.httpClient.error("HTTP error from URL \(url.absoluteString) : \(response.statusCode)")
                throw HTTPClientError.httpError(response.statusCode)
            }
            Logger.httpClient.info("Response from URL \(url.absoluteString) : \(response.statusCode)")
            return (result, response)
        }
        fatalError()
    }

    private func performRequest<T>(request: URLRequest, type: SessionType = .data) async throws -> (T, URLResponse) {
        var request = request

        let username = connectionConfiguration.username
        let password = connectionConfiguration.password
        let alwaysSendBasicAuth = connectionConfiguration.alwaysSendBasicAuth

        if connectionConfiguration.isCloudConnection || alwaysSendBasicAuth, !username.isEmpty, !password.isEmpty {
            request.setValue(basicAuthHeader(username: username, password: password), forHTTPHeaderField: "Authorization")
        }

        switch type {
        case .download:
            return try await session.download(for: request) as! (T, URLResponse)
        case .data:
            return try await session.data(for: request) as! (T, URLResponse)
        case .bytes:
            return try await session.bytes(for: request, delegate: nil) as! (T, URLResponse)
        case .mjpegStream:
            return try await session.data(for: request) as! (T, URLResponse)
        }
    }
}
