SELECT
    content_item_id AS id_content_item,
    business_group_id AS id_business_group,
    language,
    source_lang AS source_language,
    name,
    item_description,
    created_by,
    last_updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_ended,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_talent_raw.hrt_content_items_tl