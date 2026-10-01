// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// The package of the webui-termux-api release APK (Termux:API repackaged).
/// Modules do not install it under this name: the build renames it per
/// module ([appPlanePackage]).
const String termuxApiPackage = 'com.webui.termux.api';

/// The package a module's own copy of the app plane installs as:
/// `com.webui.api.<seg>`, `<seg>` being [moduleId] with every character
/// outside `[A-Za-z0-9_]` replaced by `_`, prefixed with `m` if it starts
/// with a digit (webui-termux-api WEBUI.md, "Renaming per module"; flutter_p0g
/// applies the same rule).
String appPlanePackage(String moduleId) {
  var seg = moduleId.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
  if (seg.isEmpty || RegExp('^[0-9]').hasMatch(seg)) seg = 'm$seg';
  return 'com.webui.api.$seg';
}

/// The receiver class. The fork keeps Termux:API's Java package, so the
/// component is `<package>/com.termux.api.TermuxApiReceiver`
/// (webui-termux-api `TermuxApiReceiver.java`).
const String termuxApiReceiver = 'com.termux.api.TermuxApiReceiver';
