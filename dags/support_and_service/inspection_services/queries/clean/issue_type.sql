SELECT
    id AS id_issue_type,
    item_type_id AS id_item_type,
    inspection_type,
    repair_suggestion,
    responsibility,
    severity,
    type,
    require_manual_analysis,
    order AS number_order,
    enabled AS is_enabled,
    protected AS is_protected,
    deleted AS is_deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.issue_type
