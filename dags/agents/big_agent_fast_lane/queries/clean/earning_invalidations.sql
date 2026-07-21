SELECT
    id,
    earning_id AS id_earning,
    replaced_by AS id_replaced_by,
    GET_JSON_OBJECT(author, "$.id") AS id_author,
    reason,
    invalidation_description,
    author,
    GET_JSON_OBJECT(author, "$.role") AS author_role,
    GET_JSON_OBJECT(author, "$.channel") AS author_channel,
    GET_JSON_OBJECT(author, "$.on_behalf_of_role") AS author_on_behalf_of_role,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earning_invalidations