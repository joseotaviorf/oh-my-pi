SELECT
    do.id AS id_duplicity,
    sp.id_property AS id_house,
    sp.id_owner,
    do.action_type,
    do.duplicity_reason,
    sp.is_same_property_owner,
    do.ts_created AS ts_action,
    sp.ts_created,
    sp.ts_updated
FROM
    datalake_property_dedup_clean.similar_property AS sp
JOIN
    datalake_property_dedup_clean.duplicity_output AS do
        ON sp.id = do.id_similar_property