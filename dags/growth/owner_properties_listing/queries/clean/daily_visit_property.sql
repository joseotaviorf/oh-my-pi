SELECT
    id,
    property_id AS id_property,
    scheduled_to AS dt_scheduled,
    confirmed_count,
    waiting_confirmation_count,
    canceled_count,
    concluded_count,
    visits,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_daily_visit_property
