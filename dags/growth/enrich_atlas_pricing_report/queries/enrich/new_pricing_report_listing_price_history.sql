SELECT
    id_house,
    business_context,
    dt_price_updated,
    price,
    status
FROM datalake_atlas_pricing_report.status_history_house_listing

UNION

SELECT
    id_house,
    business_context,
    dt_price_updated,
    price,
    status
FROM datalake_atlas_pricing_report.status_history_house_negotiation

UNION 

SELECT
    id_house,
    business_context,
    dt_price_updated,
    price,
    status
FROM datalake_atlas_pricing_report.status_history_house_price_change

UNION 

SELECT
    id_house,
    business_context,
    dt_price_updated,
    price,
    status
FROM datalake_atlas_pricing_report.status_history_house_unpublished
