WITH listing_depublication AS (
  SELECT 
    lbc_aud.id_house,
    rev.id,
    lbc_aud.status,
    lbc_aud.mod_status,
    rev.ts_revision AS depublication_time
  FROM 
    datalake_ebdb_clean.listing_business_context_aud lbc_aud
  LEFT JOIN
    datalake_ebdb_user_revision_entity.user_revision_entity rev
      ON lbc_aud.rev = rev.id
      AND lbc_aud.status = 'UNPUBLISHED'
      AND lbc_aud.mod_status = 1
  WHERE lbc_aud.business_context = 'SALE'
),
not_published AS (
  SELECT 
    ssvo.id_house, 
    SUM(DATEDIFF(ssvo.ts_status_changed_next, ssvo.ts_status_changed_new)) AS days_not_published 
  FROM 
    datalake_sale_listings.sale_status_version_order AS ssvo
  JOIN 
    datalake_ebdb_clean.listing_business_context AS lbc
    ON ssvo.id_house = lbc.id_house 
    AND lbc.business_context = 'SALE'
  WHERE 
    ssvo.status_history_new IN ('SUSPENDED', 'UNPUBLISHED')
  GROUP BY ssvo.id_house
),
listing_columns AS (
  SELECT 
    lbc.id_house,
    lbc.ts_first_publication,
    lbc.ts_last_publication,
    MIN(ld.depublication_time) AS ts_first_depublication,
    MAX(ld.depublication_time) AS ts_last_depublication,
    COUNT(ld.id) AS unpublications
  FROM 
    datalake_ebdb_clean.listing_business_context lbc
  LEFT JOIN
    listing_depublication ld
      ON lbc.id_house = ld.id_house
  WHERE lbc.business_context = 'SALE'
  GROUP BY 1, 2, 3
),
sale_status_version_order AS (
SELECT
    BIGINT(STRING(id_house)||'00'||STRING(order_version)) AS id_sale_listing,
    id_house,
    COALESCE(
      MAX(ts_status_changed_new) OVER(
        PARTITION BY id_house
      ) = ts_status_changed_new,
    FALSE) AS is_last_status
FROM 
    datalake_sale_listings.sale_status_version_order
)
-- Get information about rent context to build flags about the house
, rental_context AS (
  SELECT
    lbc.id_house,
    MAX(IF(c.status ='Ativo',TRUE,FALSE)) AS has_active_rental_contract,
    MAX(IF(c.id_house IS NOT NULL ,TRUE,FALSE)) AS has_house_been_rented
  FROM
    datalake_ebdb_clean.listing_business_context AS lbc
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON c.id_house = lbc.id_house
  WHERE
    lbc.business_context = 'RENT'
  GROUP BY 1
 )
 -- Get information about first demand dates
 , first_sale_flows AS (
   SELECT
     id_house,
     MIN(ts_first_event) AS ts_first_sale_flow,
     MIN(ts_first_booking_created) AS ts_first_booking,
     MIN(dt_sale_agreement_signed) AS dt_first_sale_agreement_signed,
     MIN(dt_house_registry_ended) AS dt_house_registry_ended,
     MIN(ts_first_offer_submitted) AS ts_first_offer_submitted
   FROM
     datalake_sale_flows.sale_flow
   GROUP BY 1
 )
SELECT
  sls.id_sale_listing,
  lc.id_house,
  IF(rc.id_house IS NOT NULL, TRUE, FALSE) AS is_for_rent,
  COALESCE(has_active_rental_contract, FALSE) AS has_active_rental_contract,
  COALESCE(has_house_been_rented, FALSE) AS has_house_been_rented,
  IF(lc.ts_last_depublication > lc.ts_last_publication,
  COALESCE(
    DATEDIFF(lc.ts_last_depublication, lc.ts_last_publication)),
    NULL
  ) AS days_last_publication_to_depublication,
  DATEDIFF(lc.ts_first_depublication, lc.ts_first_publication) AS days_first_publication_to_first_depublication,
  DATEDIFF(lc.ts_last_depublication, lc.ts_first_publication) AS days_first_publication_to_last_depublication,
  DATEDIFF(sf.ts_first_sale_flow, lc.ts_first_publication) AS days_first_publication_to_first_sale_flow,
  DATEDIFF(sf.ts_first_booking, lc.ts_first_publication) AS days_first_publication_to_first_booking,
  DATEDIFF(sf.dt_first_sale_agreement_signed, lc.ts_first_publication) AS days_first_publication_to_first_sale_agreement_signed,
  DATEDIFF(sf.dt_house_registry_ended, lc.ts_first_publication) AS days_first_publication_to_house_registry_ended,
  DATEDIFF(sf.ts_first_offer_submitted, lc.ts_first_publication) AS days_first_publication_to_first_offer_submitted,
  lc.unpublications,
  lc.ts_first_publication,
  lc.ts_last_publication,
  lc.ts_first_depublication,
  lc.ts_last_depublication,
  sf.ts_first_sale_flow,
  sf.ts_first_offer_submitted,
  sf.ts_first_booking,
  sf.dt_first_sale_agreement_signed,
  sf.dt_house_registry_ended,
  IF(lc.ts_first_publication IS NULL, NULL, DATEDIFF(NOW(), lc.ts_first_publication) - COALESCE(np.days_not_published,0)) AS days_as_published
FROM
  listing_columns AS lc
JOIN
  sale_status_version_order AS sls
    ON lc.id_house = sls.id_house
    AND sls.is_last_status
LEFT JOIN
  not_published AS np
    ON np.id_house = lc.id_house
LEFT JOIN
  rental_context rc
    ON rc.id_house = lc.id_house
LEFT JOIN
  first_sale_flows sf
    ON sf.id_house = lc.id_house
