SELECT
    id AS id_budget,
    inspection_id AS id_inspection,
    uuid,
    owner_approval_comment,
    tenant_approval_comment,
    owner_approval_reason,
    tenant_approval_reason,
    owner_approved_by,
    tenant_approved_by,
    owner_approved,
    tenant_approved,
    total_cost,
    owner_amount_payment,
    tenant_amount_payment,
    owner_approved_date AS dt_owner_approved,
    tenant_approved_date AS dt_tenant_approved,
    owner_deadline_date AS dt_owner_dead_line,
    tenant_deadline_date AS dt_tenant_dead_line,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.budget
WHERE
	year = {year}
	AND month = {month}
	AND day = {day}
