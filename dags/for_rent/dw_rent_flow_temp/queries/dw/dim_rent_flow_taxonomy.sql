SELECT
    *
FROM
    dw_rent.dim_rent_flow_taxonomy
WHERE
    sk_rent_flow_taxonomy > 0 -- The DAG already creates a -1 line on dimensions, by bringing it from the table we would have the sk duplicated
