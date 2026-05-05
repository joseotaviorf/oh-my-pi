WITH deduped_time_requests AS (
    SELECT
        id_request,
        id_employee_profile,
        id_request_subtype,
        approval_status,
        approval_stage,
        approval_flow,
        request_type,
        request_subtype_state,
        hours_calculation_type,
        is_all_day,
        is_paid_request,
        is_locked,
        is_endless,
        is_night_shift,
        is_up_to_date,
        ts_interval_started,
        ts_interval_ended,
        ts_created,
        ts_updated,
        ts_deleted,
        ts_synced,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_oitchau_clean.requests
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_request
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) = 1
),
employee_registration AS (
    SELECT
        id_employee_profile,
        registration_code,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_oitchau_clean.employees
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_employee_profile
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) = 1
),
time_requests_with_person AS (
    SELECT
        rq.id_request,
        rq.id_request_subtype,
        rq.approval_status,
        rq.approval_stage,
        rq.approval_flow,
        rq.request_type,
        rq.request_subtype_state,
        rq.hours_calculation_type,
        rq.is_all_day,
        rq.is_paid_request,
        rq.is_locked,
        rq.is_endless,
        rq.is_night_shift,
        rq.is_up_to_date,
        rq.ts_interval_started,
        rq.ts_interval_ended,
        rq.ts_created,
        rq.ts_updated,
        rq.ts_deleted,
        rq.ts_synced,
        XXHASH64(
            TRIM(CAST(rq.id_request AS STRING))
        ) AS sk_time_request,
        XXHASH64(
            TRIM(CAST(rq.id_request_subtype AS STRING))
        ) AS sk_request_raw,
        im.id_person AS sk_employee,
        im.person_number
    FROM
        deduped_time_requests AS rq
    INNER JOIN
        employee_registration AS er
            ON er.id_employee_profile = rq.id_employee_profile
    INNER JOIN
        datalake_people.identifier_mapping AS im
            ON TRIM(CAST(er.registration_code AS STRING)) = TRIM(CAST(im.person_number AS STRING))
            AND NOT im.is_user_test
            AND im.is_person_latest_assignment
    WHERE
        rq.id_request IS NOT NULL
        AND TRIM(CAST(rq.id_request AS STRING)) <> ''
        AND rq.id_request_subtype IS NOT NULL
)
SELECT
    rm.sk_time_request,
    rm.sk_employee,
    COALESCE(dr.sk_request, rm.sk_request_raw) AS sk_request,
    TRIM(CAST(rm.id_request AS STRING)) AS id_request,
    rm.person_number,
    rm.approval_status,
    rm.approval_stage,
    rm.request_type,
    rm.hours_calculation_type,
    rm.is_all_day,
    rm.is_paid_request,
    rm.is_locked,
    rm.is_endless,
    rm.is_night_shift,
    rm.is_up_to_date,
    rm.ts_interval_started,
    rm.ts_interval_ended,
    DATE(rm.ts_created) AS dt_created,
    DATE(rm.ts_updated) AS dt_updated,
    rm.ts_created,
    rm.ts_updated,
    rm.ts_deleted,
    rm.ts_synced,
    TO_JSON(rm.approval_flow) AS approval_flow,
    TO_JSON(rm.request_subtype_state) AS request_subtype_state,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    time_requests_with_person AS rm
LEFT JOIN
    dw_time.dim_request AS dr
        ON rm.sk_request_raw = dr.sk_request
