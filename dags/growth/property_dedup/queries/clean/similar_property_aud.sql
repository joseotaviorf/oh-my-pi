SELECT
    id,
    property_id AS id_property,
    owner_id AS id_owner,
    address,
    context_ownership,
    context_property_status,
    is_same_property_owner,
    similarity_score,
    rev,
    revtype,
    revend,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_property_dedup_raw.similar_property_aud
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, rev ORDER BY dt DESC) = 1