-- transactional scopes incremental reloads: CDC filters op_cdc = 'd', hiding hard deletes
WITH updated_agent_data AS (
    SELECT
        DadosAgente_id AS id_agent_data
    FROM
        datalake_ebdb_transactional.dadosagente_tipos
    WHERE
        DATE(ts_database_transaction) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_data_types AS (
    SELECT
        aud.id_agent_data,
        aud.rev,
        aud.rev_type,
        aud.types,
        CAST(rev.ts_revision / 1000 AS TIMESTAMP) AS ts_revision
    FROM
        updated_agent_data AS updated
    JOIN
        datalake_ebdb_clean.agent_data_types_aud AS aud
            ON updated.id_agent_data = aud.id_agent_data
    JOIN
        datalake_ebdb_clean.user_revision_entity AS rev
            ON rev.id = aud.rev 
),
types_history AS (
    SELECT
        types.id_agent_data,
        types.types,
        deleted.ts_revision IS NULL AS is_active,
        IF(
            deleted.ts_revision IS NULL,
            TRUE,
            ROW_NUMBER() OVER(PARTITION BY types.id_agent_data, types.types, deleted.ts_revision ORDER BY types.ts_revision DESC) = 1
        ) AS is_dedup_row,
        types.ts_revision AS ts_started,
        deleted.ts_revision AS ts_ended
    FROM
        agent_data_types AS types
    LEFT JOIN
        agent_data_types AS deleted
            ON deleted.id_agent_data = types.id_agent_data
            AND deleted.types = types.types
            AND deleted.rev_type = 2
            AND deleted.ts_revision > types.ts_revision
    WHERE
        types.rev_type <> 2
),
dedup_start_exceptions AS (
    SELECT
        types.id_agent_data,
        types.types,
        types.is_active,
        ROW_NUMBER() OVER(PARTITION BY types.id_agent_data, types.types, types.ts_started ORDER BY types.ts_ended DESC) = 1 AS is_dedup_start_exceptions,
        types.ts_started,
        types.ts_ended
    FROM
        types_history AS types
    WHERE
        types.is_dedup_row IS TRUE
),
dedup_deletion_history AS (
    SELECT
        types.id_agent_data,
        types.types,
        types.is_active,
        ROW_NUMBER() OVER(PARTITION BY types.id_agent_data, types.types ORDER BY types.ts_started DESC) = 1 AS is_lastest_by_type,
        types.ts_started,
        types.ts_ended
    FROM
        dedup_start_exceptions AS types
    WHERE
        types.is_dedup_start_exceptions IS TRUE
),
fix_audit_error AS (
    SELECT
        types.id_agent_data,
        types.types,
        current_.id_agent_data IS NOT NULL AS is_active,
        types.is_active IS FALSE AND current_.id_agent_data IS NOT NULL AS has_aud_divergence,
        types.ts_started,
        types.ts_ended
    FROM
        dedup_deletion_history AS types
    LEFT JOIN
        datalake_ebdb_clean.agent_data_types AS current_
            ON current_.id_agent_data = types.id_agent_data
            AND current_.types = types.types
    UNION
    SELECT
        current_.id_agent_data,
        current_.types,
        TRUE AS is_active,
        TRUE AS has_aud_divergence,
        current_.ts_database_transaction AS ts_started,
        NULL AS ts_ended
    FROM
        updated_agent_data AS updated
    JOIN
        datalake_ebdb_clean.agent_data_types AS current_
            ON current_.id_agent_data = updated.id_agent_data
    LEFT JOIN
        dedup_deletion_history AS types
            ON current_.id_agent_data = types.id_agent_data
            AND current_.types = types.types
            AND types.is_lastest_by_type IS TRUE
    WHERE
        types.id_agent_data IS NULL
)
SELECT
    XXHASH64(id_agent_data, types, ts_started) AS id_agent_profile,
    id_agent_data,
    types AS profile,
    has_aud_divergence,
    is_active,
    ROW_NUMBER() OVER(PARTITION BY id_agent_data, DATE(ts_started) ORDER BY ts_started DESC) = 1 AS is_lastest_by_date,
    ts_started AS ts_revision_started,
    IF( 
        is_active IS FALSE AND ts_ended IS NULL,
        LEAD(ts_started) OVER(PARTITION BY id_agent_data ORDER BY ts_started),
        ts_ended
    ) AS ts_revision_ended
FROM
    fix_audit_error