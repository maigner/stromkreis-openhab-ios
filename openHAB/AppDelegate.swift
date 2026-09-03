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
import os.log
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Logger.appDelegate.info("didFinishLaunchingWithOptions started")

        let appDefaults = ["CacheDataAgressively": NSNumber(value: true)]
        UserDefaults.standard.register(defaults: appDefaults)

        Preferences.migratePreferences()

        Logger.appDelegate.info("didFinishLaunchingWithOptions ended")
        return true
    }

    func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        // Explicitly opt out of UIKit state restoration. Without this, iOS defaults to
        // attempting to restore any previously-saved archive for backward compatibility --
        // including one saved by an older, storyboard-based build (pre-SwiftUI app lifecycle,
        // see 6d89e35a). On a device upgraded in place from that older build, iOS tries to
        // restore view controllers/storyboard IDs that no longer exist, producing a black,
        // unresponsive screen with nothing logged (the failure happens before app code runs).
        false
    }

    // Info.plist sets UIApplicationSupportsSecureRestorableState, which makes iOS consult these
    // NSSecureCoding-based methods instead of the deprecated pair above. Both pairs are kept in
    // sync (both false) since which one iOS actually calls depends on that flag; the deprecated
    // pair stays as a defensive fallback.
    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Named distinctly from the old "Default Configuration" (storyboard-based
        // SceneDelegate + Main.storyboard, removed in 6d89e35a): reusing that name would
        // let iOS try to reconnect a UISceneSession cached from a build that had it,
        // referencing a scene delegate/storyboard that no longer exists. A new name forces
        // a fresh session instead of a reconnection attempt on in-place upgrade.
        UISceneConfiguration(name: "SwiftUI Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
}
