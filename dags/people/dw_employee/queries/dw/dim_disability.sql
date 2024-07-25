WITH disabilities_step1 AS (
  SELECT
    id_person,
    EXPLODE(disabilities) AS disabilities
  FROM
    datalake_hr_system_clean.workers QUALIFY 2 = DENSE_RANK() OVER (
      PARTITION BY id_person
      ORDER BY
        dt_effective
    )
),
self_declaration AS (
  SELECT
    id_person,
    legislation_code,
    disability_self_declaration_code,
    disability_self_declaration_description,
    has_disability,
    dt_effective_start
  FROM
    datalake_hr_system.demographic_attributes
  WHERE
    disability_self_declaration_code IS NOT NULL
    OR disability_self_declaration_description IS NOT NULL
    OR has_disability IS TRUE
)
SELECT
  DISTINCT MD5(
    CONCAT(
      COALESCE(disabilities ['Category'], '-1'),
      COALESCE(disabilities ['Status'], '-1'),
      COALESCE(disability_self_declaration_code, '-1'),
      COALESCE(has_disability, FALSE)
    )
  ) AS sk_disability,
  COALESCE(disabilities ['Category'], '-1') AS disability_category_code,
  CASE
    WHEN disabilities ['Category'] = 'ORA_HRX_MOTOR_D'
    AND disabilities ['LegislationCode'] = 'BR' THEN 'Deficiência Motora'
    WHEN disabilities ['Category'] = 'SA_HEA_IMP'
    AND disabilities ['LegislationCode'] = 'BR' THEN 'Deficiência auditiva'
    WHEN disabilities ['Category'] = 'SA_VIS_IMP'
    AND disabilities ['LegislationCode'] = 'BR' THEN 'Deficiência visual'
    WHEN disabilities ['Category'] = 'SA_INT_DIS'
    AND disabilities ['LegislationCode'] = 'BR' THEN 'Distúrbio mental'
    WHEN disabilities ['Category'] = 'ORA_HRX_MENTAL_D'
    AND disabilities ['LegislationCode'] = 'BR' THEN 'Distúrbio mental'
    WHEN disabilities ['Category'] = '99'
    AND disabilities ['LegislationCode'] = 'BR' THEN 'Prefiro Não Informar'
    ELSE '-1'
  END AS disability_category,
  COALESCE(disabilities ['Status'], '-1') AS disability_status,
  COALESCE(disability_self_declaration_code, '-1') AS disability_self_declaration_code,
  COALESCE(disability_self_declaration_description, '-1') AS disability_self_declaration_description,
  COALESCE(has_disability, FALSE) AS is_self_declared_disabled,
  NOW() AS ts_load
FROM
  disabilities_step1 ds1 FULL
  OUTER JOIN self_declaration sd ON ds1.id_person = sd.id_person
  AND ds1.disabilities ['LegislationCode'] = sd.legislation_code
WHERE
  GREATEST(
    DATE(disabilities ['EffectiveStartDate']),
    sd.dt_effective_start
  ) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')