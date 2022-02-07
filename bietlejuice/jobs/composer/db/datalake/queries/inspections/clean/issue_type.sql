SELECT
    id,
    item_type_id AS id_item_type,
    inspection_type,
    protected,
    repair_suggestion,
    responsibility,
    severity,
    type,
    enabled,
    require_manual_analysis,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_inspections_raw.issue_type