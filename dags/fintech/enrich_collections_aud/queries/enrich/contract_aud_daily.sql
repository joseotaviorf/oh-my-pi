WITH
contract_range AS (
    SELECT
        id_contract,
        DATE(MIN(ts_database_transaction)) AS dt_first_transaction,
        DATE(COALESCE(
                MAX(CASE WHEN dt_annulment IS NOT NULL THEN ts_database_transaction END),
                CURRENT_DATE
        )) AS dt_last_transaction
    FROM datalake_collections_aud.contract_aud
    GROUP BY 1
),
daily_changes AS (
    SELECT
        id_contract,
        country_code,
        city,
        guarantee,
        status,
        dt_termination_original,
        dt_annulment,
        dt_started,
        ts_signature,
        ts_analyst_annulment_input,
        ts_database_transaction,
        ts_cdc_transaction,
        year,
        month,
        day,
        DATE(ts_database_transaction) AS dt_reference
    FROM datalake_collections_aud.contract_aud
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, DATE(ts_database_transaction) ORDER BY ts_database_transaction DESC) = 1
),
get_next_day AS (
    SELECT *,
        COALESCE(
        LEAD(dt_reference) OVER(PARTITION BY id_contract ORDER BY dt_reference),
        CURRENT_DATE + INTERVAL 1 DAY) AS dt_next_day
    FROM daily_changes
),
contract_days AS (
    SELECT
        id_contract,
        dt_reference
    FROM contract_range
    LATERAL VIEW EXPLODE(
        SEQUENCE(dt_first_transaction,
                dt_last_transaction,
                INTERVAL 1 DAY
            )) AS dt_reference
)
SELECT
    dc.id_contract,
    dc.country_code,
    dc.city,
    dc.guarantee,
    dc.status,
    dc.dt_termination_original,
    dc.dt_annulment,
    dc.dt_started,
    dc.ts_signature,
    dc.ts_analyst_annulment_input,
    cd.dt_reference,
    dc.ts_database_transaction,
    dc.ts_cdc_transaction,
    YEAR(cd.dt_reference) AS year,
    MONTH(cd.dt_reference) AS month,
    DAY(cd.dt_reference) AS day,
    NOW() AS ts_load
FROM contract_days AS cd
INNER JOIN get_next_day AS dc
         ON dc.id_contract = cd.id_contract
         AND cd.dt_reference >= dc.dt_reference
         AND cd.dt_reference < dc.dt_next_day
