WITH
hr_system_workers AS (
  SELECT
    id_person,
    work_relationships,
    CASE
      WHEN DENSE_RANK() OVER (
        ORDER BY
          dt_effective
      ) = 1 THEN 'past'
      WHEN DENSE_RANK() OVER (
        ORDER BY
          dt_effective
      ) = 2 THEN 'present'
      WHEN DENSE_RANK() OVER (
        ORDER BY
          dt_effective
      ) = 3 THEN 'future'
    END AS data_moment
  FROM
    datalake_hr_system_clean.workers
),
work_rel_step1 AS (
  SELECT
    id_person,
    EXPLODE (work_relationships) AS work_relationships
  FROM
    hr_system_workers
  WHERE
    data_moment = 'future'
),
work_rel AS (
  SELECT
    id_person,
    work_relationships['PeriodOfServiceId']     AS id_period_of_service,
    work_relationships['LegalEntityId']         AS id_legal_entity,
    work_relationships['LegislationCode']       AS legislation_code,
    work_relationships['LegalEmployerName']     AS legal_employer_name,
    work_relationships['WorkerType']            AS worker_type,
    work_relationships['PrimaryFlag']           AS primary_flag,
    work_relationships['StartDate']             AS dt_start,
    work_relationships['OnMilitaryServiceFlag'] AS is_on_military_service,
    work_relationships['ReadyToConvertFlag']    AS is_ready_to_convert,
    work_relationships['TerminationDate']       AS dt_termination,
    work_relationships['NotificationDate']      AS dt_notification,
    work_relationships['RevokeUserAccess']      AS revoke_user_access,
    work_relationships['RecommendedForRehire']  AS recommended_for_rehire,
    work_relationships['CreatedBy']             AS created_by,
    TO_TIMESTAMP(
      SUBSTR(REPLACE(work_relationships['CreationDate'], 'T', ' '), 0, 19),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_created,
    work_relationships['LastUpdatedBy'] AS last_updated_by,
    TO_TIMESTAMP(
      SUBSTR(REPLACE(work_relationships['LastUpdateDate'], 'T', ' '), 0, 19),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_update,
    work_relationships['workRelationshipsDDF'] AS work_relationships_ddf,
    work_relationships['workRelationshipsDFF'] AS work_relationships_dff
  FROM
    work_rel_step1
),
work_relationships_ddf_step1 AS (
  SELECT
    id_person,
    id_period_of_service,
    EXPLODE (work_relationships_ddf) AS work_relationships_ddf
  FROM
    work_rel
),
work_relationships_ddf AS (
  SELECT
    id_person,
    id_period_of_service,
    work_relationships_ddf['_FIRST_EMPLOYMENT']         AS first_employment,
    work_relationships_ddf['_HIRING_TYPE']              AS hiring_type,
    work_relationships_ddf['_HIRING_TYPE_Display']      AS hiring_type_display,
    work_relationships_ddf['__FLEX_Context']            AS flex_content_ddf,
    work_relationships_ddf['_HIRING_INDICATOR']         AS hiring_indicator,
    work_relationships_ddf['_HIRING_INDICATOR_Display'] AS hiring_indicator_display
  FROM
    work_relationships_ddf_step1
),
work_relationships_dff_step1 AS (
  SELECT
    id_person,
    id_period_of_service,
    EXPLODE (work_relationships_dff) AS work_relationships_dff
  FROM
    work_rel
),
work_relationships_dff AS (
  SELECT
    id_person,
    id_period_of_service,
    work_relationships_dff['recrutador']                     AS recrutador,
    work_relationships_dff['dataPrevistaParaTerminoDoEstag'] AS dataPrevistaParaTerminoDoEstag
  FROM
    work_relationships_dff_step1
)
SELECT
  -- ids
  wr.id_period_of_service,
  -- non-ids
  wr.id_person,
  wr.id_legal_entity,
  -- non-metrics
  wr.legislation_code,
  wr.legal_employer_name,
  wr.worker_type,
  wr.revoke_user_access,
  wr.recommended_for_rehire,
  wr.created_by,
  wr.last_updated_by,
  wr_ddf.first_employment,
  wr_ddf.hiring_type,
  wr_ddf.hiring_type_display,
  wr_ddf.flex_content_ddf,
  wr_ddf.hiring_indicator,
  wr_ddf.hiring_indicator_display,
  wr_dff.recrutador AS recruiter,
  -- metrics
  BOOLEAN(wr.primary_flag) AS is_primary,
  BOOLEAN(wr.is_on_military_service) AS is_on_military_service,
  BOOLEAN(wr.is_ready_to_convert) AS is_ready_to_convert,
  -- dates
  DATE(wr.dt_start) AS dt_start,
  DATE(wr.dt_termination) AS dt_termination,
  DATE(wr.dt_notification) AS dt_notification,
  DATE(wr_dff.dataPrevistaParaTerminoDoEstag) AS dt_end_internship,
  -- timestamps
  wr.ts_created,
  wr.ts_last_update,
  NOW() ts_load
FROM
  work_rel AS wr
  LEFT JOIN 
    work_relationships_ddf AS wr_ddf 
      ON wr.id_person = wr_ddf.id_person
      AND wr.id_period_of_service = wr_ddf.id_period_of_service
  LEFT JOIN 
    work_relationships_dff AS wr_dff 
      ON wr.id_person = wr_dff.id_person
      AND wr.id_period_of_service = wr_dff.id_period_of_service