SELECT DISTINCT
    ha.id_invoice,
    COALESCE(b.id_contract, ha.id_contract) AS id_contract_cyber,
    COALESCE(c.id_contract_external, SPLIT(COALESCE(b.id_contract, ha.id_contract),r'\.')[0]) AS id_contract,
    ha.id_agreement AS id_negotiation
FROM datalake_cyber_clean.historical_agreements AS ha
LEFT JOIN datalake_cyber_clean.bill AS b
  ON ha.id_invoice = b.id_invoice
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON COALESCE(b.id_contract, ha.id_contract) = c.id_contract
