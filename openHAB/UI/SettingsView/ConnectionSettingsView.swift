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

import OpenHABCore
import SFSafeSymbols
import SwiftUI

struct ConnectionSettingsView: View {
    @Binding var localConnectionConfiguration: ConnectionConfiguration
    @Binding var remoteConnectionConfiguration: ConnectionConfiguration
    @Binding var localTestedOKURL: String

    @State private var remoteTestedOKURL = ""

    var body: some View {
        SingleConnectionSettingsView(headerText: String(localized: "Stromkreis Cloud"), connectionConfig: $remoteConnectionConfiguration, showNotificationToggle: true, testedOKURL: $remoteTestedOKURL)
        SingleConnectionSettingsView(headerText: String(localized: "Local server"), isLocalConnection: true, connectionConfig: $localConnectionConfiguration, showNotificationToggle: false, testedOKURL: $localTestedOKURL)
    }
}

#Preview {
    @Previewable @State var connectionConfig1 = ConnectionConfiguration(
        url: "https://openhab.local:8443",
        username: "user",
        password: "password123"
    )
    @Previewable @State var connectionConfig2 = ConnectionConfiguration(
        url: "http://192.168.2.1",
        username: "user",
        password: "password123"
    )

    NavigationStack {
        Form {
            ConnectionSettingsView(
                localConnectionConfiguration: $connectionConfig1,
                remoteConnectionConfiguration: $connectionConfig2,
                localTestedOKURL: .constant("")
            )
        }
    }
}
