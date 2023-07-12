SELECT
    id,
    similar_property_id AS id_similar_property,
    duplicity_reason,
    action_type,
    rev,
    revtype,
    revend,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_property_dedup_raw.duplicity_output_aud
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, rev ORDER BY dt DESC) = 1