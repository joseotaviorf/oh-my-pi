SELECT
    id,
    sendbird_url,
    metadata,
    entity,
    entity_id as id_entity,
    active as is_active,
    created_at as ts_created,
    last_modified_at as ts_last_modified,
    created_by_id,
    finalized_at as ts_finalized,
    cast(tags as string) as tags,
    first_user_interaction_at as ts_first_user_interaction,
    first_other_user_interaction_at as ts_first_other_user_interaction,
    cast(last_contexts as string) as last_contexts
FROM
    datalake_linhadireta_test_raw.chat
