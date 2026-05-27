SELECT
    id AS id_lead_property_change_tracking,
    lead_id AS id_lead,
    main_rent_price,
    main_sale_price,
    main_condo_price,
    last_bsp_rent_price,
    last_bsp_sale_price,
    last_sale_price_change_source,
    last_rent_price_change_source,
    sale_price_external_change_at AS ts_sale_price_external_change,
    rent_price_external_change_at AS ts_rent_price_external_change,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.lead_property_change_tracking
