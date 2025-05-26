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
),
initial_talent_ratings AS (
  SELECT
    hpi.id_profile,
    hm_ctx.id_meeting AS id_reference_meeting,
    trd.id_rating_level,
    hptst.section_name,
    trd.rating_description,
    trd.numeric_rating,
    hpi.ts_created,
    hpi.ts_updated
  FROM
    datalake_pin_talent_clean.profile_item AS hpi
  INNER JOIN
    datalake_pin_talent_clean.profile_type_sections_translation AS hptst
      ON hpi.id_section = hptst.id_section
      AND hptst.language = 'US'
  INNER JOIN
    datalake_pin_hr_review_clean.meeting AS hm_ctx
        ON hpi.alternative_source_key_1 IS NULL
        OR hpi.alternative_source_key_1 <> hm_ctx.id_meeting
  LEFT JOIN
    talent_rating_descriptions AS trd
      ON trd.id_rating_level = hpi.id_rating_level
  WHERE
    hpi.ts_created < hm_ctx.ts_meeting
    AND (
      hpi.source_type = 'HRTR'
      OR hpi.created_by = 'FUSION_APPS_HCM_ESS_LOADER_APPID'
    )
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY hpi.id_profile, hpi.id_section, hm_ctx.id_meeting ORDER BY hpi.ts_created DESC) = 1
),
grouped_initial_ratings AS (
  SELECT
    id_profile,
    id_reference_meeting,
    -- risk of loss
    MAX(id_rating_level) FILTER (WHERE section_name IN ('Risco de Perda', 'Risk of Loss', 'Riesgo de Pérdida')) AS id_risk_loss_rating_level_initial,
    MAX(rating_description) FILTER (WHERE section_name IN ('Risco de Perda', 'Risk of Loss', 'Riesgo de Pérdida')) AS initial_risk_of_loss,
    MAX(ts_created) FILTER (WHERE section_name IN ('Risco de Perda', 'Risk of Loss', 'Riesgo de Pérdida')) AS ts_initial_risk_of_loss_created,
    MAX(ts_updated) FILTER (WHERE section_name IN ('Risco de Perda', 'Risk of Loss', 'Riesgo de Pérdida')) AS ts_initial_risk_of_loss_updated,
    MAX(numeric_rating) FILTER (WHERE section_name IN ('Risco de Perda', 'Risk of Loss', 'Riesgo de Pérdida')) AS initial_numeric_risk_of_loss,
    -- criticality
    MAX(id_rating_level) FILTER (WHERE section_name IN ('Criticidade', 'Criticality', 'Criticidad')) AS id_criticality_rating_level_initial,
    MAX(rating_description) FILTER (WHERE section_name IN ('Criticidade', 'Criticality', 'Criticidad')) AS initial_criticality,
    MAX(ts_created) FILTER (WHERE section_name IN ('Criticidade', 'Criticality', 'Criticidad')) AS ts_initial_criticality_created,
    MAX(ts_updated) FILTER (WHERE section_name IN ('Criticidade', 'Criticality', 'Criticidad')) AS ts_initial_criticality_updated,
    MAX(numeric_rating) FILTER (WHERE section_name IN ('Criticidade', 'Criticality', 'Criticidad')) AS initial_numeric_criticality,
    -- readiness
    MAX(id_rating_level) FILTER (WHERE section_name IN ('Prontidão para Promoção', 'Readiness', 'Disposición para Mover')) AS id_readiness_rating_level_initial,
    MAX(rating_description) FILTER (WHERE section_name IN ('Prontidão para Promoção', 'Readiness', 'Disposición para Mover')) AS initial_readiness,
    MAX(ts_created) FILTER (WHERE section_name IN ('Prontidão para Promoção', 'Readiness', 'Disposición para Mover')) AS ts_initial_readiness_created,
    MAX(ts_updated) FILTER (WHERE section_name IN ('Prontidão para Promoção', 'Readiness', 'Disposición para Mover')) AS ts_initial_readiness_updated,
    MAX(numeric_rating) FILTER (WHERE section_name IN ('Prontidão para Promoção', 'Readiness', 'Disposición para Mover')) AS initial_numeric_readiness,
    -- potential
    MAX(id_rating_level) FILTER (WHERE section_name IN ('Potencial', 'Career Potential')) AS id_potential_rating_level_initial,
    MAX(rating_description) FILTER (WHERE section_name IN ('Potencial', 'Career Potential')) AS initial_potential,
    MAX(ts_created) FILTER (WHERE section_name IN ('Potencial', 'Career Potential')) AS ts_initial_potential_created,
    MAX(ts_updated) FILTER (WHERE section_name IN ('Potencial', 'Career Potential')) AS ts_initial_potential_updated,
    MAX(numeric_rating) FILTER (WHERE section_name IN ('Potencial', 'Career Potential')) AS initial_numeric_potential
  FROM
    initial_talent_ratings
  GROUP BY
    id_profile,
    id_reference_meeting
)
SELECT
  ei.assignment_number,
  ei.id_period_of_service,
  hm.id_meeting,
  hrd.id_risk_loss_rating_level_calibrated,
  hrd.id_criticality_rating_level_calibrated,
  hrd.id_readiness_rating_level_calibrated,
  hrd.id_potential_rating_level_calibrated,
  gir.id_risk_loss_rating_level_initial,
  gir.id_criticality_rating_level_initial,
  gir.id_readiness_rating_level_initial,
  gir.id_potential_rating_level_initial,
  hm.meeting_title AS committee_title,
  gir.initial_risk_of_loss,
  c_rol.rating_description AS calibrated_risk_of_loss,
  gir.initial_criticality,
  c_cri.rating_description AS calibrated_criticality,
  gir.initial_readiness,
  c_rea.rating_description AS calibrated_readiness,
  gir.initial_potential,
  c_pot.rating_description AS calibrated_potential,
  gir.initial_numeric_risk_of_loss,
  c_rol.numeric_rating AS calibrated_numeric_risk_of_loss,
  gir.initial_numeric_criticality,
  c_cri.numeric_rating AS calibrated_numeric_criticality,
  gir.initial_numeric_readiness,
  c_rea.numeric_rating AS calibrated_numeric_readiness,
  gir.initial_numeric_potential,
  c_pot.numeric_rating AS calibrated_numeric_potential,
  DATE(hm.ts_meeting) AS dt_committee_meeting,
  gir.ts_initial_risk_of_loss_created,
  gir.ts_initial_risk_of_loss_updated,
  gir.ts_initial_criticality_created,
  gir.ts_initial_criticality_updated,
  gir.ts_initial_readiness_created,
  gir.ts_initial_readiness_updated,
  gir.ts_initial_potential_created,
  gir.ts_initial_potential_updated,
  NOW() AS ts_load
FROM
  datalake_hr_system.employee_ids AS ei
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
LEFT JOIN
  talent_rating_descriptions AS c_rol
    ON c_rol.id_rating_level = hrd.id_risk_loss_rating_level_calibrated
LEFT JOIN
  talent_rating_descriptions AS c_cri
    ON c_cri.id_rating_level = hrd.id_criticality_rating_level_calibrated
LEFT JOIN
  talent_rating_descriptions AS c_rea
    ON c_rea.id_rating_level = hrd.id_readiness_rating_level_calibrated
LEFT JOIN
  talent_rating_descriptions AS c_pot
    ON c_pot.id_rating_level = hrd.id_potential_rating_level_calibrated
LEFT JOIN
  grouped_initial_ratings AS gir
    ON gir.id_profile = hpb.id_profile
    AND gir.id_reference_meeting = hm.id_meeting
WHERE
  ei.assignment_type IN ('E', 'C')
  AND (
    hdtt.name IS NULL
    OR hdtt.name = 'Talent Review'
  )