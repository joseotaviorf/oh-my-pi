-- Grain: one row per DevelopmentNegotiation.
-- Visit house (id_house_shell) is the listing the visit was booked on.
-- Unit house (id_house) is DevelopmentTypologyUnit.imovel_id and is the house
-- on the Sales Flow offer. Match offer/flow on visit_external_id + unit house.
-- id_sales_flow / offer attrs are the non-canceled latest flow (then latest
-- offer) on that pair. ids_sales_flow is every flow id for the pair.
WITH sales_flow_offer_candidates AS (
    SELECT
        sf.id AS id_sales_flow,
        o.id AS id_offer,
        sf.id_visit_external,
        sf.id_house,
        sf.flow_step,
        o.status AS offer_status,
        o.offer_price,
        o.sale_price,
        o.final_price,
        sf.ts_created AS ts_sales_flow_created,
        ROW_NUMBER() OVER (
            PARTITION BY sf.id_visit_external, sf.id_house
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
    WHERE
        sf.id_visit_external IS NOT NULL
        AND sf.id_house IS NOT NULL
),
sales_flow_offer AS (
    SELECT
        c.id_sales_flow,
        c.id_offer,
        c.id_visit_external,
        c.id_house,
        h.ids_sales_flow,
        c.flow_step,
        c.offer_status,
        c.offer_price,
        c.sale_price,
        c.final_price,
        c.ts_sales_flow_created
    FROM
        sales_flow_offer_candidates AS c
    INNER JOIN (
        SELECT
            id_visit_external,
            id_house,
            SORT_ARRAY(COLLECT_SET(id_sales_flow)) AS ids_sales_flow
        FROM
            sales_flow_offer_candidates
        GROUP BY
            id_visit_external,
            id_house
    ) AS h
        ON h.id_visit_external = c.id_visit_external
        AND h.id_house = c.id_house
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
    sfo.ids_sales_flow,
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
        ON sfo.id_visit_external = n.id_visit
        AND sfo.id_house = dtu.id_house
