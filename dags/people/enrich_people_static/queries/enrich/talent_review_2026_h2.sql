WITH
translated_grade AS (
  SELECT
    assignment_number,
    CASE review_month
      WHEN 'fev./26' THEN '2026-02'
      WHEN 'set./26' THEN '2026-09'
    END AS review_month,
    CASE potential
      WHEN 'Alto' THEN 'High'
      WHEN 'Médio' THEN 'Medium'
      WHEN 'Baixo' THEN 'Low'
    END AS calibrated_potential,
    CASE readiness
      WHEN 'Pronto agora' THEN 'Ready now'
      WHEN 'Pronto entre 6 meses e 1 ano' THEN 'Ready in 6 months - 1 years'
      WHEN 'Pronto entre 1 e 2 anos' THEN 'Ready in 1 - 2 years'
      WHEN 'Sem perspectiva de promoção' THEN 'Unlikely to be promoted'
      WHEN 'Atenção: necessita desenvolvimento' THEN 'Attention - needs development'
    END AS calibrated_readiness,
    CASE criticality
      WHEN 'Sim' THEN 'Yes'
      WHEN 'Não' THEN 'No'
    END AS calibrated_criticality,
    CASE risk_of_loss
      WHEN 'Alto' THEN 'High'
      WHEN 'Médio' THEN 'Medium'
      WHEN 'Baixo' THEN 'Low'
    END AS calibrated_risk_of_loss,
    ts_load
  FROM
    datalake_gsheets_people_clean.talent_review_h2_26
  WHERE
    review_month IN ('set./26', 'fev./26')
),
rated AS (
  SELECT
    assignment_number,
    review_month,
    calibrated_potential,
    calibrated_readiness,
    calibrated_criticality,
    calibrated_risk_of_loss,
    CASE calibrated_potential
      WHEN 'High' THEN 3
      WHEN 'Medium' THEN 2
      WHEN 'Low' THEN 1
    END AS calibrated_numeric_potential,
    CASE calibrated_readiness
      WHEN 'Attention - needs development' THEN 2
      WHEN 'Unlikely to be promoted' THEN 4
      WHEN 'Ready in 1 - 2 years' THEN 6
      WHEN 'Ready in 6 months - 1 years' THEN 8
      WHEN 'Ready now' THEN 10
    END AS calibrated_numeric_readiness,
    CASE calibrated_criticality
      WHEN 'Yes' THEN 1
      WHEN 'No' THEN 0
    END AS calibrated_numeric_criticality,
    CASE calibrated_risk_of_loss
      WHEN 'High' THEN 3
      WHEN 'Medium' THEN 2
      WHEN 'Low' THEN 1
    END AS calibrated_numeric_risk_of_loss,
    ts_load
  FROM
    translated_grade
)
-- The workbook has one grade per dimension. It is stored as the calibrated rating.
-- Manager ratings stay unknown so calibration variation is not invented.
SELECT
  mapping.id_period_of_service,
  committee.id_meeting,
  rated.assignment_number,
  CAST(NULL AS STRING) AS initial_potential,
  CAST(NULL AS STRING) AS initial_readiness,
  CAST(NULL AS STRING) AS initial_criticality,
  CAST(NULL AS STRING) AS initial_risk_of_loss,
  rated.calibrated_potential,
  rated.calibrated_readiness,
  rated.calibrated_criticality,
  rated.calibrated_risk_of_loss,
  CAST(NULL AS DOUBLE) AS initial_numeric_potential,
  CAST(NULL AS DOUBLE) AS initial_numeric_readiness,
  CAST(NULL AS DOUBLE) AS initial_numeric_criticality,
  CAST(NULL AS DOUBLE) AS initial_numeric_risk_of_loss,
  CAST(rated.calibrated_numeric_potential AS DOUBLE) AS calibrated_numeric_potential,
  CAST(rated.calibrated_numeric_readiness AS DOUBLE) AS calibrated_numeric_readiness,
  CAST(rated.calibrated_numeric_criticality AS DOUBLE) AS calibrated_numeric_criticality,
  CAST(rated.calibrated_numeric_risk_of_loss AS DOUBLE) AS calibrated_numeric_risk_of_loss,
  (
    rated.calibrated_numeric_potential IS NOT NULL
    AND rated.calibrated_numeric_readiness IS NOT NULL
    AND rated.calibrated_numeric_criticality IS NOT NULL
    AND rated.calibrated_numeric_risk_of_loss IS NOT NULL
  ) AS has_calibrated_rating,
  DATE(committee.ts_meeting) AS dt_committee_meeting,
  rated.ts_load AS ts_created,
  rated.ts_load AS ts_updated,
  NOW() AS ts_load
FROM
  rated
INNER JOIN
  datalake_people.talent_review_committee_2026_h2 AS committee
    ON committee.review_month = rated.review_month
INNER JOIN
  datalake_people.identifier_mapping AS mapping
    ON mapping.assignment_number = rated.assignment_number
