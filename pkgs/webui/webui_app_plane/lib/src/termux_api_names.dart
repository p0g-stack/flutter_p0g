// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// The package webui-termux-api installs as (Termux:API repackaged).
const String termuxApiPackage = 'com.webui.termux.api';

/// The receiver class. The fork keeps Termux:API's Java package, so the
/// component is `<package>/com.termux.api.TermuxApiReceiver`
/// (webui-termux-api `TermuxApiReceiver.java`).
const String termuxApiReceiver = 'com.termux.api.TermuxApiReceiver';
