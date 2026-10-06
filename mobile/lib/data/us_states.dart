/// US states + DC for home-state selection.
class UsStates {
  UsStates._();

  static const List<({String code, String name})> all = [
    (code: 'AL', name: 'Alabama'),
    (code: 'AK', name: 'Alaska'),
    (code: 'AZ', name: 'Arizona'),
    (code: 'AR', name: 'Arkansas'),
    (code: 'CA', name: 'California'),
    (code: 'CO', name: 'Colorado'),
    (code: 'CT', name: 'Connecticut'),
    (code: 'DE', name: 'Delaware'),
    (code: 'DC', name: 'District of Columbia'),
    (code: 'FL', name: 'Florida'),
    (code: 'GA', name: 'Georgia'),
    (code: 'HI', name: 'Hawaii'),
    (code: 'ID', name: 'Idaho'),
    (code: 'IL', name: 'Illinois'),
    (code: 'IN', name: 'Indiana'),
    (code: 'IA', name: 'Iowa'),
    (code: 'KS', name: 'Kansas'),
    (code: 'KY', name: 'Kentucky'),
    (code: 'LA', name: 'Louisiana'),
    (code: 'ME', name: 'Maine'),
    (code: 'MD', name: 'Maryland'),
    (code: 'MA', name: 'Massachusetts'),
    (code: 'MI', name: 'Michigan'),
    (code: 'MN', name: 'Minnesota'),
    (code: 'MS', name: 'Mississippi'),
    (code: 'MO', name: 'Missouri'),
    (code: 'MT', name: 'Montana'),
    (code: 'NE', name: 'Nebraska'),
    (code: 'NV', name: 'Nevada'),
    (code: 'NH', name: 'New Hampshire'),
    (code: 'NJ', name: 'New Jersey'),
    (code: 'NM', name: 'New Mexico'),
    (code: 'NY', name: 'New York'),
    (code: 'NC', name: 'North Carolina'),
    (code: 'ND', name: 'North Dakota'),
    (code: 'OH', name: 'Ohio'),
    (code: 'OK', name: 'Oklahoma'),
    (code: 'OR', name: 'Oregon'),
    (code: 'PA', name: 'Pennsylvania'),
    (code: 'RI', name: 'Rhode Island'),
    (code: 'SC', name: 'South Carolina'),
    (code: 'SD', name: 'South Dakota'),
    (code: 'TN', name: 'Tennessee'),
    (code: 'TX', name: 'Texas'),
    (code: 'UT', name: 'Utah'),
    (code: 'VT', name: 'Vermont'),
    (code: 'VA', name: 'Virginia'),
    (code: 'WA', name: 'Washington'),
    (code: 'WV', name: 'West Virginia'),
    (code: 'WI', name: 'Wisconsin'),
    (code: 'WY', name: 'Wyoming'),
  ];

  static String? nameFor(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final s in all) {
      if (s.code == code) return s.name;
    }
    return code;
  }

  /// House seats per state under the 2020 reapportionment — fixed through
  /// the 2030 census redistricting. DC's single at-large delegate counts as
  /// 1: it is the user's House ballot either way.
  static const Map<String, int> houseSeats = {
    'AL': 7,
    'AK': 1,
    'AZ': 9,
    'AR': 4,
    'CA': 52,
    'CO': 8,
    'CT': 5,
    'DE': 1,
    'DC': 1,
    'FL': 28,
    'GA': 14,
    'HI': 2,
    'ID': 2,
    'IL': 17,
    'IN': 9,
    'IA': 4,
    'KS': 4,
    'KY': 6,
    'LA': 6,
    'ME': 2,
    'MD': 8,
    'MA': 9,
    'MI': 13,
    'MN': 8,
    'MS': 4,
    'MO': 8,
    'MT': 2,
    'NE': 3,
    'NV': 4,
    'NH': 2,
    'NJ': 12,
    'NM': 3,
    'NY': 26,
    'NC': 14,
    'ND': 1,
    'OH': 15,
    'OK': 5,
    'OR': 6,
    'PA': 17,
    'RI': 2,
    'SC': 7,
    'SD': 1,
    'TN': 9,
    'TX': 38,
    'UT': 4,
    'VT': 1,
    'VA': 11,
    'WA': 10,
    'WV': 2,
    'WI': 8,
    'WY': 1,
  };

  /// Number of House districts a state picker should offer. 0 = not a state
  /// we cover (or no code set), so callers can hide the district row.
  static int districtCount(String? code) {
    if (code == null || code.isEmpty) return 0;
    return houseSeats[code.toUpperCase()] ?? 0;
  }
}
