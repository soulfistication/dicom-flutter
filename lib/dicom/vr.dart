/// DICOM Value Representations and their on-disk encoding rules.
abstract final class VR {
  static const extendedLength = {
    'OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'SQ', 'UC', 'UR', 'UT', 'UN', 'SV', 'UV',
  };

  static const stringVRs = {
    'AE', 'AS', 'CS', 'DA', 'DS', 'DT', 'IS', 'LO', 'LT', 'PN', 'SH', 'ST',
    'TM', 'UC', 'UI', 'UR', 'UT',
  };

  static const all = {
    'AE', 'AS', 'AT', 'CS', 'DA', 'DS', 'DT', 'FL', 'FD', 'IS', 'LO', 'LT',
    'OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'PN', 'SH', 'SL', 'SQ', 'SS', 'ST',
    'SV', 'TM', 'UC', 'UI', 'UL', 'UN', 'UR', 'US', 'UT', 'UV',
  };

  static bool isValid(String code) => all.contains(code);
  static bool usesExtendedLength(String code) => extendedLength.contains(code);
  static bool isString(String code) => stringVRs.contains(code);
}
