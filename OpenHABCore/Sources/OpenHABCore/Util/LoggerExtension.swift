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

// Inspired by https://www.avanderlee.com/debugging/oslog-unified-logging/

import Foundation
import os.log

public extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "net.stromkreis.app"

    static let appDelegate = Logger(subsystem: subsystem, category: "AppDelegate")


    static let clientCert = Logger(subsystem: subsystem, category: "ClientCert")

    static let connectionFailureTracker = Logger(subsystem: subsystem, category: "ConnectionFailureTracker")

    static let defaultLoggingMiddleware = Logger(subsystem: subsystem, category: "loggingMiddleware")



    static let etagCache = Logger(subsystem: subsystem, category: "ETagCache")

    static let etagChecker = Logger(subsystem: subsystem, category: "ETagChecker")

    static let httpClient = Logger(subsystem: subsystem, category: "HTTPClient")

    static let httpClientDelegate = Logger(subsystem: subsystem, category: "HTTPClientDelegate")



    static let networkTracker = Logger(subsystem: subsystem, category: "NetworkTracker")



    static let nwPathMonitoring = Logger(subsystem: subsystem, category: "NWPathMonitoring")





    static let preferences = Logger(subsystem: subsystem, category: "Preferences")





    static let sessionChallenge = Logger(subsystem: subsystem, category: "SessionChallenge")


    static let serverCert = Logger(subsystem: subsystem, category: "ServerCertificateManager")





    static let viewController = Logger(subsystem: subsystem, category: "viewController")





    #if DEBUG
    private static let testSubsystem = subsystem + "." + "test"

    static let testNetworkTracker = Logger(subsystem: testSubsystem, category: "NetworkTrackerTests")
    #endif
}
