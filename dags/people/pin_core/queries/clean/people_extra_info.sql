SELECT
  person_extra_info_id AS id_person_extra_info,
  person_id AS id_person,
  enterprise_id AS id_enterprise,
  pei_information1 AS id_meeting,
  pei_information3 AS id_rating_impact,
  pei_information4 AS id_rating_behavior,
  pei_information5 AS id_rating_leadership,
  information_type,
  pei_information_category AS information_category,
  CASE
    WHEN information_type = 'Contatos de Emergência' 
    THEN pei_information2
  END AS contact_relationship,
  category_code,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(pei_information2) AS dt_evaluation,
  TO_DATE(effective_start_date) AS dt_effective_started,
  COALESCE(
    NULLIF(TO_DATE(effective_end_date), DATE('4712-12-31')),
    DATE('9999-12-31')
  ) AS dt_effective_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  CURRENT_TIMESTAMP() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_people_extra_info_f
