SELECT DISTINCT
    h.id AS id_house,
    h.id_address_data,
    o.id AS id_offer,
    o.id_firestore,
    o.id_sales_flow,
    sf.id_buyer,
    sf.id_seller,
    DATE('{year}-{month}-{day}') AS dt_load,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM 
    datalake_sales_flow_clean.house_aud AS h
JOIN
    datalake_sales_flow_clean.sales_flow_aud AS sf
        ON sf.id_house = h.id
JOIN
    datalake_sales_flow_clean.offer AS o
        ON o.id_sales_flow = sf.id
WHERE
    DATE(sf.ts_created) = DATE('{year}-{month}-{day}')
    OR DATE(o.ts_created) = DATE('{year}-{month}-{day}')
    OR (
        sf.year = {year}
        AND sf.month = {month}
        AND sf.day = {day}
        AND (
            sf.mod_id_buyer IS TRUE
            OR sf.mod_id_seller IS TRUE
        )
    )
    OR (
        h.year = {year}
        AND h.month = {month}
        AND h.day = {day}
        AND h.mod_id_address_data IS TRUE
    )