SELECT
    id,
    owner_id AS id_owner,
    priority_listing_status_id AS id_priority_listing_status,
    main_property_id AS id_main_property,
    version,
    processed_events,
    rent_context,
    sale_context,
    visit,
    photo_job,
    address,
    cover_image,
    house_type,
    access_type,
    priority_context,
    lead_id AS id_lead,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_property
