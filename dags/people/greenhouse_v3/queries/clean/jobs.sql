SELECT
    -- ids
    id AS id_job,
    copied_from_id AS id_copied_from,
    requisition_id AS id_requisition,
    department_id AS id_department,
    -- text fields
    name,
    status,
    custom_fields.career_path.value AS career_path,
    custom_fields.l1.value AS l1_full_name,
    custom_fields.careers_page_area_of_interest.value AS careers_page_area,
    custom_fields.employment_type.value AS employment_type,
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
    office_ids,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.jobs
