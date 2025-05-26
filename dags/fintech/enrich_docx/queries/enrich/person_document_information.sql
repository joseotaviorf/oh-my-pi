WITH get_data AS (
  SELECT
    pdi.id AS id_person_document_info,
    pdi.id_input_source AS id_input_source,
    pd.id_person,
    pdi.id_person_document,
    CASE
      WHEN
        pdi.input_value_type = 'INTEGER'
        AND pdi.input_type = 'USER_ID'
      THEN
        CAST(input_value AS INTEGER)
    END AS id_user,
    p.user_person_uuid,
    p.person_uuid,
    input_source_type,
    input_type,
    input_value,
    status AS person_document_info_status,
    pd.type AS document_type,
    pd.country_code,
    CASE
      WHEN
        pdi.input_value_type = 'BOOLEAN'
        AND pdi.input_type = 'TEST_GROUP_FLAG'
      THEN
        CAST(input_value AS BOOLEAN)
    END AS is_in_test_group,
    CASE
      WHEN
        pdi.input_value_type = 'BOOLEAN'
        AND pdi.input_type = 'EARLY_CREDIT_ELIGIBILITY_FLAG'
      THEN
        CAST(input_value AS BOOLEAN)
    END AS is_early_credit_criteria_satisfied,
    CASE
      WHEN
        pdi.input_value_type = 'BOOLEAN'
        AND pdi.input_type = 'ELIGIBILITY_FLAG'
      THEN
        CAST(input_value AS BOOLEAN)
    END AS is_eligible_criteria_satisfied,
    CASE
      WHEN
        pdi.input_value_type = 'BOOLEAN'
        AND pdi.input_type = 'APP_VERSION_ELIGIBILITY_FLAG'
      THEN
        CAST(input_value AS BOOLEAN)
    END AS is_app_version_updated,
    CASE
      WHEN
        pdi.input_value_type = 'BOOLEAN'
        AND pdi.input_type = 'FEATURE_ENABLED_FLAG'
      THEN
        CAST(input_value AS BOOLEAN)
    END AS is_feature_enabled,
    CASE
      WHEN
        pdi.input_value_type = 'BOOLEAN'
        AND pdi.input_type = 'WILL_RESIDE'
      THEN
        CAST(input_value AS BOOLEAN)
    END AS is_going_to_reside,
    CASE
      WHEN
        pdi.input_value_type = 'STRING'
        AND pdi.input_type = 'INCOME_NATURE'
      THEN
        CAST(input_value AS STRING)
    END AS income_nature,
    CASE
      WHEN
        pdi.input_value_type = 'DOUBLE'
        AND pdi.input_type = 'INFORMED_INCOME'
      THEN
        CAST(input_value AS DOUBLE)
    END AS informed_income,
    pdi.ts_last_validated,
    rev.ts_rev AS ts_updated,
    ROW_NUMBER() OVER (PARTITION BY pdi.id ORDER BY rev.ts_rev DESC) AS version
  FROM
    datalake_docx_clean.person_document_info_aud AS pdi
  INNER JOIN
    datalake_docx_clean.person_document AS pd
      ON pd.id = pdi.id_person_document
  INNER JOIN
    datalake_docx_clean.person AS p
      ON p.id = pd.id_person
  INNER JOIN
    datalake_docx_clean.rev_info AS rev
      ON rev.rev = pdi.rev
),
get_user_id AS (
  SELECT
    id_person,
    id_user
  FROM
    get_data
  WHERE
    input_type = 'USER_ID' AND
    version = 1
)
  SELECT
    gd.id_person_document_info,
    gd.id_person,
    gu.id_user,
    gd.user_person_uuid AS uuid_user_person,
    gd.person_uuid AS uuid_person,
    gd.person_document_info_status,
    gd.input_type,
    gd.income_nature,
    gd.informed_income,
    gd.is_in_test_group,
    COALESCE(
      gd.is_early_credit_criteria_satisfied, gd.is_eligible_criteria_satisfied
    ) AS is_early_credit_criteria_satisfied,
    gd.is_app_version_updated,
    gd.is_feature_enabled,
    gd.is_going_to_reside,
    gd.ts_last_validated,
    gd.ts_updated,
    gd.version
  FROM
    get_data AS gd
  LEFT JOIN
    get_user_id AS gu
      ON gu.id_person = gd.id_person
  WHERE
    gd.document_type IN ('INCOME', 'TENANT_CREDIT_PRE_APPROVAL_BY_CITY_CONFIG', 'RENT_INFO')
