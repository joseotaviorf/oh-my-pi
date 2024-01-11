SELECT
    *
FROM
    dw_rent.dim_house_listing
WHERE
  sk_house_listing > 0 -- The DAG already creates a -1 line on dimensions, by bringing it from the table we would have the sk duplicated
