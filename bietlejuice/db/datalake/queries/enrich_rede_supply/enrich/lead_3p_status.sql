WITH starting_value AS (
    SELECT
        COALESCE(MAX(sk_lead_3p_status), 0) AS max_sk_lead_3p_status
    FROM
        datalake_rede_supply.lead_3p_status
),
possible_status AS (
    SELECT DISTINCT
        status,
        growth_status,
        is_waiting_for_enrichment,
        is_ineligible,
        is_discarded
    FROM
        datalake_rede_supply.lead_3p_status_changes
)
SELECT
    COALESCE(
        ls.sk_lead_3p_status, -- Keep the sk if it is already defined, so it is durable
        sv.max_sk_lead_3p_status + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_lead_3p_status,
    ps.status,
    ps.growth_status,
    ps.is_waiting_for_enrichment,
    ps.is_ineligible,
    ps.is_discarded
FROM
    possible_status AS ps,
    starting_value AS sv
LEFT JOIN 
    datalake_rede_supply.lead_3p_status AS ls
        ON ls.status = ps.status
        AND ls.growth_status = ps.growth_status
        AND ls.is_waiting_for_enrichment = ps.is_waiting_for_enrichment
        AND ls.is_ineligible = ps.is_ineligible
        AND ls.is_discarded = ps.is_discarded
