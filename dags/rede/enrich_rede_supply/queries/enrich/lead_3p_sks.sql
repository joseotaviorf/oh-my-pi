WITH starting_value AS (
    SELECT
        COALESCE(MAX(sk_lead_3p), 0) AS max_sk_lead_3p
    FROM
        datalake_rede_supply.lead_3p_sks
)
SELECT
    COALESCE(
        sk_lead_3p, -- Keep the sk_file if it is already defined, so it is durable
        sv.max_sk_lead_3p + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_lead_3p,
    l.id AS id_lead_3p -- Natural key
FROM
    datalake_brokers_supply_processor.lead_3p AS l,
    starting_value AS sv
LEFT JOIN 
    datalake_rede_supply.lead_3p_sks AS ls
        ON l.id = ls.id_lead_3p