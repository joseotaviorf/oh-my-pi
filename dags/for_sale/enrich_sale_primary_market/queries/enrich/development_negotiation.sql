-- Grain: one row per DevelopmentNegotiation.
-- Visit house (id_house_shell) is the listing the visit was booked on.
-- Unit house (id_house) is DevelopmentTypologyUnit.imovel_id and is the house
-- on the Sales Flow offer. Match offer/flow on visit_external_id + unit house.
-- Several sales_flow rows can share that pair: keep non-canceled, then latest
-- ts_created on the flow, then latest ts_created on the offer.
WITH sales_flow_offer AS (
    SELECT
        id_sales_flow,
        id_offer,
        id_visit_external,
        id_house
    FROM (
        SELECT
            sf.id AS id_sales_flow,
            o.id AS id_offer,
            sf.id_visit_external,
            sf.id_house,
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
    ) AS _sales_flow_offer
    WHERE
        _w = 1
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
    CASE
        WHEN dtu.id IS NULL THEN NULL
        ELSE dlu.id IS NOT NULL
    END AS is_published_unit,
    n.ts_created,
    n.ts_updated
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
