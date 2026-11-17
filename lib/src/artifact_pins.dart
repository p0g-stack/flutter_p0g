import 'package:flutter_tools/src/base/common.dart';

final class PinnedArtifact {
  const PinnedArtifact(this.url, this.sha256);

  final String url;
  final String sha256;
}

// Historical releases predate source-tagged names. Asset IDs identify the
// original bytes even if someone replaces an asset on the old release tag.
const Map<String, Map<String, PinnedArtifact>> dartAndroidKitPins = {
  '3.13.4': {
    'arm64-v8a': PinnedArtifact(
      'https://api.github.com/repos/p0g-stack/flutter_p0g/releases/assets/602745358',
      '2611cf7d36b68b103eab41a38d46a45bd1c1739e2f33f078ecf90520f7831bc1',
    ),
    'x86_64': PinnedArtifact(
      'https://api.github.com/repos/p0g-stack/flutter_p0g/releases/assets/602745349',
      'faa7ef975702a8a52a7500b704ee9ef60ed7cce6cccaccfc0e81d02b06205991',
    ),
  },
  // dart-android-3.13.7-9a94692015433723b2f5e0b19b5c00553112ce40
  '3.13.7': {
    'arm64-v8a': PinnedArtifact(
      'https://api.github.com/repos/p0g-stack/flutter_p0g/releases/assets/758156337',
      '2ecff73f4cf0205ec16ed54f81dc94b57b7709bcd1681691859f211b351fcd01',
    ),
    'x86_64': PinnedArtifact(
      'https://api.github.com/repos/p0g-stack/flutter_p0g/releases/assets/758156334',
      'a82bc739280110274e16499158f94e62aca652fb453d29af7f2ec9bff25ceac3',
    ),
  },
};

const Map<String, Map<String, PinnedArtifact>> aeraKitPins = {
  '3.47.5': {
    'linux-arm64-debug': PinnedArtifact(
      'https://api.github.com/repos/p0g-stack/flutter-aera/releases/assets/610973721',
      '12b9a131467a3737a8b1191c69d239039a66498bf638f14095741db74ba44e60',
    ),
    'linux-x64-debug': PinnedArtifact(
      'https://api.github.com/repos/p0g-stack/flutter-aera/releases/assets/610973281',
      '89502b18226472ee3d981eda915f1afee9b5643af67c8da9a1beeb8338ad52aa',
    ),
  },
  // kit-3.47.9-0c28b4e291849f008d7ee3fd063e2670d0f9116b
  '3.47.9': {
    'linux-arm64-debug': PinnedArtifact(
      'https://github.com/p0g-stack/flutter-aera/releases/download/kit-3.47.9-0c28b4e291849f008d7ee3fd063e2670d0f9116b/flutter-aera-kit-linux-arm64-debug-3.47.9.tar.xz',
      '31c2131acd5966a50e96b9438c6e48d63126be806fcbe4da747479ae6a56caed',
    ),
    'linux-x64-debug': PinnedArtifact(
      'https://github.com/p0g-stack/flutter-aera/releases/download/kit-3.47.9-0c28b4e291849f008d7ee3fd063e2670d0f9116b/flutter-aera-kit-linux-x64-debug-3.47.9.tar.xz',
      '928be84c9d962dfc324733349f6ae0f9b363da167b40097fcbc49d57a6ac2a43',
    ),
  },
};

PinnedArtifact pinnedKit(
  Map<String, Map<String, PinnedArtifact>> pins,
  String kind,
  String version,
  String target,
) {
  final artifact = pins[version]?[target];
  if (artifact == null) {
    throwToolExit('No pinned $kind kit for $version/$target; provide an explicit kit and sha256.');
  }
  return artifact;
}
