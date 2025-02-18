WITH
base_calculation AS (
    SELECT DISTINCT
      i.id_contract_external AS id_contract,
      i.id_external AS id_invoice,
      fni_original.id_invoice_extra,
      DATE(fn.dt_promisse) AS dt_negotiation_creation,
      i.dt_due_adjusted,
      DATE(i.ts_created) AS dt_created,
      fn.dt_down_payment,
      fn.sk_negotiation AS sk_negotiation_created,
      fni_extra.sk_negotiation AS sk_negotiation_created_by
    FROM datalake_retsuko.invoice AS i
    LEFT JOIN dw_collection_recovery_quintoandar.fact_debt AS fd
      ON i.id_external = fd.id_invoice
    LEFT JOIN dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS bmdn
      ON fd.sk_debt = bmdn.sk_debt
    LEFT JOIN dw_collection_recovery_quintoandar.fact_negotiation AS fn
      ON bmdn.sk_negotiation = fn.sk_negotiation
        AND fn.dt_down_payment IS NOT NULL
    LEFT JOIN dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni_original
      ON fn.sk_negotiation = fni_original.sk_negotiation
        AND fni_original.id_invoice_extra IS NOT NULL
    LEFT JOIN dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni_extra
      ON i.id_external = fni_extra.id_invoice_extra
),
invoice_mapping AS (
    SELECT
        id_contract,
        id_invoice_extra AS child_invoice,
        id_invoice AS parent_invoice
    FROM base_calculation
    WHERE id_invoice_extra IS NOT NULL
),
calculate_anchor AS (
    SELECT
        b.id_contract,
        b.id_invoice,
        b.dt_due_adjusted,
        b.sk_negotiation_created_by,
        b.sk_negotiation_created,
        FINTECH_COLLECTIONS_RENEGOTIATION(
            b.id_invoice,
            map_from_entries(
                collect_set(named_struct('key', i.child_invoice, 'value', i.parent_invoice))
            )
        ) AS anchor_result
    FROM base_calculation b
    LEFT JOIN invoice_mapping i
      ON b.id_contract = i.id_contract
    WHERE
      i.child_invoice IS NOT NULL
      AND i.parent_invoice IS NOT NULL
    GROUP BY 1,2,3,4,5
),
get_negotiations AS (
  SELECT DISTINCT
      id_contract AS sk_contract,
      id_invoice AS sk_invoice,
      anchor_result.invoice AS sk_anchor_invoice,
      MAX(sk_negotiation_created) OVER(PARTITION BY id_contract, anchor_result.invoice, anchor_result.level) AS sk_negotiation_created,
      MAX(sk_negotiation_created_by) OVER(PARTITION BY id_contract, anchor_result.invoice, anchor_result.level) AS sk_negotiation_created_by,
      anchor_result.level AS renegotiation_level,
      dt_due_adjusted,
      MIN(dt_due_adjusted) OVER(PARTITION BY id_contract, anchor_result.invoice) AS dt_due_adjusted_anchor
  FROM calculate_anchor
)
SELECT
  sk_contract,
  sk_invoice,
  sk_anchor_invoice,
  sk_negotiation_created,
  sk_negotiation_created_by,
  renegotiation_level,
  dt_due_adjusted,
  dt_due_adjusted_anchor
FROM get_negotiations
WHERE
  sk_negotiation_created IS NOT NULL
  OR sk_negotiation_created_by IS NOT NULL
