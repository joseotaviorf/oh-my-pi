WITH company_memberships AS (
  SELECT
    mu.id_hubspot AS id_company,
    'SALE' AS business_context,
    LAG(mu.ts_start) OVER (PARTITION BY mu.id_hubspot ORDER BY mu.ts_start) IS NULL AS is_first_membership,
    mu.ts_start AS ts_membership_started,
    LEAD(mu.ts_start) OVER (PARTITION BY mu.id_hubspot ORDER BY mu.ts_start) AS ts_next_membership_started
  FROM
    datalake_hubspot.membership_updates AS mu
  WHERE
    mu.hubspot_status = 'Membro'
),
lead_publications AS (
    SELECT
        id_lead_3p,
        id_company_hubspot,
        business_context,
        MIN(ts_status_started) AS ts_first_listing
    FROM
        datalake_rede_supply.lead_3p_status_changes
    WHERE
        growth_status = 'FIRST_LISTING'
    GROUP BY 1, 2, 3
),
first_leads AS (
    SELECT
        lsc.id_company_hubspot,
        lsc.business_context,
        MIN(lsc.ts_status_started) AS ts_first_lead
    FROM
        datalake_rede_supply.lead_3p_status_changes AS lsc
    GROUP BY 1, 2
)
SELECT
    lp.id_lead_3p,
    lp.business_context,
    -- Farming is when the lead was published in the first 30 days after the last membership start
    -- If the membership has not started yet, we consider the date of the first lead sent
    -- Otherwise, it is hunting
    CASE
        WHEN (cm.ts_membership_started IS NULL OR cm.is_first_membership)
            AND DATEDIFF(lp.ts_first_listing, LEAST(fle.ts_first_lead, cm.ts_membership_started)) > 30
                THEN 'FARMING'
        WHEN DATEDIFF(lp.ts_first_listing, cm.ts_membership_started) > 30
            THEN 'FARMING'
        ELSE 'HUNTING'
    END AS acquisition_team
FROM
    lead_publications AS lp
LEFT JOIN
    company_memberships AS cm
        ON lp.id_company_hubspot = cm.id_company
        AND lp.business_context = cm.business_context
        AND lp.ts_first_listing BETWEEN cm.ts_membership_started AND COALESCE(cm.ts_next_membership_started, NOW())
LEFT JOIN
    first_leads AS fle
        ON lp.id_company_hubspot = fle.id_company_hubspot
        AND lp.business_context = fle.business_context