WITH for_sale AS (
    SELECT
        dh.sk_house AS id_house,
        1 AS trasaction_type,
        1 AS transaction_situation,
        0 AS iptu,
        sa.sale_price_agreed AS transaction_amount,
        dh.address AS address,
        dh.number AS address_number,
        dh.complement AS address_complement,
        dh.neighborhood AS address_neighborhood,
        dh.zipcode AS address_zipcode,
        CASE
            WHEN dh.type LIKE 'Casa%' THEN 2
            WHEN dh.type='Apartamento' THEN 3
            WHEN dh.type LIKE 'Studio%' THEN 3
            ELSE 0
        END AS house_type,
        dh.total_area AS useful_area,
        dh.total_area AS total_area,
        COALESCE(dh.construction_area) AS terrain_area,
        dh.parking_slots AS parking_slots,
        dh.bedrooms AS bedrooms,
        dh.bathrooms AS bathrooms,
        '1900' AS construction_year,
        TO_DATE(dd.date, 'YYYY-MM-DD') AS dt_transaction
    FROM
        dw_sale.fact_sale_flows AS fsf
    INNER JOIN
        dw_house.dim_house AS dh
            ON fsf.sk_house = dh.sk_house
    INNER JOIN
        dw_public.dim_date AS dd
            ON fsf.sk_sale_agreement_signed_date = dd.sk_date
    INNER JOIN
        dw_sale.fact_offers AS fo            
            ON concat(fo.sk_buyer,'_',fo.sk_house) = fsf.sk_sale_flow            
    INNER JOIN
        dw_sale.dim_sale_agreement AS sa
            ON sa.sk_offer = fo.sk_offer
    WHERE
        dd.date BETWEEN TRUNC(ADD_MONTHS(CURRENT_DATE(), -1), 'month') AND LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -1))
        AND LOWER(TRIM(dh.city)) IN ('são paulo', 'sao paulo')
        AND is_ccv_canceled = false
),
for_rent AS (
    SELECT
        imo.id AS id_house,
        2 AS trasaction_type,
        1 AS transaction_situation,
        0 AS iptu,
        con.rent AS transaction_amount,
        imo.address,
        imo.number AS address_number,
        imo.complement AS address_complement,
        imo.neighborhood AS address_neighborhood,
        imo.zipcode AS address_zipcode,
        CASE
            WHEN imo.type LIKE 'Casa%' THEN 2
            WHEN imo.type = 'Apartamento' THEN 3
            WHEN imo.type LIKE 'Studio%' THEN 3
            ELSE 0
        END AS house_type,
        imo.total_area AS useful_area,
        imo.total_area AS total_area,
        COALESCE(imo.land_area) AS terrain_area,
        imo.parking_slots AS parking_slots,
        imo.bedrooms AS bedrooms,
        imo.bathrooms AS bathrooms,
        '1900' AS construction_year,
        TO_DATE(con.ts_signed, 'YYYY-MM-DD') AS dt_transaction
    FROM
        datalake_ebdb_clean.contract AS con
    INNER JOIN
        datalake_ebdb_clean.house AS imo
            ON con.id_house = imo.id
    WHERE
        con.type = 'FullService'
        AND LOWER(TRIM(imo.city)) IN ('são paulo', 'sao paulo')
        AND TO_DATE(con.ts_signed, 'YYYY-MM-DD') BETWEEN TRUNC(ADD_MONTHS(CURRENT_DATE(), -1), 'month') AND LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -1))
        AND con.status IN ('Ativo', 'Finalizado')
)

SELECT 
         id_house
        ,trasaction_type
        ,transaction_situation
        ,iptu
        ,transaction_amount
        ,address
        ,address_number
        ,address_complement
        ,address_neighborhood
        ,address_zipcode
        ,house_type
        ,useful_area
        ,total_area
        ,terrain_area
        ,parking_slots
        ,bedrooms
        ,bathrooms
        ,construction_year
        ,dt_transaction
FROM (
    SELECT *
    FROM
        for_sale
    UNION
    SELECT *
    FROM
        for_rent
)
ORDER BY
    dt_transaction