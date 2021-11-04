with leads_b2b AS (
    SELECT DISTINCT
        lead.id AS id_lead,
        partner_agent.id_partner AS id_online_partner
    FROM datalake_lead.lead
    JOIN datalake_ebdb_clean.partner_agent
        ON partner_agent.id_user = lead.id_user_has_indicated
    WHERE partner_agent.id_partner IS NOT NULL
),
autonomous_agent_info AS (
    SELECT
        partner_agent.id_user AS id_autonomous_agent,
        partner_agent.ts_created
    FROM datalake_ebdb_clean.partner_agent
    JOIN datalake_ebdb_clean.partner
        ON partner_agent.id_partner = partner.id
        AND partner.type = 'AUTONOMOUS_AGENT'
        AND partner.id <> '257' -- Test User
)
SELECT
    listing_flow.id,
    COALESCE(h.id_condo_parent, CAST(-1 AS INTEGER)) AS id_condo,
    CAST(
        COALESCE(
            CONCAT(
                CAST(listing_flow.id_house AS STRING),
                '00',
                 CAST(COALESCE(hl_version_zero.version, 1) AS STRING)
             )
             , '-1'
        )
        AS BIGINT) AS id_house_listing,
    COALESCE(pa_b2b_prime.id_partner,
            l_b2b.id_online_partner,
            listing_flow.id_partner,
            CAST(-1 AS INTEGER)
        ) AS id_partner,
    COALESCE(aa_info.id_autonomous_agent, CAST(-1 AS INTEGER)) AS id_autonomous_agent,
    h.id_user_registrant AS id_user_registrant,
    h.is_exclusive,
    COALESCE(aa_info.id_autonomous_agent IS NOT NULL, FALSE) AS is_autonomous_agent
FROM datalake_listing_flow.listing_flows_with_reprocessed_leads AS listing_flow
LEFT JOIN datalake_ebdb_listing.house AS h
    ON listing_flow.id_house = h.id
LEFT JOIN leads_b2b AS l_b2b
    ON l_b2b.id_lead = listing_flow.id_lead
LEFT JOIN datalake_ebdb_clean.partner_agent AS pa_b2b_prime
    ON h.id_user = pa_b2b_prime.id_user
LEFT JOIN datalake_ebdb_listing.house_listing AS hl_version_zero
    ON hl_version_zero.id_house = listing_flow.id_house
    AND hl_version_zero.version = 0
LEFT JOIN autonomous_agent_info AS aa_info
    ON aa_info.id_autonomous_agent = h.id_user_registrant
    AND h.dt_creation >= aa_info.ts_created --This rule might change when we start to considering migration
    AND h.id_external IS NOT NULL --This rule might change when we start to considering migration