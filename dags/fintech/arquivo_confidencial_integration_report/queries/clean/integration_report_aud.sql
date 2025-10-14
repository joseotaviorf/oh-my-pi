SELECT
    id,
    cpf,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    integration_provider,
    raw_data,
    attributes,
    CASE
      WHEN TRIM(UPPER(integration_provider)) IN ('SERASA_REPORT_HVA4', 'SERASA_REPORT_HSPA')
        THEN CAST(GET_JSON_OBJECT(attributes, '$.reports[0].score.score') AS INT)
      WHEN TRIM(UPPER(integration_provider)) IN ('SERASA_SCORE_HSPI','SERASA_SCORE_HSPN')
        THEN CAST(GET_JSON_OBJECT(attributes, '$.score') AS INT)
    END AS score_serasa,
    CASE
      WHEN TRIM(UPPER(integration_provider)) = 'SERASA_REPORT_HVA4'
        THEN CAST(GET_JSON_OBJECT(attributes, '$.reports[0].score.score') AS INT)
    END AS hva4_serasa,
    CASE
      WHEN TRIM(UPPER(integration_provider)) = 'SERASA_REPORT_HSPA'
        THEN CAST(GET_JSON_OBJECT(attributes, '$.reports[0].score.score') AS INT)
    END AS hspa_serasa,
    CASE
      WHEN TRIM(UPPER(integration_provider)) = 'SERASA_SCORE_HSPI'
        THEN CAST(GET_JSON_OBJECT(attributes, '$.score') AS INT)
    END AS hspi_serasa,
    CASE
      WHEN TRIM(UPPER(integration_provider)) = 'SERASA_SCORE_HSPN'
        THEN CAST(GET_JSON_OBJECT(attributes, '$.score') AS INT)
    END AS hspn_serasa,
    CASE
      WHEN TRIM(UPPER(integration_provider)) = 'SERASA_REPORT_HSPA'
        THEN GET_JSON_OBJECT(attributes, '$.reports[0].negativeData.pefin.summary.count')
    END AS serasa_pefin_count,
    CASE
      WHEN TRIM(UPPER(integration_provider)) = 'BOAVISTA_SCORE_P6'
        THEN GET_JSON_OBJECT(attributes, '$.score_p6')
    END AS bvs_score,
    created_at AS ts_created,
    CAST(year AS INT) AS year,
    CAST(month AS INT) AS month,
    CAST(day AS INT) AS day
FROM
    datalake_arquivo_confidencial_raw.integration_report_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
