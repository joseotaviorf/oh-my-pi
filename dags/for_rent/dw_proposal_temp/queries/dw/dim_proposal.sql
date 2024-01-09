SELECT
    *
FROM
    dw_rent.dim_proposal
WHERE
    sk_proposal > 0 -- The DAG already creates a -1 line on dimensions, by bringing it from the table we would have the sk duplicated
