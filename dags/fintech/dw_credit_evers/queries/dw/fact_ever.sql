SELECT
    COALESCE(c.sk_contract, f.sk_contract) AS sk_contract,
    COALESCE(c.sk_contract_retsuko, f.sk_contract_retsuko) AS sk_contract_retsuko,
    COALESCE(c.sk_contract_ebdb, f.sk_contract_ebdb) AS sk_contract_ebdb,
    COALESCE(c.sk_proposal, f.sk_proposal) AS sk_proposal,
    COALESCE(c.mob, f.mob) AS mob,
    COALESCE(c.ever, f.ever) AS ever,
    c.is_ever AS is_ever_clean,
    f.is_ever AS is_ever_full,
    c.is_ever_with_agreement AS is_ever_clean_with_agreement,
    f.is_ever_with_agreement AS is_ever_full_with_agreement,
    COALESCE(c.dt_contract_signature, f.dt_contract_signature) AS dt_contract_signature,
    COALESCE(c.dt_reference, f.dt_reference) AS dt_reference,
    COALESCE(c.dt_contract_updated, f.dt_contract_updated) AS dt_contract_updated
FROM dw_credit_evers.fact_ever_full AS f
FULL OUTER JOIN dw_credit_evers.fact_ever_clean AS c
  ON c.sk_contract = f.sk_contract
    AND c.ever = f.ever
    AND c.mob = f.mob
