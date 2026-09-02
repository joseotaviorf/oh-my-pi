-- Grain: one row per DevelopmentNegotiation.
-- Strong key to Sales Flow is unit house (id_house = DTU.imovel_id = house.id_external).
-- id_visit is payload on the negotiation, not a join predicate to offer/flow.
-- id_house_shell is the listing Imovel the visit was booked on; offer house is minted.
-- sales_flow.house_id is the Sales Flow house PK; Imovel is house.id_external.
-- Latest flow prefers not canceled, then latest ts_created.
WITH sales_flow_offer_candidates AS (
    SELECT
        sf.id AS id_sales_flow,
        o.id AS id_offer,
        h.id_external AS id_house,
        sf.flow_step,
        o.status AS offer_status,
        o.offer_price,
        o.sale_price,
        o.final_price,
        sf.ts_created AS ts_sales_flow_created,
        ROW_NUMBER() OVER (
            PARTITION BY h.id_external
            ORDER BY
                CASE
                    WHEN COALESCE(sf.is_canceled, FALSE) = FALSE THEN 0
                    ELSE 1
                END,
                sf.ts_created DESC,
                o.ts_created DESC
        ) AS _w
    FROM
        datalake_sales_flow_clean.sales_flow AS sf
    INNER JOIN
        datalake_sales_flow_clean.offer AS o
            ON o.id_sales_flow = sf.id
    INNER JOIN
        datalake_sales_flow_clean.house AS h
            ON h.id = sf.id_house
    WHERE
        h.id_external IS NOT NULL
),
sales_flow_offer AS (
    SELECT
        c.id_sales_flow,
        c.id_offer,
        c.id_house,
        c.flow_step,
        c.offer_status,
        c.offer_price,
        c.sale_price,
        c.final_price,
        c.ts_sales_flow_created
    FROM
        sales_flow_offer_candidates AS c
    WHERE
        c._w = 1
)
SELECT
    n.id AS id_development_negotiation,
    n.id_development,
    n.id_visit,
    v.id_house AS id_house_shell,
    v.id_visitor,
    n.id_demand,
    n.id_agent,
    nu.id AS id_development_negotiation_unit,
    nu.id_development_typology_unit,
    dtu.id_house,
    sfo.id_offer,
    sfo.id_sales_flow,
    dtu.id_development_typology,
    dlu.id AS id_development_listing_unit,
    dlu.id_listing_business_context,
    d.id_development_contact,
    n.uuid_event,
    n.actor,
    sfo.flow_step,
    sfo.offer_status,
    sfo.offer_price,
    sfo.sale_price,
    sfo.final_price,
    CASE
        WHEN dtu.id IS NULL THEN NULL
        ELSE dlu.id IS NOT NULL
    END AS is_published_unit,
    n.ts_created,
    n.ts_updated,
    sfo.ts_sales_flow_created
FROM
    datalake_ebdb_clean.development_negotiation AS n
LEFT JOIN
    datalake_ebdb_clean.visit AS v
        ON v.id = n.id_visit
LEFT JOIN
    datalake_ebdb_clean.development_negotiation_unit AS nu
        ON nu.id_development_negotiation = n.id
LEFT JOIN
    datalake_ebdb_clean.development_typology_unit AS dtu
        ON dtu.id = nu.id_development_typology_unit
LEFT JOIN
    datalake_ebdb_clean.development_listing_unit AS dlu
        ON dlu.id_development_typology_unit = dtu.id
LEFT JOIN
    datalake_ebdb_clean.development AS d
        ON d.id = n.id_development
LEFT JOIN
    sales_flow_offer AS sfo
        ON sfo.id_house = dtu.id_house
