SELECT
  MONOTONICALLY_INCREASING_ID() AS pk_offer,
  o.id_offer AS sk_offer,
  o.id_tenant AS sk_client,
  o.id_owner AS sk_owner,
  o.id_house AS sk_house,
  hl.id_house_listing AS sk_house_listing,
  o.status,
  o.original_rent AS original_rent_value,
  o.last_proposed_rent_value,
  DATEDIFF(DAY, o.ts_last_iteration, o.ts_first_iteration) AS days_of_negotiation,
  COALESCE(o.qtd_topics_negotiated, 0) AS qtd_topics_negotiated,
  o.original_rent - o.last_proposed_rent_value AS original_to_final_value_difference,
  o.ts_first_iteration,
  o.ts_last_iteration
FROM
  datalake_rental_transact.offer AS o
JOIN
  datalake_ebdb_listing.house_listing AS hl
    ON hl.id_house = o.id_house
      AND COALESCE(o.ts_created, '1900-01-01') BETWEEN
          COALESCE(hl.ts_listing_version_start, '1900-01-01')
          AND COALESCE(hl.ts_listing_version_end, NOW())