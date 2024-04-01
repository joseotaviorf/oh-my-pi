SELECT
    rm.id_lead,
    CASE
        WHEN REGEXP_LIKE(LOWER(table_name), 'lcr') THEN 'cross_listing_rent'
        WHEN REGEXP_LIKE(LOWER(table_name), 'lcs') THEN 'cross_listing_sale'
        WHEN REGEXP_LIKE(LOWER(table_name), 'repro') THEN 'manual_reprocessed'
        ELSE 'other'
    END AS type,
    EXPLODE (CASE
        WHEN REGEXP_LIKE(LOWER(table_name), 'lcr') THEN ARRAY('RENT')
        WHEN REGEXP_LIKE(LOWER(table_name), 'lcs') THEN ARRAY('SALE')
        WHEN REGEXP_LIKE(LOWER(table_name), 'repro') THEN ARRAY('RENT', 'SALE')
        ELSE ARRAY('RENT', 'SALE')
    END) AS business_context,
    rm.id_campaign,
    SF_NORMALIZE_STRING(rm.table_name) AS table_name,
    SF_NORMALIZE_STRING(c.description) AS description,
    CASE 
        -- These campaigns were deactivated a long time ago and deleted from the team interface
        -- It's not possible to change the data from original database
        WHEN c.id_campaign IN (34, 20, 76, 34) THEN "quintoandar" 
        ELSE LOWER(REPLACE(SPLIT(c.description, "_")[0], "5ANDAR", "QUINTOANDAR"))
    END AS ops_partner, 
    "is_outbound" AS ops_agent, 
    "conversion" AS ops_objective,
    "active" AS ops_approach,
    "phone_call" AS ops_contact_medium,
    "olos" AS application,
    TIMESTAMP(COALESCE(rm.ts_created,CONCAT_WS('-', rm.year, rm.month, rm.day))) AS ts_created,
    NOW() AS ts_load,
    rm.year,
    rm.month,
    rm.day
FROM
    datalake_olos_dialer_clean.reprocessing_mailing AS rm 
LEFT JOIN 
    datalake_olos_dialer_clean.campaign AS c
        ON rm.id_campaign = c.id_campaign
WHERE rm.id_lead IS NOT NULL
    AND DATE(COALESCE(rm.ts_created,CONCAT_WS('-', rm.year, rm.month, rm.day))) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')