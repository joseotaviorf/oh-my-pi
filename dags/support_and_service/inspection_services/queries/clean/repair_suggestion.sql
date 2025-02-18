SELECT
    id,
    service,
    type,
    responsibility,
    exempted AS is_exempted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.repair_suggestion
