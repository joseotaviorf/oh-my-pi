WITH listing_business_context AS (
  SELECT
    bc.id,
    a.id_house,
    a.business_context,
    a.status,
    a.status_reason,
    a.ts_last_status_changed,
    bc.ts_created,
    bc.status AS current_main_status,
    bc.status_reason AS current_main_status_reason,
    a.ts_first_publication,
    a.ts_updated,
    a.ts_cdc_transaction,
    a.ts_database_transaction
  FROM
    datalake_ebdb_clean.listing_business_context_aud AS a
  INNER JOIN
    datalake_ebdb_clean.listing_business_context AS bc
      ON a.id_listing_business_context = bc.id
  INNER JOIN
    datalake_3p_supply.lead_3p AS l
      ON l.id_house = a.id_house
  WHERE
    bc.ownership = 'THIRD_PARTY'
),
portfolio_manager_publishing AS (
  SELECT
    aud.id_house,
    aud.business_context,
    aud.status,
    e.principal_type,
    e.id_principal,
    LAG(aud.status) OVER (PARTITION BY aud.id_house, aud.business_context ORDER BY aud.ts_database_transaction ASC) AS prev_status,
    ROW_NUMBER() OVER (PARTITION BY aud.id_house, aud.business_context, aud.status ORDER BY aud.ts_database_transaction ASC) AS rn
  FROM
    datalake_ebdb_clean.listing_business_context_aud AS aud
  LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS e
      ON aud.rev = e.id
),
portfolio_manager_publishing_filtered AS (
  SELECT
    pm.id_house,
    pm.business_context
  FROM
    portfolio_manager_publishing AS pm
  WHERE
    pm.status != pm.prev_status
    AND pm.id_principal = 'portfolio-manager-api'
    AND pm.principal_type = 'SERVICE'
    AND pm.status = 'PUBLISHED'
    AND pm.rn = 1
)
SELECT
  CASE
    WHEN lbc.business_context = 'SALE' THEN lbc.id_house * 10
    WHEN lbc.business_context = 'RENT' THEN lbc.id_house * 10 + 1
  END AS sk_listing_draft_status,
  lbc.id_house,
  lbc.business_context,
  lbc.current_main_status,
  lbc.current_main_status_reason,
  pmf.id_house IS NOT NULL AS is_first_listing_published_through_portfolio_manager,
  MIN(CASE WHEN lbc.status = 'EDITING' AND lbc.status_reason = 'WAITING_CONFIRMATION' THEN lbc.ts_created END) AS ts_availability_check_start,
  MIN(CASE WHEN lbc.status <> 'EDITING' AND lbc.status <> 'PUBLISHED' THEN lbc.ts_last_status_changed WHEN lbc.status = 'PUBLISHED' THEN lbc.ts_first_publication END) AS ts_availability_check_end,
  MIN(CASE WHEN lbc.status = 'PUBLISHED' THEN lbc.ts_first_publication END) AS ts_first_listing,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  listing_business_context AS lbc
LEFT JOIN
  portfolio_manager_publishing_filtered AS pmf
    ON lbc.id_house = pmf.id_house
    AND lbc.business_context = pmf.business_context
GROUP BY
  lbc.id_house,
  lbc.business_context,
  lbc.current_main_status,
  lbc.current_main_status_reason,
  pmf.id_house IS NOT NULL
