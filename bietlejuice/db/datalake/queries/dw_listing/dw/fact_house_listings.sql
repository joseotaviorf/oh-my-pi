WITH house_listing_contracts AS (
    WITH latest_contract AS (
        SELECT
            hl.id_house_listing,
            MAX(c.id) AS id_contract,
            DENSE_RANK() OVER (PARTITION BY hl.id_house ORDER BY hl.id_house_listing) AS order_renting
        FROM datalake_ebdb_listing.house_listing hl
        JOIN datalake_ebdb_clean.contract c
        ON hl.id_house = c.id_house
            and c.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '2000-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, current_date)
              AND c.status in ('Ativo', 'Finalizado')
        GROUP BY hl.id_house_listing, hl.id_house
    )
    SELECT
        hl.id_house_listing,
        hl.version AS house_version,
        c.id AS id_contract,
        c.ts_signed AS ts_contract_signed,
        c.dt_termination AS dt_contract_annulment,
        LAG(c.id, 1) OVER (PARTITION BY hl.id_house ORDER BY hl.version) AS id_prev_contract,
        LEAD(c.ts_signed, 1) OVER (PARTITION BY hl.id_house ORDER BY hl.version) AS ts_next_contract_signed,
        COUNT(c.id) OVER (PARTITION BY c.id_house) AS nr_renting,
        lc.order_renting
    FROM datalake_ebdb_listing.house_listing hl
    LEFT JOIN latest_contract lc
        ON hl.id_house_listing = lc.id_house_listing
    LEFT JOIN datalake_ebdb_clean.contract c
        ON c.id = lc.id_contract
),
lbc AS (
    SELECT
        id_house,
	    CAST(MAX(CAST((business_context = 'SALE') AS INTEGER)) AS BOOLEAN) AS is_for_sale,
        CAST(MAX(CAST((business_context = 'RENT') AS INTEGER)) AS BOOLEAN) AS is_for_rent
    FROM
       datalake_ebdb_listing.listing_business_context
    GROUP BY 1
),
autonomous_agent_info AS (
    SELECT DISTINCT
        h.id AS id_house,
        pa.id_user AS sk_autonomous_agent
    FROM datalake_ebdb_clean.partner_agent pa
    JOIN datalake_ebdb_clean.partner dp
        ON pa.id_partner = dp.id
    JOIN datalake_ebdb_clean.house h
        ON pa.id_user = h.id_user_registrant
    LEFT JOIN datalake_ebdb_listing.listing_business_context lbc ON
        lbc.id_house = h.id
    WHERE
        lbc.business_context <> 'SALE'
        AND dp.type = 'AUTONOMOUS_AGENT'
        AND dp.id <> '257' -- Test User
        AND h.dt_creation >= pa.ts_created --This rule might change when we start to considering migration
        AND h.id_external IS NOT NULL --This rule might change when we start to considering migration
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  hl.id_house_listing AS sk_house_listing,
  COALESCE(NULLIF(NULLIF(h.id_user, pa_b2b_online.id_user), pa_b2b_prime.id_user), -1) AS sk_owner,
  COALESCE(h.id_region, -1) AS sk_region,
  COALESCE(h.id_user_registrant, -1) AS sk_user_registration,
  COALESCE(hlc.id_contract, -1) AS sk_contract,
  COALESCE(cd.id, -1) AS sk_condo,
  COALESCE(pa_b2b_online.id_user, pa_b2b_prime.id_user, -1) AS sk_user_partner_agent,
  COALESCE(pa_b2b_online.id_partner, pa_b2b_prime.id_partner, -1) AS sk_partner,
  COALESCE(aa_info.sk_autonomous_agent, -1) AS sk_autonomous_agent,
  COALESCE(CAST(DATE_FORMAT(hl.dt_stranded, 'yyyyMMdd') AS BIGINT), -1) AS sk_stranded_date,
  -- SparkSQL's datediff ignores the time part, so we get the seconds diff and convert it to integer days.
  -- 60s*60m*24h = 86400s
  CAST((CAST(CAST(hlc.ts_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(hl.ts_listing_version_start AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_listing_to_contract_signed,
  CAST((CAST(CAST(hl.ts_last_unpublished AS TIMESTAMP) AS LONG) - CAST(CAST(hl.ts_listing_version_start AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_listing_to_depublication,
  CAST((CAST(CAST(hl.ts_listing_version_end AS TIMESTAMP) AS LONG) - CAST(CAST(hlc.dt_contract_annulment AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_ended_rental_to_relisting,
  CAST((CAST(CAST(hlc.ts_next_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(hl.ts_listing_version_end AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_relisting_to_re_rental,
  CAST((CAST(CAST(hlc.ts_next_contract_signed AS TIMESTAMP) AS LONG) - CAST(CAST(hlc.dt_contract_annulment AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_ended_rental_to_re_rented,
  CAST(COALESCE(hlc.nr_renting, 0) AS SMALLINT) AS nr_renting,
  CAST(COALESCE(hlc.order_renting, 0) AS SMALLINT) AS order_renting,
  NOW() AS ts_load
FROM datalake_ebdb_listing.house h
LEFT JOIN lbc
  ON lbc.id_house = h.id
JOIN datalake_ebdb_listing.house_listing hl
  ON hl.id_house = h.id
LEFT JOIN house_listing_contracts hlc
  ON hl.id_house_listing = hlc.id_house_listing
LEFT JOIN datalake_ebdb_clean.condo cd
  ON h.id_condo_parent = cd.id
LEFT JOIN datalake_ebdb_clean.partner_agent pa_b2b_prime
  ON h.id_user = pa_b2b_prime.id_user
LEFT JOIN datalake_lead.conversion_lead lc
  ON lc.id_house = h.id
LEFT JOIN datalake_lead.lead l
  ON l.id = lc.id_converted_lead
    AND l.affiliate_type = 'B2BPartner'
LEFT JOIN datalake_ebdb_clean.partner_agent pa_b2b_online
  ON pa_b2b_online.id_user = l.id_user_has_indicated
LEFT JOIN autonomous_agent_info aa_info
  ON aa_info.id_house = h.id
WHERE
  lbc.id_house IS NULL
  OR lbc.is_for_rent