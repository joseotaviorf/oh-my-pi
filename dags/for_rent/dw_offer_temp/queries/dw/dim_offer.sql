SELECT
    *
FROM
    dw_rent.dim_offer
WHERE
    sk_offer > 0 -- The DAG already creates a -1 line on dimensions, by bringing it from the table we would have the sk duplicated
