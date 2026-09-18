SELECT
  t.id_termination AS sk_termination,
  t.id_house_listing AS sk_house_listing,
  COALESCE(hl.id_next_house_listing_consolidated, -1) AS sk_next_house_listing_consolidated,
  t.id_contract AS sk_contract,
  COALESCE(hl.id_next_contract, -1) AS sk_next_contract,
  t.id_region AS sk_region,
  BIGINT(DATE_FORMAT(t.ts_termination_request, 'yyyyMMdd')) AS sk_termination_request_date,
  BIGINT(DATE_FORMAT(t.dt_termination, 'yyyyMMdd')) AS sk_termination_date,
  COALESCE(BIGINT(DATE_FORMAT(next_hl.ts_publicated, 'yyyyMMdd')), -1) AS sk_next_house_listing_publication_date,
  COALESCE(BIGINT(DATE_FORMAT(c.dt_started, 'yyyyMMdd')), -1) AS sk_contract_start_date,
  COALESCE(BIGINT(DATE_FORMAT(c.dt_ended_rental_confirmed, 'yyyyMMdd')), -1) AS sk_ended_rental_confirmed_date,
  COALESCE(BIGINT(DATE_FORMAT(next_c.ts_signed, 'yyyyMMdd')), -1) AS sk_next_contract_signature_date,
  COALESCE(BIGINT(DATE_FORMAT(t.ts_declined, 'yyyyMMdd')), -1) AS sk_declined_date,
  t.is_relisting_enabled,
  t.is_early_relisting_enabled,
  DATEDIFF(c.dt_ended_rental_confirmed, t.ts_termination_request) AS days_termination_request_to_ended_rental_confirmed,
  DATEDIFF(next_hl.ts_publicated, t.ts_termination_request) AS days_termination_request_to_publication,
  DATEDIFF(t.ts_declined, t.ts_termination_request) AS days_termination_request_to_relisting_declined,
  DATEDIFF(next_hl.ts_publicated, t.dt_termination) AS days_termination_to_publication,
  DATEDIFF(next_c.ts_signed, t.dt_termination) AS days_termination_to_contract_signed,
  NOW() AS ts_load,
  t.year,
  t.month,
  t.day
FROM
  transformation_terminator_test_curated.termination AS t
LEFT JOIN
  datalake_ebdb_listing.house_listing AS hl
    ON t.id_house_listing = hl.id_house_listing
LEFT JOIN
  datalake_ebdb_contract.contract AS c
    ON t.id_contract = c.id
LEFT JOIN
  datalake_ebdb_contract.contract AS next_c
    ON hl.id_next_contract = next_c.id
LEFT JOIN
  datalake_ebdb_listing.house_listing AS next_hl
    ON hl.id_next_house_listing_consolidated = next_hl.id_house_listing
