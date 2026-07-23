WITH partner AS (
  SELECT
    bsh.sk_broker,
    CASE
      WHEN bsh.product_name = 'Rede Sale' THEN 'SALE'
      ELSE 'RENT'
    END AS business_context,
    bsh.ts_start AS ts_partner_contract_start
  FROM
    datalake_brokers.broker_status_history AS bsh
  WHERE
    bsh.broker_status = 'ACTIVE'
),
leads_matched_to_latest_contract AS (
  SELECT
    lsc.sk_lead_3p_flow,
    l.id_lead_3p,
    l.lead_hash,
    l.uuid_company,
    partner.sk_broker,
    lsc.business_context,
    lsc.ts_business_context_created,
    partner.ts_partner_contract_start,
    ROW_NUMBER() OVER (
      PARTITION BY l.id_lead_3p, lsc.business_context
      ORDER BY partner.ts_partner_contract_start DESC
    ) AS rn_contract
  FROM
    datalake_3p_supply.lead_3p AS l
  LEFT JOIN
    datalake_3p_supply.lead_3p_status_changes AS lsc
      ON l.id_lead_3p = lsc.id_lead_3p
      AND lsc.is_current = TRUE
  LEFT JOIN
    core_brokers.brokers AS cb
      ON l.uuid_company = cb.uuid_company
  LEFT JOIN
    partner
      ON partner.sk_broker = cb.sk_broker
      AND partner.business_context = lsc.business_context
      AND partner.ts_partner_contract_start <= lsc.ts_business_context_created
),
latest_contract_per_lead AS (
  SELECT
    lm.sk_lead_3p_flow,
    lm.id_lead_3p,
    lm.lead_hash,
    lm.uuid_company,
    lm.sk_broker,
    lm.business_context,
    lm.ts_business_context_created,
    lm.ts_partner_contract_start,
    MIN(lm.ts_business_context_created) OVER (
      PARTITION BY lm.uuid_company, lm.business_context, lm.ts_partner_contract_start
    ) AS ts_first_lead_after_activation
  FROM
    leads_matched_to_latest_contract AS lm
  WHERE
    lm.rn_contract = 1
)
SELECT
  lc.sk_lead_3p_flow,
  lc.id_lead_3p,
  lc.business_context,
  lc.sk_broker,
  lc.ts_partner_contract_start,
  lc.ts_business_context_created,
  MIN(lc.ts_business_context_created) OVER (
    PARTITION BY lc.lead_hash, lc.uuid_company, lc.business_context
  ) AS ts_valid_first_lead,
  MIN(lc.ts_business_context_created) OVER (
    PARTITION BY lc.lead_hash, lc.uuid_company, lc.business_context, lc.ts_partner_contract_start
  ) AS ts_current_valid_first_lead,
  CASE
    WHEN lc.ts_business_context_created = MIN(lc.ts_business_context_created) OVER (
        PARTITION BY lc.lead_hash, lc.uuid_company, lc.business_context
      )
    THEN TRUE
    ELSE FALSE
  END AS is_valid_first_lead,
  CASE
    WHEN lc.ts_partner_contract_start IS NOT NULL
      AND lc.ts_business_context_created = MIN(lc.ts_business_context_created) OVER (
        PARTITION BY lc.lead_hash, lc.uuid_company, lc.business_context, lc.ts_partner_contract_start
      )
    THEN TRUE
    ELSE FALSE
  END AS is_current_valid_first_lead,
  CASE
    WHEN lc.ts_business_context_created IS NULL
      OR lc.ts_first_lead_after_activation IS NULL
    THEN 'N/A'
    WHEN lc.ts_business_context_created = lc.ts_first_lead_after_activation
    THEN 'FIRST_BATCH'
    WHEN lc.ts_business_context_created BETWEEN lc.ts_first_lead_after_activation
        AND lc.ts_first_lead_after_activation + INTERVAL 30 DAYS
    THEN 'FIRST_MONTH_BATCH'
    WHEN lc.ts_business_context_created < lc.ts_first_lead_after_activation
    THEN 'COMPLEMENTARY'
    ELSE 'RECURRENT'
  END AS recurrency_type,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  latest_contract_per_lead AS lc
