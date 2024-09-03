WITH
  workers AS (
    SELECT 
      id_person,
      disabilities
    FROM datalake_hr_system_clean.workers
    QUALIFY 2 = DENSE_RANK() OVER (
        PARTITION BY
          id_person
        ORDER BY
          dt_effective
      )
  ),
  disabilities_step1 AS (
    SELECT
      id_person,
      EXPLODE (disabilities) AS disabilities
    FROM
      workers 
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
  w.id_person,
  MD5(
    CONCAT(
      COALESCE(ds1.disabilities['Category'], '-1'),
      COALESCE(ds1.disabilities['Status'], '-1'),
      COALESCE(disability_self_declaration_code, '-1')
    )
  ) AS sk_disability,
  COALESCE(ds1.disabilities['Category'], '-1') AS disability_category_code_wdoc,
  CASE
    WHEN ds1.disabilities['Category'] = 'ORA_HRX_MOTOR_D'
    AND ds1.disabilities['LegislationCode'] = 'BR' THEN 'Deficiência Motora'
    WHEN ds1.disabilities['Category'] = 'SA_HEA_IMP'
    AND ds1.disabilities['LegislationCode'] = 'BR' THEN 'Deficiência auditiva'
    WHEN ds1.disabilities['Category'] = 'SA_VIS_IMP'
    AND ds1.disabilities['LegislationCode'] = 'BR' THEN 'Deficiência visual'
    WHEN ds1.disabilities['Category'] = 'SA_INT_DIS'
    AND ds1.disabilities['LegislationCode'] = 'BR' THEN 'Distúrbio mental'
    WHEN ds1.disabilities['Category'] = 'ORA_HRX_MENTAL_D'
    AND ds1.disabilities['LegislationCode'] = 'BR' THEN 'Distúrbio mental'
    WHEN ds1.disabilities['Category'] = '99'
    AND ds1.disabilities['LegislationCode'] = 'BR' THEN 'Prefiro Não Informar'
    ELSE '-1'
  END AS disability_category_wdoc,
  COALESCE(ds1.disabilities['Status'], '-1') AS disability_status_wdoc,
  COALESCE(disability_self_declaration_code, '-1') AS disability_self_declaration_code,
  COALESCE(disability_self_declaration_description, '-1') AS disability_self_declaration_description,
  COALESCE(has_disability, FALSE) AS has_self_declared_disability,
  GREATEST (DATE(ds1.disabilities['EffectiveStartDate']), sd.dt_effective_start) AS dt_effective_start,
  NOW() AS ts_load
FROM workers AS w 
  LEFT JOIN 
    disabilities_step1 ds1
    ON w.id_person = ds1.id_person
  LEFT JOIN 
    self_declaration sd 
    ON w.id_person = sd.id_person
WHERE ds1.id_person is NOT NULL 
  or sd.id_person is NOT NULL