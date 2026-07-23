SELECT
    dc.id AS sk_contract,
    ct.id_termination AS sk_termination,
    MAX(IF(dna.customer_type = 'PP', dna.sk_nps_answer, NULL)) AS sk_nps_answer_owner,
    MAX(IF(dna.customer_type = 'IQ', dna.sk_nps_answer, NULL)) AS sk_nps_answer_tenant,
    dc.country_code,
    NOW() AS ts_load
FROM
    datalake_offboarding.contract_termination AS ct
JOIN 
    datalake_ebdb_contract.contract AS dc
        ON dc.id = ct.id_contract
LEFT JOIN
    datalake_nps_answer_drivers.answer_drivers AS ad
        ON ct.id_contract = ad.id_contract
LEFT JOIN
    dw_retention.dim_nps_answer AS dna
        ON dna.sk_nps_answer = ad.id_answer
GROUP BY
    1, 2, 5