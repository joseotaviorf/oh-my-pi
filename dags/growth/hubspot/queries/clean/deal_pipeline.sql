SELECT
    id AS id_pipeline,
    label,
    -- stages.created_at/archived_at/updated_at are stored as strings in raw (see
    -- load_hubspot_raw.py) to dodge the OpenX SerDe's strict nested-timestamp parser.
    -- Cast back to timestamp here with Spark's own lenient parser, which accepts both
    -- historical formats (offset "+00:00" and "Z"-suffixed ISO-8601).
    transform(
        stages,
        stage -> named_struct(
            'label', stage.label,
            'display_order', stage.display_order,
            'metadata', stage.metadata,
            'id', stage.id,
            'created_at', CAST(stage.created_at AS TIMESTAMP),
            'archived_at', CAST(stage.archived_at AS TIMESTAMP),
            'updated_at', CAST(stage.updated_at AS TIMESTAMP),
            'archived', stage.archived
        )
    ) AS stages,
    display_order,
    archived AS is_archived,
    archived_at AS ts_archived,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_raw.deal_pipeline
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}