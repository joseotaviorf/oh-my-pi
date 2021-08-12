WITH b2b_contracts AS (
    SELECT
        c.id AS id_contract,
        IFNULL((COALESCE(lead_origin.affiliate_type, l.affiliate_type) = 'B2BPartner'), FALSE) AS is_from_b2b_partner,
        (partner_agent.id IS NOT NULL AND partner.type = 'PRIME') AS is_prime
    FROM datalake_ebdb_clean.contract c
    JOIN datalake_ebdb_clean.house h
        ON c.id_house = h.id
    LEFT JOIN datalake_ebdb_clean.conversion_lead cl
        ON cl.id_house = h.id
    LEFT JOIN datalake_ebdb_clean.lead l
        ON l.id = cl.id_converted_lead
    LEFT JOIN datalake_lead.reprocessed_lead rl
        ON rl.id = l.id
    LEFT JOIN datalake_ebdb_clean.lead lead_origin
        ON lead_origin.id = rl.id_origin_lead
    LEFT JOIN datalake_ebdb_clean.partner_agent partner_agent
	    ON partner_agent.id_user = h.id_user
    LEFT JOIN datalake_ebdb_clean.partner partner
        ON partner.id = partner_agent.id_partner
),
b2b_info AS (
    SELECT DISTINCT
        c.id AS id_contract,
        COALESCE(b2b_contracts.is_from_b2b_partner OR b2b_contracts.is_prime, FALSE) AS is_b2b,
        CASE
          WHEN b2b_contracts.is_from_b2b_partner
            THEN 'online'
          WHEN b2b_contracts.is_prime
            THEN 'prime'
        END AS b2b_type,
        CASE
            WHEN
                -- because a lead can have both 'affiliate_type' = 'B2BPartner' and 'partner_agent.id' not null and we need to
                -- prioritize the first type (online), the following check must be done
                partner_agent.id IS NOT NULL
                AND partner.type = 'PRIME'
                AND NOT b2b_contracts.is_from_b2b_partner
            THEN
                CASE
                    WHEN pj.id IS NULL AND h.dt_first_publication IS NOT NULL
                      THEN 'advanced_negotiation'
                    WHEN h.id_external IS NULL OR h.id_external RLIKE '^([a-zA-Z0-9]+-){4}[a-zA-Z0-9]+$'
                      THEN 'standard'
                    WHEN h.id_external IS NOT NULL
                        THEN 'batch'
                END
        END AS b2b_prime_type
    FROM datalake_ebdb_clean.contract c
    JOIN datalake_ebdb_clean.house h
        ON c.id_house = h.id
    LEFT JOIN b2b_contracts b2b_contracts
        ON b2b_contracts.id_contract = c.id
    LEFT JOIN datalake_ebdb_clean.partner_agent partner_agent
        ON partner_agent.id_user = h.id_user
    LEFT JOIN datalake_ebdb_clean.partner partner
        ON partner.id = partner_agent.id_partner
    LEFT JOIN datalake_ebdb_listing.house_listing hl
        ON h.id = hl.id_house
        AND c.ts_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
    LEFT JOIN datalake_ebdb_clean.photographer_job pj
        ON pj.id_house = h.id
        AND pj.ts_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
)
SELECT
    id_contract,
    is_b2b,
    b2b_type,
    b2b_prime_type
FROM b2b_info
