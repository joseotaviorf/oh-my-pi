WITH table_info AS (
SELECT
    t.table AS table_name,
    t.dag,
    t.layer,
    CASE
        WHEN LOWER(d.owners) LIKE '%bedrock%' THEN 'BedRock'
        WHEN d.owners IN ('Data Fintech', 'Data Fintech, airflow', 'airflow, Data Fintech') THEN 'Fintech Platform'
        WHEN d.owners IN ('Data ForRent', 'Data ForRent, airflow', 'airflow, Data ForRent') THEN 'For Rent'
        WHEN d.owners IN ('Data ForSale', 'Data ForSale, airflow', 'airflow, Data ForSale') THEN 'For Sale'
        WHEN d.owners IN ('Data Growth', 'Data Growth, airflow', 'airflow, Data Growth') THEN 'Growth'
        WHEN d.owners IN ('Data Rede','Data Rede, airflow', 'Data Agents', 'airflow, Data Agents') THEN 'Partners'
        WHEN d.owners IN ('Data SS','Data SS, airflow') THEN 'Support & Services'
        WHEN d.owners IN ('Data International', 'airflow, Data International', 'Data International, airflow') THEN 'For Rent'
        WHEN d.owners IN ('airflow, Data People', 'Data People') THEN 'People'
        WHEN d.owners IN ('Data Governance', 'Data Governance, airflow') THEN 'Data Governance'
        WHEN d.owners IN ('Data Engineering', 'airflow, Data Engineering', 'Data Engineering, airflow') THEN 'Data Engineering'
        WHEN d.owners IN ('Data Ingestion', 'airflow, Data Ingestion') THEN 'Data Ingestion'
        ELSE d.owners
    END AS owner,
    CASE
        WHEN d.owners IN ('Data Bedrock', 'Data Bedrock, airflow', 'airflow, Data Bedrock') THEN 'BedRock'
        WHEN d.owners IN ('Data Fintech', 'Data Fintech, airflow', 'airflow, Data Fintech','Data Growth', 'Data Growth, airflow', 'airflow, Data Growth') THEN 'Fintech Platform'
        WHEN d.owners IN ('Data ForRent', 'Data ForRent, airflow', 'airflow, Data ForRent','Data International', 'airflow, Data International', 'Data International, airflow','Data SS','Data SS, airflow') THEN 'For Rent'
        WHEN d.owners IN ('Data ForSale', 'Data ForSale, airflow', 'airflow, Data ForSale', 'Data People', 'airflow, Data People', 'Data People, airflow') THEN 'For Sale'
        WHEN d.owners IN ('Data Rede','Data Rede, airflow', 'Data Agents', 'airflow, Data Agents') THEN 'Partners'
        ELSE d.owners
    END AS owner_adjusted
FROM
    datalake_dag_inventory_clean.`table` AS t
JOIN
    datalake_composer_clean.dag AS d
        on t.dag = d.id_dag
WHERE
   year = {year}
  AND month = {month}
  AND day = {day}
  AND t.layer IN ('clean','enrich','dw')
),
joined_data AS (
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
    datalake_anonymization.pii_scan_results AS sc
  LEFT JOIN
    table_info AS ti
      ON ti.table_name = CONCAT(sc.database_name, ".", sc.table_name)
  LEFT JOIN
    datalake_anonymization.columns_sample_data AS smp
      ON sc.id_entity = smp.id_entity
  WHERE
    sc.year = {year}
    AND sc.month = {month}
    AND sc.day = {day}
    AND ti.owner IS NOT NULL
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
