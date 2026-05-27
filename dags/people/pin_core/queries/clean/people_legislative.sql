SELECT
  person_id AS id_person,
  person_legislative_id AS id_person_legislative,
  business_group_id AS id_business_group,
  created_by,
  last_updated_by AS updated_by,
  legislation_code,
  marital_status,
  sex AS legal_sex,
  highest_education_level,
  attribute16 AS highest_education_level_description,
  attribute_category AS citizenship_context,
  attribute1 AS nationality,
  attribute1 AS polling_station,
  attribute2 AS electoral_zone,
  attribute4 AS vote_registration_number,
  attribute2 AS foreigner_entry_classification,
  attribute28 AS foreigner_residence_time,
  per_information1 AS ctps_number,
  per_information2 AS ctps_series,
  attribute3 AS military_reservist_number,
  attribute8 AS github_username,
  attribute27 AS accessibility_need,
  attribute18 AS iban,
  attribute25 AS bank_name,
  attribute20 AS health_insurance_current_plan,
  attribute21 AS tax_residency_status,
  attribute24 AS rnh_program_application_status,
  attribute9 AS gender_identity,
  attribute10 AS sexual_orientation,
  attribute11 AS neurodiversity,
  attribute13 AS housing_type,
  attribute14 AS quinto_andar_joining_method,
  attribute15 AS country_situation,
  attribute26 AS disability_answer,
  attribute29 AS disability_type,
  CAST(object_version_number AS INT) AS object_version_number,
  CASE
    WHEN attribute3 IN ('S', 'Y') THEN TRUE
    WHEN attribute3 IN ('N') THEN FALSE
    ELSE NULL
  END AS is_foreigner_married_to_brazilian,
  CASE
    WHEN attribute4 IN ('S', 'Y') THEN TRUE
    WHEN attribute4 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_foreigner_brazilian_children,
  CASE
    WHEN attribute6 IN ('S', 'Y') THEN TRUE
    WHEN attribute6 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_hiring_bonus,
  CASE
    WHEN attribute7 IN ('S', 'Y') THEN TRUE
    WHEN attribute7 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_stock_option,
  CASE
    WHEN attribute17 IN ('S', 'Y') THEN TRUE
    WHEN attribute17 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_relocation_bonus,
  CASE
    WHEN attribute19 IN ('S', 'Y') THEN TRUE
    WHEN attribute19 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_health_insurance_portability,
  CASE
    WHEN attribute22 IN ('S', 'Y') THEN TRUE
    WHEN attribute22 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_been_tax_resident_portugal_last_5_years,
  CASE
    WHEN attribute23 IN ('S', 'Y') THEN TRUE
    WHEN attribute23 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_benefited_rnh_program,
  CASE
    WHEN attribute5 IN ('S', 'Y') THEN TRUE
    WHEN attribute5 IN ('N') THEN FALSE
    ELSE NULL
  END AS has_salary_advance,
  TO_DATE(attribute_date1) AS dt_foreigner_arrival,
  TO_DATE(per_information_date1) AS dt_ctps_issued,
  TO_DATE(marital_status_date) AS dt_marital_status,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_people_legislative_f
