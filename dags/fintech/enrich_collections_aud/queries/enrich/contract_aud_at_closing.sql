WITH
contract_range AS (
    SELECT
        id_contract,
        DATE(DATE_TRUNC('MONTH', MIN(ts_database_transaction))) AS dt_first_transaction,
        DATE(DATE_TRUNC('MONTH', COALESCE(
            MAX(CASE WHEN dt_annulment IS NOT NULL THEN ts_database_transaction END),
            CURRENT_DATE
        ))) AS dt_last_transaction
    FROM datalake_collections_aud.contract_aud_daily
    GROUP BY 1
),
monthly_changes AS (
    SELECT *
    FROM datalake_collections_aud.contract_aud_daily
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, DATE_TRUNC('MONTH', ts_database_transaction) ORDER BY ts_database_transaction DESC) = 1
),
get_next_month AS (
    SELECT *,
        COALESCE(
        LEAD(DATE_TRUNC('MONTH', ts_database_transaction)) OVER(PARTITION BY id_contract ORDER BY DATE_TRUNC('MONTH', ts_database_transaction)),
        DATE_TRUNC('MONTH',CURRENT_DATE)) AS dt_next_month_start
    FROM monthly_changes
),
contract_months AS (
    SELECT
        id_contract,
        dt_month_start
    FROM contract_range
    LATERAL VIEW EXPLODE(
        SEQUENCE(dt_first_transaction,
                dt_last_transaction,
                INTERVAL 1 MONTH
            )) AS dt_month_start
)
SELECT
    nm.id_contract,
    nm.country_code,
    nm.city,
    nm.guarantee,
    nm.status,
    nm.dt_termination_original,
    nm.dt_annulment,
    nm.dt_started,
    nm.ts_signature,
    nm.ts_analyst_annulment_input,
    LAST_DAY(cm.dt_month_start) AS dt_closing,
    nm.ts_database_transaction,
    nm.ts_snapshot,
    YEAR(cm.dt_month_start) AS year,
    MONTH(cm.dt_month_start) AS month,
    DAY(LAST_DAY(cm.dt_month_start)) AS day,
    NOW() AS ts_load
FROM contract_months AS cm
INNER JOIN get_next_month AS nm
        ON nm.id_contract = cm.id_contract
        AND cm.dt_month_start >= DATE_TRUNC('MONTH', nm.ts_database_transaction)
        AND cm.dt_month_start < nm.dt_next_month_start
ORDER BY id_contract, dt_closing
