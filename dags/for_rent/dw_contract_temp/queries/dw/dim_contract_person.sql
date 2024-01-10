SELECT
    *
FROM
    dw_rent.dim_contract_person
WHERE
    sk_contract_person > 0 -- The DAG already creates a -1 line on dimensions, by bringing it from the table we would have the sk duplicated
