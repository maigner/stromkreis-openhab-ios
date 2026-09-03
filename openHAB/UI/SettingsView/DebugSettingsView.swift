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

import CommonUI
import OpenHABCore
import os.log
import SwiftUI

struct DebugSettingsView: View {
    @Binding var settingsSitemapDiagnosticsLogging: Bool

    var body: some View {
        Section(header: Text(LocalizedStringKey("debug"))) {
            Toggle("Sitemap Diagnostics Logging", isOn: $settingsSitemapDiagnosticsLogging)
                .onChange(of: settingsSitemapDiagnosticsLogging) { _, newValue in
                    Preferences.shared.modifyApplicationPreferences { prefs in
                        prefs.sitemapDiagnosticsLogging = newValue
                    }
                }
            NavigationLink {
                LogsViewer()
            } label: {
                Text("Logs")
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var sitemapDiagnosticsLogging = false

        var body: some View {
            Form {
                DebugSettingsView(
                    settingsSitemapDiagnosticsLogging: $sitemapDiagnosticsLogging
                )
            }
        }
    }

    return PreviewWrapper()
}
