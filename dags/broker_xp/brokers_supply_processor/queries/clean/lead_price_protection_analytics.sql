SELECT
    id AS id_lead_price_protection_analytics,
    lead_id AS id_lead,
    business_context,
    main_price,
    brokerage_price,
    protection_reason,
    occurrence_count,
    first_occurred_at AS ts_first_occurred,
    last_occurred_at AS ts_last_occurred,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.lead_price_protection_analytics
