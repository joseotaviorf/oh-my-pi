-- Grain: one row per DevelopmentNegotiation (same as enrich development_negotiation).
-- Adds city_group, hub, and EN (negotiation executive / Deal Maker) so consumers
-- don't join sales_flow.offer / offer_specialists / region themselves.
-- EN and hub are LEFT JOINs on the offer: pre-offer negotiations have no id_offer,
-- so they stay NULL, same as the enrich table's own offer attributes.
WITH business_unit_by_hub_id AS (
    SELECT
        bu.id AS id_hub,
        bu.hub_name
    FROM
        datalake_hub_services_clean.business_unit AS bu
    WHERE
        bu.business_context = 'SALE'
)
SELECT
    dn.id_development_negotiation,
    dn.id_development,
    dn.id_visit,
    dn.id_house_development,
    dn.id_visitor,
    dn.id_demand,
    dn.id_agent,
    dn.id_development_negotiation_unit,
    dn.id_development_typology_unit,
    dn.id_house,
    dn.id_offer,
    dn.id_sales_flow,
    dn.id_development_typology,
    dn.id_development_listing_unit,
    dn.id_listing_business_context,
    dn.id_development_contact,
    dn.uuid_event,
    dn.actor,
    dn.flow_step,
    dn.offer_status,
    dn.offer_price,
    dn.sale_price,
    dn.final_price,
    dn.is_published_unit,
    dn.ts_created,
    dn.ts_updated,
    dn.ts_sales_flow_created,
    h.id_region,
    r.city_group,
    o.id_hub,
    bu.hub_name,
    sp.id_user_consultant AS id_user_negotiation_executive
FROM
    datalake_sale_primary_market.development_negotiation AS dn
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = dn.id_house
LEFT JOIN
    datalake_region.region AS r
        ON r.id = h.id_region
LEFT JOIN
    datalake_sales_flow_clean.offer AS o
        ON o.id = dn.id_offer
LEFT JOIN
    business_unit_by_hub_id AS bu
        ON bu.id_hub = o.id_hub
LEFT JOIN
    datalake_sale_offer_flows.offer_specialists AS sp
        ON sp.id_offer = o.id_firestore
