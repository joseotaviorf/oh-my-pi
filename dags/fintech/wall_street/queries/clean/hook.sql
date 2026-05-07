SELECT
    id,
    entityId AS id_entity,
    entityType AS entity_type,
    type AS hook_type,
    status,
    numberOfAttempts AS number_of_attempts,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(firstAttemptAt AS TIMESTAMP) AS ts_first_attempt,
    CAST(lastAttemptAt AS TIMESTAMP) AS ts_last_attempt
FROM
    datalake_wall_street_raw.hook
