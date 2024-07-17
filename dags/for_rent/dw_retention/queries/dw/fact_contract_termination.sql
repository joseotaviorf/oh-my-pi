SELECT
    dc.id AS sk_contract,
    ct.id_termination AS sk_termination,
    dc.country_code,
    NOW() AS ts_load
FROM
    datalake_offboarding.contract_termination AS ct
JOIN 
    datalake_ebdb_contract.contract AS dc
        ON dc.id = ct.id_contract
GROUP BY
    1, 2, 5