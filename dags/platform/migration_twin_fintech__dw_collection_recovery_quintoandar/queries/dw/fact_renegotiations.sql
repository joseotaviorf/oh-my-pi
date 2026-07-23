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
      fn.sk_negotiation AS sk_negotiation_child,
      fni_extra.sk_negotiation AS sk_negotiation_parent
    FROM datalake_retsuko.invoice AS i
    LEFT JOIN
      dw_collection_recovery_quintoandar.fact_debt AS fd
        ON i.id_external = fd.id_invoice
    LEFT JOIN
      dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS bmdn
        ON fd.sk_debt = bmdn.sk_debt
    LEFT JOIN
      dw_collection_recovery_quintoandar.fact_negotiation AS fn
        ON bmdn.sk_negotiation = fn.sk_negotiation
          AND fn.dt_down_payment IS NOT NULL
    LEFT JOIN
      dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni_original
        ON fn.sk_negotiation = fni_original.sk_negotiation
          AND fni_original.id_invoice_extra IS NOT NULL
    LEFT JOIN
      dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni_extra
        ON i.id_external = fni_extra.id_invoice_extra
),
invoice_mapping AS (
  SELECT
    b.id_contract,
    b.id_invoice_extra AS child_invoice,
    b.id_invoice AS parent_invoice,
    b.dt_due_adjusted AS parent_most_recent_due_date
  FROM base_calculation b
  WHERE b.id_invoice_extra IS NOT NULL
),
grouped_child_parents AS (
  SELECT
    id_contract,
    child_invoice,
    collect_set(parent_invoice) AS parent_array
  FROM invoice_mapping
  GROUP BY 1,2
),
invoice_map_json_by_contract AS (
  SELECT
    id_contract,
    TO_JSON(
      MAP_FROM_ENTRIES(
        COLLECT_LIST(
          NAMED_STRUCT('key', child_invoice, 'value', parent_array)
        )
      )
    ) AS invoice_map_json
  FROM grouped_child_parents
  GROUP BY 1
),
parent_due_agg AS (
  SELECT
    id_contract,
    parent_invoice,
    MAX(CAST(parent_most_recent_due_date AS STRING)) AS due_date_str
  FROM invoice_mapping
  GROUP BY 1, 2
),
due_date_map_json_by_contract AS (
  SELECT
    id_contract,
    TO_JSON(
      MAP_FROM_ENTRIES(
        COLLECT_LIST(
          NAMED_STRUCT('key', parent_invoice, 'value', due_date_str)
        )
      )
    ) AS due_date_map_json
  FROM parent_due_agg
  GROUP BY id_contract
),
calculate_anchor AS (
  SELECT
    b.id_contract,
    b.id_invoice,
    b.dt_due_adjusted,
    b.sk_negotiation_parent,
    b.sk_negotiation_child,
    m.invoice_map_json,
    d.due_date_map_json,
    fintech_collections_renegotiation(
      b.id_invoice,
      m.invoice_map_json,
      d.due_date_map_json,
      'latest'
    ) AS anchor_result_json
  FROM base_calculation b
  JOIN
    invoice_map_json_by_contract m
      ON b.id_contract = m.id_contract
  JOIN
    due_date_map_json_by_contract d
      ON b.id_contract = d.id_contract
),
get_negotiations AS (
  SELECT DISTINCT
    id_contract AS sk_contract,
    id_invoice AS sk_invoice,
    sk_negotiation_parent,
    sk_negotiation_child,
    get_json_object(anchor_result_json, '$.invoice') AS sk_anchor_invoice,
    get_json_object(anchor_result_json, '$.level') AS renegotiation_level,
    dt_due_adjusted,
    get_json_object(anchor_result_json, '$.due_date') AS dt_due_adjusted_anchor
  FROM calculate_anchor
  WHERE sk_negotiation_child IS NOT NULL OR sk_negotiation_parent IS NOT NULL
)
SELECT
  sk_contract,
  sk_invoice,
  sk_anchor_invoice,
  MAX(sk_negotiation_parent) AS sk_negotiation_parent,
  MAX(sk_negotiation_child) AS sk_negotiation_child,
  renegotiation_level,
  MIN(dt_due_adjusted_anchor) AS dt_due_adjusted_anchor
FROM get_negotiations
GROUP BY sk_contract, sk_invoice, sk_anchor_invoice, renegotiation_level
