WITH house_portability AS (
    SELECT
        hl.id_house,
        hl.id_house_listing,
        hl.id_contract
    FROM
        datalake_ebdb_listing.house_listing hl
    JOIN
        datalake_ebdb_clean.portability por
            ON por.id_house = hl.id_house
            AND por.owner_type = 'B2B'
    WHERE
        por.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, NOW())
),
lbc_first_publication AS (
    SELECT
        h.id AS id_house,
        COALESCE(IF(lbc.business_context = 'RENT', lbc.ts_first_publication, NULL), h.dt_first_publication) AS ts_first_publication
    FROM
        datalake_ebdb_clean.house AS h
    LEFT JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = h.id
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY h.id ORDER BY IF(lbc.business_context = 'RENT', 1, 2)) = 1
)
SELECT DISTINCT
    h.id AS id_house,
    hl.id_house_listing,
    hl.id_contract,
    CASE
        WHEN partner_agent.status = 'INACTIVE' THEN NULL
        WHEN COALESCE(lo.affiliate_type, l.affiliate_type) = 'B2BPartner' THEN 'online'
        WHEN (partner_agent.id IS NOT NULL AND partner.type = 'PRIME') THEN 'prime'
    END AS b2b_type,
    CASE
        WHEN
            -- because a lead can have both 'affiliate_type' = 'B2BPartner' AND 'partner_agent.id' not null AND we need to
            -- prioritize the first type (online), the following check must be done
            partner_agent.id IS NOT NULL
            AND partner.type = 'PRIME'
            AND COALESCE(lo.affiliate_type, l.affiliate_type, '') != 'B2BPartner'
        THEN
            CASE
            WHEN pj.id IS NULL AND lbc.ts_first_publication IS NOT NULL THEN 'advanced_negotiation'
            WHEN h.id_external IS NULL OR h.id_external RLIKE '^([a-zA-Z0-9]+-){{4}}[a-zA-Z0-9]+$' THEN 'standard'
            WHEN h.id_external IS NOT NULL THEN 'batch'
            END
    END AS b2b_prime_type,
    IF(((
        (COALESCE(lo.affiliate_type, l.affiliate_type) = 'B2BPartner')
            OR (partner_agent.id_partner IS NOT NULL AND partner.type = 'PRIME'))
            AND partner_agent.status = 'ACTIVE'), TRUE, FALSE)
        OR por.id_house IS NOT NULL
    AS is_b2b,
    IF(por.id_house_listing IS NOT NULL, TRUE, FAlSE) AS is_portability
FROM
    datalake_ebdb_clean.house AS h
LEFT JOIN
    lbc_first_publication AS lbc
        ON lbc.id_house = h.id
LEFT JOIN
    datalake_ebdb_clean.conversion_lead AS cl
        ON cl.id_house = h.id
LEFT JOIN
    datalake_ebdb_clean.lead AS l
        ON l.id = cl.id_converted_lead
LEFT JOIN
    datalake_lead.reprocessed_lead AS rl
        ON rl.id = l.id
LEFT JOIN
    datalake_lead.lead AS lo
        ON lo.id = rl.id_origin_lead
LEFT JOIN
    datalake_ebdb_clean.partner_agent
        ON partner_agent.id_user = h.id_user
LEFT JOIN
    datalake_ebdb_clean.partner
        ON partner.id = partner_agent.id_partner
LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
        ON h.id = hl.id_house
LEFT JOIN
    datalake_ebdb_clean.photographer_job AS pj
        ON pj.id_house = h.id
        AND pj.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, NOW())
LEFT JOIN
    house_portability AS por
        ON hl.id_house_listing = por.id_house_listing
