class NgLocations {
  static const List<String> states = [
    'Abia','Adamawa','Akwa Ibom','Anambra','Bauchi','Bayelsa','Benue','Borno','Cross River','Delta','Ebonyi','Edo','Ekiti','Enugu','Abuja FCT','Gombe','Imo','Jigawa','Kaduna','Kano','Katsina','Kebbi','Kogi','Kwara','Lagos','Nasarawa','Niger','Ogun','Ondo','Osun','Oyo','Plateau','Rivers','Sokoto','Taraba','Yobe','Zamfara'
  ];

  /// Minimal-but-useful LGA dataset to support cascading selection.
  /// Add/extend LGAs anytime without changing UI code.
  static const Map<String, List<String>> lgasByState = {
    'Lagos': ['Agege','Ajeromi-Ifelodun','Alimosho','Amuwo-Odofin','Apapa','Badagry','Epe','Eti-Osa','Ibeju-Lekki','Ifako-Ijaiye','Ikeja','Ikorodu','Kosofe','Lagos Island','Lagos Mainland','Mushin','Ojo','Oshodi-Isolo','Shomolu','Surulere'],
    'Kwara': ['Asa','Baruten','Edu','Ekiti (Kwara)','Ifelodun (Kwara)','Ilorin East','Ilorin South','Ilorin West','Irepodun (Kwara)','Isin','Kaiama','Moro','Offa','Oke Ero','Oyun','Pategi'],
    'Anambra': ['Aguata','Anambra East','Anambra West','Anaocha','Awka North','Awka South','Ayamelum','Dunukofia','Ekwusigo','Idemili North','Idemili South','Ihiala','Njikoka','Nnewi North','Nnewi South','Ogbaru','Onitsha North','Onitsha South','Orumba North','Orumba South','Oyi'],
    'Gombe': ['Akko','Balanga','Billiri','Dukku','Funakaye','Gombe','Kaltungo','Kwami','Nafada','Shongom','Yamaltu/Deba'],
    'Oyo': ['Afijio','Akinyele','Atiba','Atisbo','Egbeda','Ibadan North','Ibadan North-East','Ibadan North-West','Ibadan South-East','Ibadan South-West','Ibarapa Central','Ibarapa East','Ibarapa North','Ido','Irepo','Iseyin','Itesiwaju','Iwajowa','Kajola','Lagelu','Ogbomosho North','Ogbomosho South','Ogo Oluwa','Olorunsogo','Oluyole','Ona Ara','Orelope','Ori Ire','Oyo East','Oyo West','Saki East','Saki West','Surulere'],
    // Abuja Federal Capital Territory
    'Abuja FCT': ['Abaji','Bwari','Gwagwalada','Kuje','Kwali','Municipal Area Council'],
    // Backwards-compat alias for any existing saved values.
    'FCT': ['Abaji','Bwari','Gwagwalada','Kuje','Kwali','Municipal Area Council'],
    'Ogun': ['Abeokuta North','Abeokuta South','Ado-Odo/Ota','Ewekoro','Ifo','Ijebu East','Ijebu North','Ijebu North East','Ijebu Ode','Ikenne','Imeko Afon','Ipokia','Obafemi Owode','Odeda','Odogbolu','Ogun Waterside','Remo North','Shagamu'],
    'Rivers': ['Port Harcourt','Obio/Akpor','Okrika','Ogu–Bolo','Eleme','Ikwerre','Etche','Omuma','Oyigbo','Tai','Gokana','Khana','Bonny','Andoni','Opobo–Nkoro','Asari-Toru','Akuku-Toru','Degema','Abua/Odual','Ahoada East','Ahoada West','Ogba/Egbema/Ndoni','Emohua'],
    'Kano': ['Dala','Fagge','Gwale','Kano Municipal','Nasarawa','Tarauni','Ungogo','Kumbotso'],
  };

  static List<String> lgasForState(String? state) {
    if (state == null || state.trim().isEmpty) return const [];
    return lgasByState[state] ?? const [];
  }

  /// Role-based state visibility rules.
  ///
  /// - `supplier`: can select all states EXCEPT Abuja.
  /// - `fieldProvider`, `nationalMalaria`, `nationalHIVTB`, `admin`, `superAdmin`: can select Abuja.
  /// - everyone else: Abuja is hidden.
  ///
  /// NOTE: We keep the UI label as `Abuja FCT`.
  static List<String> statesForRole(String? roleName) {
    final role = (roleName ?? '').trim();
    final allowAbuja = role == 'fieldProvider' || role == 'nationalMalaria' || role == 'nationalHIVTB' || role == 'admin' || role == 'superAdmin';
    final hideAbuja = role.isEmpty ? true : !allowAbuja;
    if (!hideAbuja) return states;
    return states.where((s) => s != 'Abuja FCT').toList(growable: false);
  }

  /// 3-letter state codes used in FieldProvider IDs.
  /// Kept explicit to avoid ambiguous abbreviations.
  static const Map<String, String> stateCode3 = {
    'Abia': 'ABI',
    'Adamawa': 'ADA',
    'Akwa Ibom': 'AKI',
    'Anambra': 'ANB',
    'Bauchi': 'BAU',
    'Bayelsa': 'BAY',
    'Benue': 'BEN',
    'Borno': 'BOR',
    'Cross River': 'CRS',
    'Delta': 'DEL',
    'Ebonyi': 'EBO',
    'Edo': 'EDO',
    'Ekiti': 'EKI',
    'Enugu': 'ENU',
    'Abuja FCT': 'ABU',
    'Gombe': 'GMB',
    'Imo': 'IMO',
    'Jigawa': 'JIG',
    'Kaduna': 'KAD',
    'Kano': 'KAN',
    'Katsina': 'KAT',
    'Kebbi': 'KEB',
    'Kogi': 'KOG',
    'Kwara': 'KWA',
    'Lagos': 'LAG',
    'Nasarawa': 'NAS',
    'Niger': 'NIG',
    'Ogun': 'OGU',
    'Ondo': 'OND',
    'Osun': 'OSU',
    'Oyo': 'OYO',
    'Plateau': 'PLA',
    'Rivers': 'RIV',
    'Sokoto': 'SOK',
    'Taraba': 'TAR',
    'Yobe': 'YOB',
    'Zamfara': 'ZAM',
  };

  static String? stateTo3LetterCode(String? state) {
    if (state == null || state.trim().isEmpty) return null;
    final normalized = state == 'FCT' ? 'Abuja FCT' : state;
    return stateCode3[normalized];
  }
}
