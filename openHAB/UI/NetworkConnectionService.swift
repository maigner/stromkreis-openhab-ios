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

import Combine
import OpenHABCore
import os.log
import SwiftUI

@MainActor
class NetworkConnectionService: ObservableObject {
    // MARK: - Private state

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupTracker()
    }

    // MARK: - Network Tracker

    private func setupTracker() {
        // Every change of the active home's connection settings restarts connection tracking.
        Preferences.shared.currentHomePreferencesPublisher
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { homeSettings in
                let connections = homeSettings.trackedConnections
                Task {
                    await NetworkTracker.shared.startTracking(connectionConfigurations: connections)
                }
            }
            .store(in: &cancellables)
    }
}
