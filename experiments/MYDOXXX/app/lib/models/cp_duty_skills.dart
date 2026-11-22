/// The clinical skills a care physician can tick under each hospital duty
/// type (from the "Basic Skill Sets" templates). Saved on the profile as
/// `dutySkills`: {dutyType: [skill, ...]}.
///
/// duty type -> [(group title, skills)]
const Map<String, List<(String, List<String>)>> cpDutySkills = {
  'ward': [
    ('Ward / Inpatient skills', [
      'General Ward Management',
      'Post-operative Patient Management',
      'Pre-operative Assessment',
      'Medication Administration & Monitoring',
      'IV Cannulation',
      'IV Fluid Management',
      'Injection Administration',
      'Blood Transfusion Monitoring',
      'Foley Catheterization',
      "Ryle's Tube / NG Tube Insertion",
      'Wound Dressing',
      'Suture Removal',
      'Drain Management',
      'Vitals & Clinical Monitoring',
      'ABG Sampling',
      'ECG Interpretation',
      'Basic Emergency Management',
      'Discharge Summary Preparation',
      'Case Sheet / Clinical Documentation',
      'Doctor–Patient Counselling',
      'Referral / Escalation of Patients',
    ]),
  ],
  'icu': [
    ('Basic ICU skills', [
      'ICU Patient Monitoring',
      'Critical Patient Assessment',
      'ABG Interpretation',
      'ECG Interpretation',
      'Electrolyte & Acid–Base Management',
      'Fluid & Hemodynamic Management',
      'Vasopressor Management',
      'Sepsis Management',
      'Shock Management',
      'Ventilator Monitoring',
      'Non-Invasive Ventilation (NIV)',
      'Oxygen Therapy',
    ]),
    ('Advanced ICU skills', [
      'Endotracheal Intubation',
      'Mechanical Ventilation Management',
      'Central Venous Catheter Assistance / Management',
      'Arterial Line Monitoring',
      'Sedation & Analgesia',
      'Invasive Hemodynamic Monitoring',
      'CPR / BLS',
      'ACLS',
      'Defibrillation',
      'Code Blue Management',
      'Multi-organ Failure Management',
      'ICU Referral / Transfer',
    ]),
  ],
  'casualty': [
    ('Casualty / Emergency skills', [
      'Primary Survey / ABCDE Assessment',
      'Emergency Patient Assessment',
      'Trauma Management',
      'Acute Medical Emergencies',
      'CPR / BLS',
      'ACLS',
      'Airway Management',
      'Bag-Valve-Mask Ventilation',
      'Intubation',
      'Defibrillation',
      'ECG Interpretation',
      'Acute Chest Pain Management',
      'Acute Stroke Assessment',
      'Seizure Management',
      'Anaphylaxis Management',
      'Poisoning / Toxicology Management',
      'Acute Asthma / COPD Management',
      'Shock Management',
      'Suturing',
      'Local Anaesthesia',
      'Splinting / Basic Fracture Management',
      'RTA / Polytrauma Initial Management',
      'Medicolegal Case (MLC) Handling',
      'Emergency Referral / Transfer',
    ]),
  ],
  'specialty': [
    ('Pediatric skills', [
      'Pediatric OPD',
      'Pediatric Emergency',
      'Pediatric Patient Assessment',
      'Pediatric Drug / Dose Calculation',
      'Pediatric IV Cannulation',
      'Pediatric Fluid Management',
      'Nebulization',
      'Pediatric CPR / BLS',
      'Pediatric Advanced Life Support (PALS)',
      'Febrile Seizure Management',
      'Dehydration Management',
      'Respiratory Distress Management',
      'Neonatal Resuscitation',
      'Newborn Assessment',
    ]),
  ],
};

/// The skills saved on a profile for [dutyType] (only ones still listed).
List<String> cpSkillsOf(Map<String, dynamic> profile, String dutyType) {
  final saved = profile['dutySkills'];
  if (saved is! Map) return const [];
  final list = saved[dutyType];
  if (list is! List) return const [];
  final known = {
    for (final g in cpDutySkills[dutyType] ?? const <(String, List<String>)>[])
      ...g.$2
  };
  return [for (final s in list) if (known.contains(s.toString())) s.toString()];
}
