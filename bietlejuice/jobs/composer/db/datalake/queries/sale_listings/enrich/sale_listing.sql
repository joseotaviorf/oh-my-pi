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
)
SELECT
  BIGINT(STRING(sls.id_house)||'00'||STRING(sls.order_version)) AS id_sale_listing,
  lc.id_house,
  IF(lc.ts_last_depublication > lc.ts_last_publication,
    COALESCE(DATEDIFF(lc.ts_last_depublication, lc.ts_last_publication)),
    NULL)
  AS days_last_publication_to_depublication,
 DATEDIFF(lc.ts_first_depublication, lc.ts_first_publication) AS days_first_publication_to_first_depublication,
  lc.unpublications,
  lc.ts_first_publication,
  lc.ts_last_publication,
  lc.ts_first_depublication,
  lc.ts_last_depublication,
  COALESCE(DATEDIFF(NOW(), lc.ts_first_publication) - np.days_not_published, 0) AS days_as_published
FROM 
  listing_columns AS lc
JOIN 
  datalake_sale_listings.sale_status_version_order AS sls
    ON lc.id_house = sls.id_house
LEFT JOIN
  not_published AS np
    ON np.id_house = lc.id_house
