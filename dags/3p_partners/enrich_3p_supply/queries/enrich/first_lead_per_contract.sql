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
)
SELECT
  lm.id_lead_3p,
  lm.business_context,
  lm.sk_broker,
  lm.ts_partner_contract_start,
  lm.ts_business_context_created,
  MIN(lm.ts_business_context_created) OVER (
    PARTITION BY lm.lead_hash, lm.uuid_company, lm.business_context, lm.ts_partner_contract_start
  ) AS ts_first_valid_post_contract,
  CASE
    WHEN lm.ts_partner_contract_start IS NOT NULL
      AND lm.ts_business_context_created = MIN(lm.ts_business_context_created) OVER (
        PARTITION BY lm.lead_hash, lm.uuid_company, lm.business_context, lm.ts_partner_contract_start
      )
    THEN TRUE
    ELSE FALSE
  END AS is_valid_lead_occurrence,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  leads_matched_to_latest_contract AS lm
WHERE
  lm.rn_contract = 1
