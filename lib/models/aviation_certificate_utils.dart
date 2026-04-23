String normalizeCertificateName(String certificate) {
  final normalized = certificate.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );

  switch (normalized) {
    case 'airline transport pilot':
    case 'airline transport pilot (atp)':
    case 'atp':
      return 'airline transport pilot';
    case 'commercial pilot':
    case 'commercial pilot (cpl)':
    case 'cpl':
      return 'commercial pilot';
    case 'instrument rating':
    case 'instrument rating (ifr)':
    case 'ifr':
      return 'instrument rating';
    case 'private pilot':
    case 'private pilot (ppl)':
    case 'ppl':
    case 'private pilot (pp)':
    case 'pp':
      return 'private pilot';
    case 'rotorcraft':
    case 'helicopter':
      return 'helicopter';
    default:
      return normalized;
  }
}

String canonicalCertificateLabel(String certificate) {
  return normalizeCertificateName(certificate) == 'private pilot'
      ? 'Private Pilot (PPL)'
      : normalizeCertificateName(certificate) == 'helicopter'
      ? 'Helicopter'
      : certificate;
}

Set<String> expandedCertificateQualifications(String certificate) {
  final normalized = normalizeCertificateName(certificate);

  switch (normalized) {
    case 'airline transport pilot':
      return {
        'airline transport pilot',
        'commercial pilot',
        'instrument rating',
        'private pilot',
      };
    case 'commercial pilot':
      return {'commercial pilot', 'private pilot'};
    default:
      return {normalized};
  }
}
