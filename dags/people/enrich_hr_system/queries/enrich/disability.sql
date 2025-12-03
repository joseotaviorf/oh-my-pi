WITH
disabilities AS (
  SELECT
    id_person,
    person_number,
    disabilities[0].DisabilityId AS id_disability,
    disabilities[0].Category AS documented_code,
    disabilities[0].Status AS status_documented,
    legislative_info[0].legislativeInfoDFF[0].deficienciaAutodeclaracao AS self_declared_code,
    disabilities[0].CreatedBy AS created_by_documented,
    disabilities[0].LastUpdatedBy AS updated_by_documented,
    COALESCE(legislative_info[0].legislativeInfoDFF[0].possuiAlgumaDeficiencia = 'Sim', False) AS has_self_declared_disability,
    CAST(disabilities[0].CreationDate AS TIMESTAMP) AS ts_documented_created,
    CAST(disabilities[0].LastUpdateDate AS TIMESTAMP) AS ts_documented_updated,
    ts_load
  FROM
    datalake_hr_system_clean.workers
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY person_number ORDER BY dt_effective) = 2
),
selfdeclared_lookup AS (
  SELECT
    lookup_code,
    meaning
  FROM
    datalake_pin_core_clean.lookup
  WHERE
    lookup_type = 'QA_DEF_AUTODECLARADA'
),
enriched_disabilities AS (
  SELECT
    id_person,
    person_number,
    id_disability,
    documented_code,
    self_declared_code,
    CASE
      WHEN documented_code IN ('SA_HEA_IMP', 'ORA_HRX_AUDITORY_D') THEN 'Deficiência auditiva'
      WHEN documented_code IN ('SA_VIS_IMP', 'ORA_HRX_VISUAL_D') THEN 'Deficiência visual'
      WHEN documented_code IN ('SA_INT_DIS', 'ORA_HRX_INTELLECTUAL_D') THEN 'Deficiência intelectual'
      WHEN documented_code = 'ORA_HRX_MOTOR_D' THEN 'Deficiência física'
      WHEN documented_code = 'ORA_HRX_MENTAL_D' THEN 'Deficiência mental/psicossocial'
      WHEN documented_code = 'ORA_HRX_MULTIPLE_D' THEN 'Deficiência Múltipla'
      WHEN documented_code = 'ORA_HRX_REHABILITATED' THEN 'Reabilitado'
      WHEN documented_code = 'ORA_HRX_P_DEV_DIS' THEN 'Transtorno Global do Desenvolvimento (TEA/Autismo)'
      WHEN documented_code = 'Múltiplo' THEN 'Múltiplas'
      WHEN documented_code = '6' THEN 'Deficiência mental/psicossocial'
      ELSE documented_code || '*'
    END AS documented_name,
    look.meaning AS self_declared_name,
    status_documented,
    created_by_documented,
    updated_by_documented,
    COALESCE(status_documented = 'A', False) AS has_documented_active_disability,
    COALESCE(status_documented = 'P', False) AS has_documented_pending_disability,
    has_self_declared_disability,
    ts_documented_created,
    ts_documented_updated,
    ts_load
  FROM
    disabilities
  LEFT JOIN
    selfdeclared_lookup AS look
      ON look.lookup_code = disabilities.self_declared_code
)
SELECT
  id_person,
  id_disability,
  MD5(
    CONCAT(
      COALESCE(CASE
        WHEN has_documented_active_disability THEN documented_name
      END, '-1'),
      COALESCE(self_declared_name, '-1'),
      has_documented_active_disability,
      has_self_declared_disability,
      has_documented_pending_disability
    )
  ) AS sk_disability,
  MD5(
    CONCAT(
      COALESCE(documented_name, '-1'),
      COALESCE(self_declared_name, '-1'),
      status_documented,
      has_self_declared_disability
    )
  ) AS sk_disability_all_status,
  person_number,
  documented_code,
  self_declared_code,
  documented_name,
  CASE
    WHEN has_documented_active_disability THEN documented_name
  END AS documented_name_active,
  status_documented,
  self_declared_name,
  created_by_documented,
  updated_by_documented,
  has_documented_active_disability,
  has_documented_pending_disability,
  has_self_declared_disability,
  ts_documented_created,
  ts_documented_updated,
  NOW() AS ts_load
FROM
  enriched_disabilities