WITH 1p_tb AS (
    SELECT 
        id AS id_lead,
        '1P' AS source,
        CURRENT_TIMESTAMP AS ts_created,
        FALSE AS is_backfill
    FROM 
        datalake_rene_descartes_clean.house_lead
    WHERE 
        DATE(ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY ALL
),
3p_tb AS (
    SELECT
        id AS id_lead,
        '3P' AS source,
        CURRENT_TIMESTAMP AS ts_created,
        FALSE AS is_backfill
    FROM
        datalake_brokers_supply_processor_clean.lead_3p
    WHERE 
        DATE(ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY ALL
),
draft_with_rene_informations AS (
    SELECT
    hd.id AS id_draft,
    s.id_external AS id_house,
    hlc.id_lead AS id_lead_ebdb,
    hl.id AS id_lead_rene
    FROM
        datalake_bob_clean.house_draft AS hd
    LEFT JOIN datalake_bob_clean.submission_progress AS s 
        ON hd.id = s.id_house_draft
    LEFT JOIN datalake_rene_descartes_clean.house_lead_conversion AS hlc 
        ON s.id_external = hlc.id_house
    LEFT JOIN datalake_rene_descartes_clean.house_lead AS hl 
        ON hlc.id_lead = hl.id_lead_ebdb
    WHERE
        hd.type IN ('ADMIN_CONFIRMATION', 'PORTFOLIO_MANAGER')
        AND hl.id IS NOT NULL
),
ciq_tb AS (
    SELECT 
        hd.id AS id_lead,
        'CIQ' AS source,
        CURRENT_TIMESTAMP AS ts_created,
        FALSE AS is_backfill
    FROM 
        datalake_bob_clean.house_draft AS hd
    WHERE
        (hd.id NOT IN (SELECT DISTINCT id_draft FROM draft_with_rene_informations))
        AND (hd.type IN ('ADMIN_CONFIRMATION', 'PORTFOLIO_MANAGER'))
        AND (DATE(ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}'))
    GROUP BY ALL
)

SELECT *
FROM 1p_tb
UNION ALL
SELECT *
FROM 3p_tb
UNION ALL
SELECT *
FROM ciq_tb