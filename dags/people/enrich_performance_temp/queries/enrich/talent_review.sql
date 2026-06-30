WITH
talent_rating_descriptions AS (
  SELECT
    hrlb.id_rating_level,
    hrlt.rating_description,
    hrlb.numeric_rating
  FROM
    datalake_pin_talent_clean.rating_level_base AS hrlb
  INNER JOIN
    datalake_pin_talent_clean.rating_level_translation AS hrlt
      ON hrlt.id_rating_level = hrlb.id_rating_level
      AND hrlt.language = 'US'
  INNER JOIN
    datalake_pin_talent_clean.rating_model_base AS hrmb
      ON hrmb.id_rating_model = hrlb.id_rating_model
  INNER JOIN
    datalake_pin_talent_clean.rating_model_translation AS hrmt
      ON hrmt.id_rating_model = hrmb.id_rating_model
      AND hrmt.language = 'US'
)

SELECT
  ei.assignment_number,
  ei.id_period_of_service,
  ei.id_person,
  hm.id_meeting,
  -- ids rating level
  COALESCE(i_rol.id_rating_level, -1) AS id_risk_loss_rating_level_initial,
  COALESCE(c_rol.id_rating_level, -1) AS id_risk_loss_rating_level_calibrated,
  COALESCE(i_cri.id_rating_level, -1) AS id_criticality_rating_level_initial, 
  COALESCE(c_cri.id_rating_level, -1) AS id_metric_calibrated_value_4,
  COALESCE(i_rea.id_rating_level, -1) AS id_readiness_rating_level_initial,
  COALESCE(c_rea.id_rating_level, -1) AS id_metric_calibrated_value_3,
  COALESCE(i_pot.id_rating_level, -1) AS id_potential_rating_level_initial,
  COALESCE(c_pot.id_rating_level, -1) AS id_potential_rating_level_calibrated,
  -- descriptions
  COALESCE(i_rol.rating_description, -1) AS initial_risk_of_loss,
  COALESCE(c_rol.rating_description, -1) AS calibrated_risk_of_loss,
  COALESCE(i_cri.rating_description, -1) AS initial_criticality,
  COALESCE(c_cri.rating_description, -1) AS calibrated_criticality,
  COALESCE(i_rea.rating_description, -1) AS initial_readiness,
  COALESCE(c_rea.rating_description, -1) AS calibrated_readiness,
  COALESCE(i_pot.rating_description, -1) AS initial_potential,
  COALESCE(c_pot.rating_description, -1) AS calibrated_potential,
  -- other descriptions
  hm.meeting_title AS committee_title,
  -- values
  i_rol.numeric_rating AS initial_numeric_risk_of_loss,
  c_rol.numeric_rating AS calibrated_numeric_risk_of_loss,
  i_cri.numeric_rating AS initial_numeric_criticality,
  c_cri.numeric_rating AS calibrated_numeric_criticality,
  i_rea.numeric_rating AS initial_numeric_readiness,
  c_rea.numeric_rating AS calibrated_numeric_readiness,
  i_pot.numeric_rating AS initial_numeric_potential,
  c_pot.numeric_rating AS calibrated_numeric_potential,
  -- dates and timestamps
  DATE(hm.ts_meeting) AS dt_committee_meeting,
  hrd.ts_created,
  hrd.ts_updated,
  NOW() AS ts_load
FROM
  datalake_people.identifier_mapping AS ei
LEFT JOIN
  datalake_pin_talent_clean.profile_base AS hpb
    ON hpb.id_person = ei.id_person
LEFT JOIN
  datalake_pin_hr_review_clean.dashboard AS hrd
    ON hrd.id_person = ei.id_person
LEFT JOIN
  datalake_pin_hr_review_clean.meeting AS hm
    ON hm.id_meeting = hrd.id_meeting
LEFT JOIN
  datalake_pin_hr_review_clean.dashboard_template_translation AS hdtt
    ON hdtt.id_dashboard_template = hm.id_dashboard_template
    AND hdtt.language = 'US'
-- initial ratings
LEFT JOIN
  talent_rating_descriptions AS i_rol
    ON i_rol.id_rating_level = hrd.id_risk_loss_rating_level
LEFT JOIN
  talent_rating_descriptions AS i_cri
    ON i_cri.id_rating_level = hrd.id_metric_value_4
LEFT JOIN
  talent_rating_descriptions AS i_rea
    ON i_rea.id_rating_level = hrd.id_metric_value_3
LEFT JOIN
  talent_rating_descriptions AS i_pot
    ON i_pot.id_rating_level = hrd.id_potential_rating_level
-- calibrated ratings
LEFT JOIN
  talent_rating_descriptions AS c_rol
    ON c_rol.id_rating_level = hrd.id_risk_loss_rating_level_calibrated
LEFT JOIN
  talent_rating_descriptions AS c_cri
    ON c_cri.id_rating_level = hrd.id_metric_calibrated_value_4
LEFT JOIN
  talent_rating_descriptions AS c_rea
    ON c_rea.id_rating_level = hrd.id_metric_calibrated_value_3
LEFT JOIN
  talent_rating_descriptions AS c_pot
    ON c_pot.id_rating_level = hrd.id_potential_rating_level_calibrated
    
WHERE
  ei.assignment_type IN ('E', 'C')
  AND (
    hdtt.name IS NULL
    OR hdtt.name = 'Talent Review'
  )