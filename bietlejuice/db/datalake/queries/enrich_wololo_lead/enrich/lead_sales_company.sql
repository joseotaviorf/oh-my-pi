WITH lead_revision as (
    SELECT
        id_reference AS id_lead,
        id_dimension_entity,
        sales_company,
        ts_rev AS ts_revision,
        info.rev,
        MIN(ts_rev) OVER (PARTITION BY id_reference) AS ts_inserted,
        (
            lag (sales_company) OVER (PARTITION BY id_reference ORDER BY ts_rev ASC)
            <> sales_company
        ) AS flag_change_sales_company
    FROM datalake_wololo_clean.prospect_aud p
      JOIN datalake_wololo_clean.prospect_dimension_aud pd_aud
          ON p.id_dimension_entity =  pd_aud.id
      JOIN datalake_wololo_clean.rev_info info
         ON pd_aud.rev = info.rev
),
last_change_company AS (
    SELECT
        id_lead,
        MAX(
            CASE
                WHEN flag_change_sales_company = TRUE
                    THEN ts_revision
            ELSE ts_inserted END
        ) AS ts_last_changed_company
    FROM lead_revision
    GROUP BY 1
),
distinct_lead AS (
    SELECT
        lr.id_lead,
        sales_company,
        ts_last_changed_company AS ts_sales_company_sent,
        ROW_NUMBER() OVER (PARTITION BY lr.id_lead ORDER BY lr.rev DESC) AS rn_lead
    FROM lead_revision lr
        JOIN last_change_company lcc
            ON lr.id_lead = lcc.id_lead
            AND lcc.ts_last_changed_company = lr.ts_revision
)
SELECT
    id_lead,
    sales_company,
    ts_sales_company_sent
FROM distinct_lead
WHERE rn_lead = 1
