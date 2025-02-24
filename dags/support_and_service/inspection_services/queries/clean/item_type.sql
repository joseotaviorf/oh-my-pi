SELECT
    id AS id_item_type,
    item_group_type_id AS id_item_group_type,
    display_type,
    media_type,
    type,
    order AS number_order,
    allow_comments AS is_allow_comments,
    allow_media AS is_allow_media,
    deleted AS is_deleted,
    show_label AS is_show_label,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_type
