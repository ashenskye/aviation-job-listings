const String legacyTotalInstructorHoursLabel = 'Total Instructor Hours';
const String flightInstructionCfiHourLabel = 'Flight Instruction (CFI)';

const List<String> availableFaaCertificateOptions = [
  'Airline Transport Pilot (ATP)',
  'Commercial Pilot (CPL)',
  'Instrument Rating (IFR)',
  'Private Pilot (PPL)',
  'Airframe & Powerplant (A&P)',
  'Inspection Authorization (IA)',
  'Dispatcher (DSP)',
];

const List<String> availableInstructorCertificateOptions = [
  'Flight Instructor (CFI)',
  'Instrument Instructor (CFII)',
  'Multi-Engine Instructor (MEI)',
];

const List<String> availableFaaRuleOptions = [
  'Part 121',
  'Part 135',
  'Part 91',
];

const List<String> availableEmployerFlightHourOptions = [
  'Total Time',
  'Total PIC Time',
  'Total SIC Time',
  'PIC Turbine',
  'SIC Turbine',
  'PIC Jet',
  'SIC Jet',
  'Multi-engine',
  'Instrument',
  'Cross-Country',
  'Night',
];

const List<String> availableInstructorHourOptions = [
  flightInstructionCfiHourLabel,
  'Instrument (CFII)',
  'Multi-Engine (MEI)',
];

final Set<String> instructorHourOptionSet =
    {...availableInstructorHourOptions, legacyTotalInstructorHoursLabel};

String normalizeInstructorHourLabel(String label) {
  return label == legacyTotalInstructorHoursLabel
      ? flightInstructionCfiHourLabel
      : label;
}

const List<String> availableSpecialtyExperienceOptions = [
  'Fire Fighting',
  'Aerobatic',
  'Floatplane',
  'Ski-plane',
  'Alaska Time',
  'Tailwheel',
  'Off Airport',
  'Banner Towing',
  'Low Altitude',
  'Aerial Survey',
];

const List<String> availableJobTypeOptions = [
  'Full-Time',
  'Part-Time',
  'Seasonal',
  'Rotations',
  'Contract',
];

const List<String> availablePayRateMetricOptions = [
  'Flight Hour',
  'Hourly Pay for Duty Time',
  'Daily Rate',
  'Weekly Salary',
  'Monthly Salary',
  'Annual Salary',
  'Shift',
  'Contract Completion',
];

const List<String> landRatingSelectionOptions = [
  'Single-Engine Land',
  'Multi-Engine Land',
];

const List<String> seaRatingSelectionOptions = [
  'Single-Engine Sea',
  'Multi-Engine Sea',
];

const List<String> tailwheelRatingSelectionOptions = [
  'Tailwheel Endorsement',
];

const List<String> rotorRatingSelectionOptions = [
  'Helicopter',
  'Gyroplane',
];

const List<String> otherRatingSelectionOptions = [
  'Glider',
  'Lighter-than-Air',
];

const List<List<String>> groupedRatingSelectionOptions = [
  landRatingSelectionOptions,
  seaRatingSelectionOptions,
  tailwheelRatingSelectionOptions,
  rotorRatingSelectionOptions,
  otherRatingSelectionOptions,
];

const List<String> availableRatingSelectionOptions = [
  ...landRatingSelectionOptions,
  ...seaRatingSelectionOptions,
  ...tailwheelRatingSelectionOptions,
  ...rotorRatingSelectionOptions,
  ...otherRatingSelectionOptions,
];