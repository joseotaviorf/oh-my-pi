WITH b2b_house_contracts AS (
  /* * This CTE checks reflects the currently house status (B2B or not), but not necessarily the contract status.
  As a reminder, a house can belong to different existing contracts, and during this flows, the house may has changed it status from B2B or not. * */
  SELECT
    c.id AS id_contract,
    COALESCE((
      COALESCE(lead_origin.affiliate_type, l.affiliate_type) = 'B2BPartner'
    ), FALSE) AS is_from_b2b_partner,
    (
      NOT partner_agent.id IS NULL AND partner.type = 'PRIME'
    ) AS is_prime
  FROM datalake_ebdb_clean.contract AS c
  JOIN datalake_ebdb_clean.house AS h
    ON c.id_house = h.id
  LEFT JOIN datalake_ebdb_clean.conversion_lead AS cl
    ON cl.id_house = h.id
  LEFT JOIN datalake_ebdb_clean.lead AS l
    ON l.id = cl.id_converted_lead
  LEFT JOIN datalake_lead.reprocessed_lead AS rl
    ON rl.id = l.id
  LEFT JOIN datalake_ebdb_clean.lead AS lead_origin
    ON lead_origin.id = rl.id_origin_lead
  LEFT JOIN datalake_ebdb_clean.partner_agent AS partner_agent
    ON partner_agent.id_user = h.id_user
  LEFT JOIN datalake_ebdb_clean.partner AS partner
    ON partner.id = partner_agent.id_partner
),
contracts_partner_quantity AS (
  SELECT
    id_contract,
    COUNT(DISTINCT uuid_person) AS partner_quantity,
    MAX(IF(revenue_share_type = 'EXECUTIVE_FOR_RENT', TRUE, FALSE)) AS is_executive_partner
  FROM
    datalake_big_agent.earnings_unified
  WHERE
    is_calculated
    AND incentive_system = 'SUPPLY_ACQUISITION_FR'
    AND business_model = '1P'
  GROUP BY
    id_contract
),
contracts_partner_selection AS (
  SELECT
    cpd.id_contract,
    CASE
      WHEN revenue_share_type IS NULL THEN 'AUTONOMOUS_AGENT'
      ELSE revenue_share_type
    END AS partner_type,
    CASE
      WHEN cpd.revenue_share_type IS NULL OR cpd.revenue_share_type = 'EXECUTIVE_FOR_RENT' THEN 'REGULAR'
      WHEN cpd.revenue_share_type = 'PRIME' THEN 'PRIME'
      ELSE 'OTHER'
    END AS contract_plan,
    cpd.administration_percentage AS administration_split_percentage,
    cpd.revenue_percentage AS brokerage_split_percentage,
    IF(partner_type = 'PRIME', TRUE, FALSE) AS is_contract_b2b,
    pq.partner_quantity,
    pq.is_executive_partner,
    IF(partner_type = 'EXECUTIVE_FOR_RENT', 2, 1) AS partner_weight
  FROM datalake_big_agent.earnings_unified AS cpd
  JOIN contracts_partner_quantity AS pq
    ON pq.id_contract = cpd.id_contract
  LEFT JOIN datalake_ebdb_clean.contract AS c
    ON c.id = cpd.id_contract
  WHERE
    cpd.is_calculated
    AND cpd.incentive_system = 'SUPPLY_ACQUISITION_FR'
    AND cpd.business_model = '1P'
),
b2b_contracts AS (
  /* * This CTE checks if a contract exists in contract_partnership_data table. If so, there is a Partner involved and we may be talking about a B2B contract, depending on
  the Partner type. This logic can cover cases where there have been house plan updates (from B2B to not, vice-versa) or user exchanges for a house, where it may led to change
  the contract type when looking to the b2b_house_contracts information. * */
  SELECT
    id_contract,
    partner_type,
    contract_plan,
    administration_split_percentage,
    brokerage_split_percentage,
    is_contract_b2b,
    partner_quantity,
    is_executive_partner,
    row_num
  FROM (
    /* * This CTE checks if a contract exists in contract_partnership_data table. If so, there is a Partner involved and we may be talking about a B2B contract, depending on
  the Partner type. This logic can cover cases where there have been house plan updates (from B2B to not, vice-versa) or user exchanges for a house, where it may led to change
  the contract type when looking to the b2b_house_contracts information. * */
    SELECT
      id_contract,
      partner_type,
      contract_plan,
      administration_split_percentage,
      brokerage_split_percentage,
      is_contract_b2b,
      partner_quantity,
      is_executive_partner,
      ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY partner_weight ASC) AS row_num
    FROM contracts_partner_selection
  ) AS _t
  WHERE
    row_num = 1
), lbc_first_publication AS (
  SELECT
    id_house,
    ts_first_publication
  FROM (
    SELECT
      h.id AS id_house,
      COALESCE(
        IF(lbc.business_context = 'RENT', lbc.ts_first_publication, NULL),
        h.dt_first_publication
      ) AS ts_first_publication,
      ROW_NUMBER() OVER (PARTITION BY h.id ORDER BY IF(lbc.business_context = 'RENT', 1, 2)) AS _w,
      h.id,
      lbc.business_context
    FROM datalake_ebdb_clean.house AS h
    LEFT JOIN datalake_ebdb_clean.listing_business_context AS lbc
      ON lbc.id_house = h.id
  ) AS _t
  WHERE
    _w = 1
), b2b_info AS (
  SELECT DISTINCT
    c.id AS id_contract,
    ch.country_code,
    CASE
      WHEN b2b_h_c.is_from_b2b_partner
      THEN 'online'
      WHEN b2b_h_c.is_prime
      THEN 'prime'
    END AS b2b_type,
    b2b_c.partner_type AS contract_partner_type,
    b2b_c.contract_plan,
    b2b_c.administration_split_percentage,
    b2b_c.brokerage_split_percentage,
    CASE
      WHEN NOT partner_agent.id /* because a lead can have both 'affiliate_type' = 'B2BPartner' and 'partner_agent.id' not null and we need to */ /* prioritize the first type (online), the following check must be done */ IS NULL
      AND partner.type = 'PRIME'
      AND NOT b2b_h_c.is_from_b2b_partner
      THEN CASE
        WHEN pj.id IS NULL AND NOT lbc.ts_first_publication IS NULL
        THEN 'advanced_negotiation'
        WHEN h.id_external IS NULL
        OR h.id_external RLIKE '^([a-zA-Z0-9]+-){{4}}[a-zA-Z0-9]+$'
        THEN 'standard'
        WHEN NOT h.id_external IS NULL
        THEN 'batch'
      END
    END AS b2b_prime_type,
    COALESCE(b2b_c.partner_quantity, 0) AS partner_quantity,
    COALESCE(b2b_c.is_executive_partner, FALSE) AS is_executive_partner,
    COALESCE(b2b_h_c.is_from_b2b_partner OR b2b_h_c.is_prime, FALSE) AS is_b2b,
    COALESCE(b2b_c.is_contract_b2b, FALSE) AS is_contract_b2b
  FROM datalake_ebdb_clean.contract AS c
  JOIN datalake_ebdb_clean.house AS h
    ON c.id_house = h.id
  JOIN datalake_ebdb_country.house AS ch
    ON ch.id_house = c.id_house
  LEFT JOIN lbc_first_publication AS lbc
    ON lbc.id_house = h.id
  LEFT JOIN b2b_house_contracts AS b2b_h_c
    ON b2b_h_c.id_contract = c.id
  LEFT JOIN b2b_contracts AS b2b_c
    ON b2b_c.id_contract = c.id
  LEFT JOIN datalake_ebdb_clean.partner_agent AS partner_agent
    ON partner_agent.id_user = h.id_user
  LEFT JOIN datalake_ebdb_clean.partner AS partner
    ON partner.id = partner_agent.id_partner
  LEFT JOIN datalake_ebdb_listing.house_listing AS hl
    ON h.id = hl.id_house
    AND c.ts_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
  LEFT JOIN datalake_ebdb_clean.photographer_job AS pj
    ON pj.id_house = h.id
    AND pj.ts_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
)
SELECT
  id_contract,
  country_code,
  contract_plan,
  contract_partner_type,
  administration_split_percentage,
  brokerage_split_percentage,
  b2b_type,
  b2b_prime_type,
  partner_quantity,
  is_executive_partner,
  is_b2b,
  is_contract_b2b
FROM b2b_info
