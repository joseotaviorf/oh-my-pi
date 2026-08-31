WITH brokers_members_ranked AS (
  SELECT
    c.id_company,
    COALESCE(c.cnpj_unique, c.cnpj) AS cnpj,
    ROW_NUMBER() OVER(
      PARTITION BY COALESCE(c.cnpj_unique, c.cnpj)
      ORDER BY
        (c.sale_lead_status = 'Membro') DESC,
        (c.id_hubspot_owner IS NOT NULL) DESC,
        (c.cnpj_unique IS NOT NULL) DESC,
        c.ts_updated DESC,
        c.id_company DESC
    ) AS rn
  FROM
    datalake_hubspot.company AS c
  WHERE
    (c.has_been_sale_member OR c.has_been_rent_member)
      AND NOT(c.is_archived)
      AND NOT(c.is_merged_into_other_company)
),
brokers_members AS (
  SELECT
    bmr.id_company,
    bmr.cnpj
  FROM
    brokers_members_ranked AS bmr
  WHERE
    bmr.rn = 1
),
ts_switch AS (
  SELECT
    ch.id_company,
    MIN(CASE WHEN ch.id_account_manager_for_sale IS NOT NULL THEN ch.ts_updated END) AS ts_switch_sale,
    MIN(CASE WHEN ch.id_account_manager_for_rent IS NOT NULL THEN ch.ts_updated END) AS ts_switch_rent
  FROM
    datalake_hubspot.company_history AS ch
  INNER JOIN
    brokers_members AS bm
      ON ch.id_company = bm.id_company
  GROUP BY
    ch.id_company
),
lanes AS (
  SELECT
    'SALE' AS business_context
  UNION ALL
  SELECT
    'RENT' AS business_context
),
lane_revisions AS (
  SELECT
    cb.sk_broker,
    ch.id_company AS id_hubspot_company,
    ln.business_context,
    CASE
      WHEN ln.business_context = 'SALE'
        AND sw.ts_switch_sale IS NOT NULL
        AND ch.ts_updated >= sw.ts_switch_sale
        THEN ch.id_account_manager_for_sale
      WHEN ln.business_context = 'RENT'
        AND sw.ts_switch_rent IS NOT NULL
        AND ch.ts_updated >= sw.ts_switch_rent
        THEN ch.id_account_manager_for_rent
      ELSE ch.id_hubspot_owner
    END AS id_account_manager,
    CASE
      WHEN ln.business_context = 'SALE'
        AND sw.ts_switch_sale IS NOT NULL
        AND ch.ts_updated >= sw.ts_switch_sale
        THEN 'ACCOUNT_MANAGER_FOR_SALE'
      WHEN ln.business_context = 'RENT'
        AND sw.ts_switch_rent IS NOT NULL
        AND ch.ts_updated >= sw.ts_switch_rent
        THEN 'ACCOUNT_MANAGER_FOR_RENT'
      ELSE 'HUBSPOT_OWNER'
    END AS account_manager_source,
    ch.ts_updated
  FROM
    datalake_hubspot.company_history AS ch
  INNER JOIN
    brokers_members AS bm
      ON ch.id_company = bm.id_company
  INNER JOIN
    core_brokers.brokers AS cb
      ON bm.cnpj = cb.cnpj
  LEFT JOIN
    ts_switch AS sw
      ON sw.id_company = ch.id_company
  CROSS JOIN
    lanes AS ln
),
eligible_revisions AS (
  SELECT
    lr.sk_broker,
    lr.id_hubspot_company,
    lr.business_context,
    lr.id_account_manager,
    lr.account_manager_source,
    lr.ts_updated,
    LAG(lr.id_account_manager) OVER (
      PARTITION BY
        lr.sk_broker,
        lr.business_context
      ORDER BY
        lr.ts_updated
    ) AS prev_id_account_manager
  FROM
    lane_revisions AS lr
  WHERE
    NOT (
      lr.account_manager_source = 'HUBSPOT_OWNER'
      AND lr.id_account_manager IS NULL
    )
),
owner_changes AS (
  SELECT
    er.sk_broker,
    er.id_hubspot_company,
    er.business_context,
    er.id_account_manager,
    er.account_manager_source,
    er.ts_updated AS ts_start,
    LEAD(er.ts_updated) OVER (
      PARTITION BY
        er.sk_broker,
        er.business_context
      ORDER BY
        er.ts_updated
    ) AS ts_end
  FROM
    eligible_revisions AS er
  WHERE
    er.prev_id_account_manager IS NULL
    OR er.id_account_manager IS DISTINCT FROM er.prev_id_account_manager
),
clipped_periods AS (
  SELECT
    oc.sk_broker,
    oc.id_hubspot_company,
    oc.business_context,
    oc.id_account_manager,
    oc.account_manager_source,
    CASE
      WHEN oc.business_context = 'RENT'
        THEN GREATEST(oc.ts_start, CAST('2026-02-01' AS TIMESTAMP))
      ELSE oc.ts_start
    END AS ts_start,
    oc.ts_end
  FROM
    owner_changes AS oc
  WHERE
    oc.business_context = 'SALE'
    OR (
      oc.business_context = 'RENT'
      AND (
        oc.ts_end IS NULL
        OR oc.ts_end > CAST('2026-02-01' AS TIMESTAMP)
      )
    )
)
SELECT
  cp.sk_broker,
  cp.id_hubspot_company,
  cp.id_account_manager,
  cp.business_context,
  cp.account_manager_source,
  ROW_NUMBER() OVER (
    PARTITION BY
      cp.sk_broker,
      cp.business_context
    ORDER BY
      cp.ts_start
  ) AS version,
  LEAD(cp.ts_start) OVER (
    PARTITION BY
      cp.sk_broker,
      cp.business_context
    ORDER BY
      cp.ts_start
  ) IS NULL AS is_current,
  cp.ts_start,
  cp.ts_end,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  clipped_periods AS cp
