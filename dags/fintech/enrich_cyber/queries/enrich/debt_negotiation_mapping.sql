WITH
deduplicate_invoices AS (
  SELECT
    id_contract,
    id_invoice
  FROM datalake_cyber_clean.bill
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice, contract_group ORDER BY ts_insert DESC) = 1
)
SELECT DISTINCT
    COALESCE(ha.id_invoice, cc.id_invoice) AS id_invoice,
    COALESCE(b.id_contract, ha.id_contract, cc.id_contract) AS id_contract_cyber,
    COALESCE(c.id_contract_external, SPLIT(COALESCE(b.id_contract, ha.id_contract, cc.id_contract),r'\.')[0]) AS id_contract,
    CAST(COALESCE(ha.id_agreement, cc.id_offer) AS STRING) AS id_negotiation
FROM datalake_cyber_clean.historical_agreements AS ha
LEFT JOIN deduplicate_invoices AS b
  ON ha.id_invoice = b.id_invoice
FULL OUTER JOIN datalake_cyber_clean.campaign_contracts AS cc
  ON ha.id_invoice = cc.id_invoice AND COALESCE(b.id_contract, ha.id_contract) = cc.id_contract
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON COALESCE(b.id_contract, ha.id_contract, cc.id_contract) = c.id_contract
