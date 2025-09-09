SELECT
    -- ids
    id,
    copied_from_id AS id_copied_from,
    requisition_id AS id_requisition,
    -- text fields
    name,
    status,
    notes,
    keyed_custom_fields.band.value AS band,
    keyed_custom_fields.company.value AS company,
    keyed_custom_fields.employment_type.value AS employment_type,
    keyed_custom_fields.monthly_salary_range.value.min_value AS salary_range_min,
    keyed_custom_fields.monthly_salary_range.value.max_value AS salary_range_max,
    keyed_custom_fields.monthly_salary_range.value.unit AS salary_range_currency,
    -- boolean
    CAST(confidential AS BOOLEAN) AS is_confidential,
    CAST(is_template AS BOOLEAN) AS is_template,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(opened_at AS TIMESTAMP) AS ts_opened,
    CAST(closed_at AS TIMESTAMP) AS ts_closed,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- arrays
    departments,
    TRANSFORM(
        offices,
        o -> STRUCT(
            o.id,
            o.name,
            o.location,
            o.parent_id,
            o.parent_office_external_id,
            o.child_ids,
            o.child_office_external_ids,
            o.external_id
        )
    ) AS offices,
    TRANSFORM(
        hiring_team.hiring_managers,
        hm -> STRUCT(
            hm.id,
            hm.first_name,
            hm.last_name,
            hm.name
        )
    ) AS hiring_managers,
    TRANSFORM(
        hiring_team.recruiters,
        r -> STRUCT(
            r.id,
            r.first_name,
            r.last_name,
            r.name,
            r.responsible
        )
    ) AS recruiters,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.jobs
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1