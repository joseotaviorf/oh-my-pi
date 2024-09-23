SELECT DISTINCT
    ha.id_invoice,
    ha.id_contract,
    c.id_contract_external,
    ha.id_agreement AS id_negotiation
FROM datalake_cyber_clean.historical_agreements AS ha
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON ha.id_contract = c.id_contract
