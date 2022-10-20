WITH starting_value AS (
    SELECT
        COALESCE(MAX(sk_lead_3p_reason), 0) AS max_sk_lead_3p_reason
    FROM
        datalake_rede_supply.lead_3p_reasons
),
possible_reason AS (
    SELECT DISTINCT
        reason,
        reason_type,
        is_ineligible_reason,
        is_discard_reason,
        is_enrichment_reason
    FROM
        datalake_rede_supply.lead_3p_reason_changes
)
SELECT
    COALESCE(
        ls.sk_lead_3p_reason, -- Keep the sk if it is already defined, so it is durable
        sv.max_sk_lead_3p_reason + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_lead_3p_reason,
    pr.reason,
    pr.reason_type,
    pr.is_ineligible_reason,
    pr.is_discard_reason,
    pr.is_enrichment_reason
FROM
    possible_reason AS pr,
    starting_value AS sv
LEFT JOIN 
    datalake_rede_supply.lead_3p_reasons AS ls
        ON ls.reason = pr.reason
        AND ls.reason_type = pr.reason_type
