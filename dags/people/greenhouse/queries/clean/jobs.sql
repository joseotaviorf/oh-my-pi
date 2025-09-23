SELECT
    -- ids
    id,
    copied_from_id AS id_copied_from,
    requisition_id AS id_requisition,
    departments[0].id AS id_department,
    FILTER(
      hiring_team.recruiters,
      r -> r.responsible IS TRUE
    ) [0].id AS id_recruiter_responsible,
    FILTER(
      hiring_team.coordinators,
      c -> c.responsible IS TRUE
    ) [0].id AS id_coordinator_responsible,
    -- text fields
    name,
    status,
    keyed_custom_fields.internal_position_name___quinto_andar_sp.value AS internal_job_name,
    keyed_custom_fields.band.value AS band,
    keyed_custom_fields.career_path.value AS career_path,
    keyed_custom_fields.salary_scale.value AS salary_table,
    keyed_custom_fields.affirmative_focus.value AS affirmative_focus,
    keyed_custom_fields.company.value AS company,
    keyed_custom_fields.l1.value AS l1_full_name,
    keyed_custom_fields.workplace.value AS workplace,
    keyed_custom_fields.careers_page_area_of_interest.value AS careers_page_area,
    keyed_custom_fields.employment_type.value AS employment_type,
    keyed_custom_fields.work_hours.value AS work_hours,
    notes,
    keyed_custom_fields.monthly_salary_range.value.unit AS salary_range_currency,
    keyed_custom_fields.plr.value.unit AS plr_currency,
    keyed_custom_fields.rvv.value.unit AS rvv_currency,
    keyed_custom_fields.sop.value.unit AS sop_currency,
    -- numeric
    CAST(keyed_custom_fields.equity_options_approval_exception_range.value.min_value AS FLOAT) AS equity_options_min,
    CAST(keyed_custom_fields.equity_options_approval_exception_range.value.max_value AS FLOAT) AS equity_options_max,
    CAST(keyed_custom_fields.monthly_salary_range.value.min_value AS FLOAT) AS salary_range_min,
    CAST(keyed_custom_fields.monthly_salary_range.value.max_value AS FLOAT) AS salary_range_max,
    CAST(keyed_custom_fields.plr.value.value AS BIGINT) AS plr,
    CAST(keyed_custom_fields.rvv.value.value AS BIGINT) AS rvv,
    CAST(keyed_custom_fields.sop.value.value AS BIGINT) AS sop,
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
    TRANSFORM(
      offices,
      o -> struct(
        o.id,
        o.name,
        o.location.name AS location
      )
    ) AS offices,
    TRANSFORM(
      departments,
      d -> struct(
        d.id,
        d.name,
        d.external_id AS code
      )
    ) AS departments,
    TRANSFORM(
      hiring_team.hiring_managers,
      hm -> struct(
        hm.id,
        hm.employee_id AS id_employee,
        hm.name
      )
    ) AS hiring_managers,
    TRANSFORM(
      hiring_team.recruiters,
      r -> struct(
        r.id,
        r.employee_id AS id_employee,
        r.name,
        r.responsible AS is_responsible
      )
    ) AS recruiters,
    TRANSFORM(
      hiring_team.coordinators,
      c -> struct(
        c.id,
        c.employee_id AS id_employee,
        c.name,
        c.responsible AS is_responsible
      )
    ) AS coordinators,
    hiring_team.sourcers AS sourcers,
    openings,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.jobs