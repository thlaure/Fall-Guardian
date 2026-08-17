// BackendConfiguration.swift
// Fall Guardian — watchOS
//
// The watch's own backend base URL. This must come from the app's signed
// build, never from a WatchConnectivity message — a relayed or tampered
// message crossing that channel must not be able to redirect where the
// watch sends its enrollment claim or, later, its direct incident
// submissions.
//
// A build-setting-driven override (an Xcode user-defined build setting
// merged into the generated Info.plist) was attempted here and reverted:
// this target uses Xcode 16's file-system-synchronized group for its
// sources, which auto-includes any physical Info.plist as a Copy Bundle
// Resources member and collides with using it as INFOPLIST_FILE ("Multiple
// commands produce Info.plist"). Resolving that cleanly needs an explicit
// synchronized-group membership exception, which is a deliberate follow-up,
// not a blind edit. Until then, this constant is the single edit point for
// a non-local build.

import Foundation

enum BackendConfiguration {
    static let baseURL = URL(string: "http://localhost:8002")!
}
