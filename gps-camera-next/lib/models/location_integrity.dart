/// Heuristic checks, never a certification of authentic GNSS signals.
enum LocationIntegrity {
  trusted,
  lowAccuracy,
  suspectedMock,
  suspectedSpoofing,
  unavailable;

  String get warning => switch (this) {
    trusted => '',
    lowAccuracy => 'Location unverified',
    suspectedMock => 'Mock Location',
    suspectedSpoofing => 'Location unverified · Suspected spoofing',
    unavailable => 'GPS unavailable',
  };
}

enum MockLocationPolicy { label, omitCoordinates }
