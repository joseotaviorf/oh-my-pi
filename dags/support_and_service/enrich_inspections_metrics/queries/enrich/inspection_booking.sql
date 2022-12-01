WITH contract_termination AS (
    SELECT
        ct.id_contract,
        ct.id_region,
        ct.dt_contract_entrance AS dt_contract_entrance,
        ct.dt_termination AS dt_contract_termination,
        ct.ts_canceled AS ts_termination_canceled
    FROM
        datalake_offboarding.contract_termination AS ct
    QUALIFY
        ct.ts_updated = FIRST(ct.ts_updated) OVER (PARTITION BY ct.id_contract ORDER BY ct.ts_updated DESC)
)
SELECT DISTINCT
    i.id_inspection,
    i.id_external,
    i.id_assessment,
    i.id_booking,
    i.id_contract,
    b.id_country,
    COALESCE(r.id_city, i.id_city) AS id_city,
    COALESCE(r.city_name, i.city_name) AS city_name,
    b.country_code,
    i.inspection_type,
    b.type AS booking_type,
    i.source,
    i.assessment_source,
    i.status,
    i.has_owner_accompanying,
    i.is_first_schedule,
    i.is_executed_in_first_schedule,
    CASE
        WHEN DATE(b.ts_first_canceled_unevaluated) = DATE(b.ts_booking_utc) THEN True
        ELSE False
    END AS is_d0_canceled,
    CASE
        WHEN DATE(b.ts_first_canceled_unevaluated) = DATE_SUB(DATE(b.ts_booking_utc), 1) THEN True
        ELSE False
    END AS is_d1_canceled,
    ct.dt_contract_entrance,
    ct.dt_contract_termination,
    CASE
      WHEN i.inspection_type = "offboarding" THEN ct.dt_contract_termination
      WHEN i.inspection_type = "onboarding" THEN ct.dt_contract_entrance
    END AS dt_execution_limit,
    b.ts_booking_utc AS ts_booking_inspected_utc,
    b.ts_booking_local_tz AS ts_booking_inspected_local_tz,
    b.ts_first_canceled_unevaluated AS ts_booking_cancelled_utc,
    b.ts_first_canceled_unevaluated_local_tz AS ts_booking_cancelled_local_tz,
    ct.ts_termination_canceled,
    i.ts_execution_started,
    i.ts_execution_finished,
    i.ts_inspected,
    i.ts_created,
    i.ts_updated
FROM
    datalake_inspections.inspection_history AS i
LEFT JOIN
    datalake_booking.booking AS b
        ON i.id_booking = b.id
LEFT JOIN
    contract_termination AS ct
        ON ct.id_contract = i.id_contract
LEFT JOIN
    datalake_region.region AS r
        ON r.id = ct.id_region
