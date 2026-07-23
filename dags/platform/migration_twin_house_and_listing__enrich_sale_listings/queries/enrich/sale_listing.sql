WITH listing_depublication_events AS (
    SELECT
        lbc_aud.id_house,
        CASE
            WHEN lbc_aud.status = 'UNPUBLISHED'
            AND lbc_aud.status IS DISTINCT FROM LAG(lbc_aud.status) OVER(PARTITION BY lbc_aud.id_house, lbc_aud.business_context ORDER BY lbc_aud.rev)
            THEN rev.ts_revision
            ELSE NULL
        END AS depublication_time,
        CASE
            WHEN lbc_aud.status = 'UNPUBLISHED'
            AND lbc_aud.status IS DISTINCT FROM LAG(lbc_aud.status) OVER(PARTITION BY lbc_aud.id_house, lbc_aud.business_context ORDER BY lbc_aud.rev)
            THEN 1
            ELSE 0
        END AS is_depublication_event
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbc_aud
    LEFT JOIN
        datalake_ebdb_user.user_revision_entity AS rev
            ON lbc_aud.rev = rev.id
    WHERE
        lbc_aud.business_context = 'SALE'
),
depublication_summary AS (
    SELECT
        id_house,
        MIN(depublication_time) AS ts_first_depublication,
        MAX(depublication_time) AS ts_last_depublication,
        SUM(is_depublication_event) AS unpublications
    FROM
        listing_depublication_events
    GROUP BY
        id_house
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
        lbc.ts_first_listing AS ts_first_publication,
        lbc.ts_last_listing AS ts_last_publication,
        ds.ts_first_depublication,
        ds.ts_last_depublication,
        COALESCE(ds.unpublications, 0) AS unpublications
    FROM
        datalake_ebdb_listing.listing_business_context AS lbc
    LEFT JOIN
        depublication_summary AS ds
            ON lbc.id_house = ds.id_house
    WHERE
        lbc.business_context = 'SALE'
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
),
-- Get information about rent context to build flags about the house
rental_context AS (
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
  lc.unpublications,
  lc.ts_first_publication,
  lc.ts_last_publication,
  lc.ts_first_depublication,
  lc.ts_last_depublication,
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
  rental_context AS rc
    ON rc.id_house = lc.id_house
