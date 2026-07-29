WITH recupera_negotiation_ranked AS (
  SELECT
    CAST(rn.id_negotiation AS BIGINT) AS id_negotiation,
    rn.id_contract,
    rn.advisory,
    CASE
      WHEN REPLACE(rn.origin_agreement, '_', ' ') = 'Portal Autonegociação' THEN 'Portal Auto Negociação'
      WHEN REPLACE(rn.origin_agreement, '_', ' ') = 'Operador' THEN 'Operador Interno'
      WHEN REPLACE(rn.origin_agreement, '_', ' ') = 'Carta Campanha' THEN 'Boletagem'
      ELSE REPLACE(rn.origin_agreement, '_', ' ')
    END AS origin_agreement,
    rn.promisse_payment_method,
    CASE
      WHEN rn.negotiation_status = 'ACORDO_LIQUIDADO' THEN 'finished'
      WHEN rn.negotiation_status = 'ACORDO_CANCELADO'
        AND rn.down_payment IS TRUE THEN 'broken'
      WHEN rn.negotiation_status = 'ACORDO_CANCELADO'
        AND rn.down_payment IS FALSE THEN 'canceled'
      WHEN rn.negotiation_status = 'ACORDO_EM_ANDAMENTO'
        AND rn.down_payment IS TRUE THEN 'offset'
      WHEN rn.negotiation_status = 'ACORDO_EM_ANDAMENTO' THEN 'started'
    END AS negotiation_status,
    rn.down_payment_amount,
    rn.original_debt_amount,
    rn.dt_promisse,
    rn.dt_down_payment,
    ROW_NUMBER() OVER (
      PARTITION BY rn.id_negotiation
      ORDER BY rn.ts_snapshot DESC, rn.id_contract DESC
    ) AS rn
  FROM datalake_recupera.negotiation AS rn
  WHERE rn.id_creditor NOT IN (3, 5)
)
SELECT
  id_negotiation,
  id_contract,
  advisory,
  origin_agreement,
  promisse_payment_method,
  negotiation_status,
  down_payment_amount,
  original_debt_amount,
  dt_promisse,
  dt_down_payment,
  NOW() AS ts_load
FROM recupera_negotiation_ranked
WHERE rn = 1
