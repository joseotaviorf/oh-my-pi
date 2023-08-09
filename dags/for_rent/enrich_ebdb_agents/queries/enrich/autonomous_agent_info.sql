SELECT
    h.id AS id_house,
    hl.id_house_listing,
    partner_agent.id_user AS id_partner_agent,
    partner_agent.id_partner AS id_partner
FROM 
    datalake_ebdb_clean.partner_agent AS partner_agent
JOIN 
    datalake_ebdb_clean.partner AS partner
        ON partner_agent.id_partner = partner.id
JOIN 
    datalake_ebdb_clean.house AS h
        ON partner_agent.id_user = h.id_user_registrant
LEFT JOIN 
    datalake_ebdb_listing.house_listing AS hl
        ON h.id = hl.id_house
LEFT JOIN 
    datalake_ebdb_listing.listing_business_context AS lbc
        ON lbc.id_house = h.id
WHERE
    lbc.business_context <> 'SALE'
    AND partner.type = 'AUTONOMOUS_AGENT'
    AND partner.id <> '257' -- Test User
    AND h.dt_creation >= partner_agent.ts_created --This rule might change WHEN we start to consider migration
    AND h.id_external IS NOT NULL --This rule might change WHEN we start to consider migration