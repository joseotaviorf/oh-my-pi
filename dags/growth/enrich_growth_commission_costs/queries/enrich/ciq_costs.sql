WITH upfront_payments_robinhood AS (
  SELECT
    CASE
      WHEN TRY_CAST(SUBSTR(ae.description,LENGTH(ae.description)-18+1) AS BIGINT) IS NOT NULL
        AND SUBSTR(ae.description, 1, 8) = 'Campanha'
        AND ae.id_source = 9 THEN SUBSTR(ae.description, LENGTH(ae.description)-18+1, 9)
      WHEN ae.id_source = 9 THEN SUBSTR(ae.description, LENGTH(ae.description)-8)
      ELSE COALESCE(ae.id_house, c.id_house)
    END AS id_house,
    description,
    ae.id_contract,
    ae.id_source,
    id_payee_external as id_ciq ,
    CASE
      WHEN ae.id_source = 9
      AND ae.cost_center_code = 'R01450' THEN ae.due_amount ELSE 0
    END AS comission_listing_fr,
    CASE
      WHEN ae.id_source = 9 AND ae.cost_center_code = 'S01450' THEN ae.due_amount ELSE 0
    END comission_listing_fS,
    CASE
      WHEN ae.id_source = 8 THEN ae.due_amount ELSE 0
      END AS revshare_cs_ciq_full,
    CASE
      WHEN ae.id_source = 9 THEN DATE_ADD(TO_DATE(CONCAT(ae.accounting_year_month, '01'), 'yyyyMMdd'), 14)
      WHEN ae.id_source = 8 THEN DATE_ADD(TO_DATE(CONCAT(ae.accrual_year_month, '01'), 'yyyyMMdd'), 24)
    END AS accounting_year_month
  FROM
    datalake_robin_hood.accounting_entry AS ae
  LEFT JOIN
    datalake_robin_hood_clean.accounting_entry_balance AS aeb
      ON ae.id = aeb.id_accounting_entry
  LEFT JOIN
    datalake_robin_hood_clean.payment_request AS pr
      ON aeb.id_payment_request = pr.id
  LEFT JOIN
    datalake_ebdb_agents.ciq_users AS ciq
      ON ae.id_payee_external = cast(ciq.id_partner AS string)
      AND ciq.is_last_status = TRUE
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON c.id = id_contract
  WHERE
      (ae.ts_blocked IS NULL OR pr.status IN ('paid','scheduled'))
      AND pr.id_next_attempt IS NULL
      AND ae.id_source IN (8,9)
),
robin_hood AS (
  SELECT
    accounting_year_month,
    id_house,
    id_ciq,
    h.id_region,
    SUM(comission_listing_fr) AS comission_listing_fr,
    SUM(comission_listing_fs) AS comission_listing_fS,
    SUM(revshare_cs_ciq_full) AS revshare_cs_ciq_full
  FROM upfront_payments_robinhood up
    LEFT JOIN datalake_ebdb_listing.house h
      ON h.id = up.id_house
    LEFT JOIN  datalake_region.region  r
      ON r.id = h.id_region
  WHERE
    h.city IS NOT NULL
    AND r.city_group IS NOT NULL
    AND up.accounting_year_month >= '2024-01-01'
  GROUP BY ALL
),
outcome_reference AS (
  SELECT
    id_outcome,
    MAX(dt_outcome) dt_outcome
  FROM
    datalake_monopoly_clean.outcome_reference
  GROUP BY ALL
),
monopolly AS (
  SELECT
      oref.dt_outcome AS paid_at,
      so.id_house,
      so.id_region,
      ps.id AS id_ciq,
      SUM(o.amount) AS revshare_ccv_ciq_full_fs
  FROM
      datalake_monopoly_clean.outcome AS o
      JOIN outcome_reference AS oref
        ON o.id = oref.id_outcome
      JOIN datalake_monopoly_clean.person_sale AS ps
        ON o.id_person_sale = ps.id
      JOIN datalake_monopoly_clean.revenue_share AS rs
        ON o.id_revenue_share = rs.id
      JOIN datalake_monopoly_clean.sale AS s
        ON ps.id_sale = s.id
      JOIN datalake_monopoly_clean.sale_revision AS sr
        ON s.id = sr.id AND s.current_revision = sr.revision
      LEFT JOIN datalake_offer.sale_offer AS so
        ON so.id_offer = s.id_external_offer
  WHERE
      rs.type = 'CIQ'
      AND o.outcome_status = 'paid'
      AND oref.dt_outcome >= '2024-01-01'
  GROUP BY ALL
)
SELECT
  COALESCE(m.id_house, rh.id_house) AS id_house,
  COALESCE(m.id_region, rh.id_region) AS id_region,
  COALESCE(m.id_ciq, rh.id_ciq) AS id_ciq,
  rh.comission_listing_fr,
  rh.comission_listing_fs,
  rh.revshare_cs_ciq_full,
  m.revshare_ccv_ciq_full_fs,
  COALESCE(m.paid_at, rh.accounting_year_month) AS dt_paid,
  YEAR(dt_paid) AS year,
  MONTH(dt_paid) AS month,
  DAY(dt_paid) AS day,
  NOW() AS ts_load
FROM
  robin_hood AS rh
FULL OUTER JOIN
  monopolly AS m
    ON rh.id_region = m.id_region
    AND paid_at = accounting_year_month
    AND m.id_ciq = rh.id_ciq
    AND rh.id_house = m.id_house
