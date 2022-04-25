SELECT
    NULLIF(id_rule_city_group_rent, '') AS id_rule_city_group_rent,
    NULLIF(id_rule_city_group_sale, '') AS id_rule_city_group_sale,
    CAST(NULLIF(REPLACE(invoice_number, ',', ''), '') AS INT) AS invoice_number,
    NULLIF(action, '') AS action,
    NULLIF(business_context, '') AS business_context,
    NULLIF(campaign_name, '') AS campaign_name,
    NULLIF(city_group, '') AS city_group,
    NULLIF(cnpj, '') AS cnpj,
    CAST(NULLIF(REPLACE(cost, ',', ''), '') AS DECIMAL(14,6)) AS cost,
    NULLIF(cost_category, '') AS cost_category,
    NULLIF(cost_center, '') AS cost_center,
    NULLIF(cost_subcategory, '') AS cost_subcategory,
    NULLIF(description, '') AS description,
    NULLIF(email, '') AS email,
    NULLIF(entry_type, '') AS entry_type,
    NULLIF(team, '') AS team,
    NULLIF(vendor_name, '') AS vendor_name,
    CASE
        WHEN has_city_group_share_1 = 'Sim' THEN true
        WHEN has_city_group_share_1 = 'Não' THEN false
        ELSE NULL
    END AS has_city_group_share_1,
    CASE
        WHEN has_city_group_share_2 = 'Sim' THEN true
        WHEN has_city_group_share_2 = 'Não' THEN false
        ELSE NULL
    END AS has_city_group_share_2,
    CASE
        WHEN has_cost_center_share = 'Sim' THEN true
        WHEN has_cost_center_share = 'Não' THEN false
        ELSE NULL
    END AS has_cost_center_share,
    TO_DATE(NULLIF(dt_invoice, ''), 'yyyy-M-d') AS dt_invoice,
    TO_DATE(NULLIF(dt_service_ended, ''), 'yyyy-M-d') AS dt_service_ended,
    TO_DATE(NULLIF(dt_service_started, ''), 'yyyy-M-d') AS dt_service_started,
    TO_TIMESTAMP(NULLIF(ts_entry, ''), 'yyyy-M-d HH:mm:ss') AS ts_entry
FROM
	datalake_gsheets_raw.offline_manual_costs;
