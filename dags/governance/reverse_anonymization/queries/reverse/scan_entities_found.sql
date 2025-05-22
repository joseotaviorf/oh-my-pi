WITH dag_info AS (
  SELECT
      d.id_dag,
      CASE
        WHEN d.owners in ('Data ForRent', 'Data ForRent, airflow', 'airflow, Data ForRent', 'Data International', 'airflow, Data International', 'Data International, airflow') THEN 'For Rent'
        WHEN d.owners IN ('Data SS', 'Data SS, airflow', 'airflow, Data SS') THEN 'Support & Services'
        WHEN d.owners IN ('Data Engineering', 'Data Engineering, airflow', 'airflow, Data Engineering') THEN 'Data Engineering'
        WHEN d.owners IN ('Data Ingestion', 'airflow, Data Ingestion', 'airflow, Data Ingestion', 'Data Life Cycle', 'Data Life Cycle, airflow', 'airflow, Data Life Cycle') THEN 'Data Ingestion'
        WHEN d.owners IN ('Data Rede', 'Data Rede, airflow', 'Data Agents', 'airflow, Data Agents') THEN 'Partners'
        WHEN d.owners IN ('Data Agents, airflow') THEN 'Agents'
        WHEN d.owners IN ('airflow, Data Rede') THEN 'Rede'
        WHEN d.owners IN ('Data Governance', 'Data Governance, airflow', 'airflow, Data Governance') THEN 'Data Governance'
        WHEN d.owners IN ('Data Fintech', 'Data Fintech, airflow', 'airflow, Data Fintech') THEN 'Fintech Platform'
        WHEN d.owners IN ('Data Growth', 'Data Growth, airflow', 'airflow, Data Growth') THEN 'Growth'
        WHEN d.owners IN ('Data Primitives') THEN 'Primitives'
        WHEN d.owners IN ('Data ForSale','Data ForSale, airflow','airflow, Data ForSale') THEN 'For Sale'
        WHEN d.owners IN ('Data People', 'airflow, Data People', 'Data People, airflow') THEN 'People'
        WHEN d.owners IN ('MLOps', 'MLOps Team') THEN 'MLOps'
        ELSE d.owners
      END AS owner_adjusted
  FROM
      datalake_astro_clean.dag AS d
  WHERE
    year = 2025
    AND month = 5
    AND day = 20
), table_info as (
    SELECT
      t.table AS table_name,
      t.dag,
      t.layer,
      d.owner_adjusted
  FROM
      datalake_dag_inventory_clean.`table` AS t
  JOIN
      dag_info AS d
          on t.dag = d.id_dag
  WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND t.layer IN ('clean','enrich','dw')
), joined_data as (
  SELECT
    sc.id_entity,
    ti.owner_adjusted AS domain,
    smp.sample,
    sc.sample_summary,
    sc.col_summary,
    aggregate(
      sample_summary,
      CAST(NULL AS STRUCT<type: STRING, count: LONG>),
      (acc, x) -> CASE
                    WHEN acc IS NULL OR x.count > acc.count THEN x
                    ELSE acc
                  END
    ).type AS highest_occur_sample,
    aggregate(
      col_summary,
      CAST(NULL AS STRUCT<type: STRING, count: LONG>),
      (acc, x) -> CASE
                    WHEN acc IS NULL OR x.count > acc.count THEN x
                    ELSE acc
                  END
    ).type AS highest_occur_col,
    sc.year,
    sc.month,
    sc.day
  FROM
    datalake_anonymization.pii_scan_results as sc
      LEFT JOIN datalake_anonymization.columns_sample_data as smp
        ON sc.id_entity = smp.id_entity
      LEFT JOIN datalake_anonymization_validation.manual_validation as mv
        ON sc.id_entity = mv.id_entity
      LEFT JOIN
        table_info AS ti
        ON ti.table_name = CONCAT(sc.database_name, ".", sc.table_name)
  WHERE
    sc.year = {year}
    AND sc.month = {month}
    AND sc.day = {day}
    AND mv.id_entity IS NULL
),
ae_managers AS (
    SELECT
        oc.work_email,
        oc.line
    FROM
        datalake_people_public.org_chart AS oc
    WHERE
        assignment_status_type = 'ACTIVE'
        AND assignment_name LIKE '%GERENTE DE ENGENHARIA DE DADOS%'
)
SELECT
    id_entity,
    domain,
    aem.work_email AS email,
    CASE WHEN
        LENGTH(TO_JSON(sample)) > 1000 THEN ARRAY('SAMPLE_TOO_LARGE')
        ELSE sample
    END AS sample,
    TO_JSON(sample_summary) AS sample_summary,
    TO_JSON(col_summary) as col_summary,
    CASE
        WHEN highest_occur_sample = highest_occur_col THEN highest_occur_col
        WHEN highest_occur_sample != highest_occur_col AND highest_occur_col = "NOT_FOUND" THEN highest_occur_sample
        WHEN highest_occur_sample != highest_occur_col AND highest_occur_sample = "NOT_FOUND" THEN highest_occur_col
        WHEN highest_occur_sample != highest_occur_col AND highest_occur_sample != "NOT_FOUND" AND highest_occur_col != "NOT_FOUND" THEN highest_occur_sample
        ELSE "NOT_FOUND"
    END AS initial_eval,
    jd.year,
    jd.month,
    jd.day
FROM
    joined_data AS jd
LEFT JOIN
    ae_managers AS aem
        ON jd.domain = aem.line
