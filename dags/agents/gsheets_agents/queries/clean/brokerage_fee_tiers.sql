-- The source spreadsheet is generated with data from the datalake, 
-- therefore, it should not be used as a dependency for other tables
SELECT
    CAST(sk_user AS BIGINT) AS id_user,
    CAST(sk_agent AS BIGINT) AS id_agent,
    kind,
    tier,
    CAST(REPLACE(comission_percentage, ',', '.') AS FLOAT) AS comission_percentage,
    CAST(REPLACE(additional_comission_percentage, ',', '.') AS FLOAT) AS additional_comission_percentage,
    TO_DATE(dt_tier_start, 'dd/MM/yyyy') AS dt_tier_started,
    TO_DATE(dt_tier_end, 'dd/MM/yyyy') AS dt_tier_ended
FROM
    datalake_gsheets_raw.brokerage_fee_tiers