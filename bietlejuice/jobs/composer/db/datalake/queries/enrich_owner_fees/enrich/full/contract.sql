WITH contract AS (
    SELECT 
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS contract_row_number
    FROM 
        datalake_owner_fees_clean.contract 
)
SELECT
    id, 
    id_house, 
    id_external, 
    id_admin_fee_option,
    real_state_agent_share, 
    rent,
    dt_validity, 
    ts_created,
    ts_updated
FROM
    contract 
WHERE 
    contract_row_number = 1