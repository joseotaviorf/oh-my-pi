WITH person_score AS (
  SELECT
    c.id AS id_score_consultation,
    c.id_person,
    c.value AS score_value,
    c.risk,
    r.name AS risk_classification,
    c.id_bureau,
    b.name AS bureau_name,
    vp.value AS score_personal_value,
    vp.declared AS declared_income,
    vp.requested AS requested_income,
    ROW_NUMBER() OVER(PARTITION BY c.id_person ORDER BY c.ts_updated DESC, c.ts_inserted DESC) AS rn
  FROM
    datalake_velo_clean.veloscore_consultations AS c
  LEFT JOIN
    datalake_velo_clean.veloscore_bureau AS b
      ON b.id = c.id_bureau
  LEFT JOIN
    datalake_velo_clean.veloscore_personal AS vp
      ON vp.consultations = c.id
  LEFT JOIN
    datalake_velo_clean.veloscore_risk AS r
      ON r.id = c.risk
),
main_client AS (
  SELECT
    id_propose,
    id_person AS id_primary_person,
    ROW_NUMBER() OVER(PARTITION BY id_propose ORDER BY ts_updated DESC) AS rn
  FROM
    datalake_velo_clean.fiancavelo_proposeperson
  WHERE
    is_active
      AND id_type = 1 -- bringing only main IQ
)

SELECT DISTINCT
  cp.id AS id_person,
  pp.id_propose,
  TRIM(UPPER(cp.name)) AS name,
  cp.email,
  cp.phone,
  prs.bureau_name,
  cp.document,
  prs.score_value AS serasa_score,
  prs.risk AS risk_score,
  prs.risk_classification,
  prs.score_personal_value,
  prs.declared_income,
  prs.requested_income,
  mc.id_primary_person IS NOT NULL AS is_primary_person,
  cp.dt_birth
FROM
  datalake_velo_clean.clientes_person AS cp
LEFT JOIN
  datalake_velo_clean.fiancavelo_proposeperson AS pp
    ON pp.id_person = cp.id
LEFT JOIN
  person_score AS prs
    ON prs.id_person =  cp.id
      AND prs.rn = 1
LEFT JOIN
  main_client AS mc
    ON mc.id_primary_person = cp.id
    AND mc.id_propose = pp.id_propose
