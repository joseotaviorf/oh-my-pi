WITH src_ranked AS (
    SELECT
        src.id_ticket,
        src.id_employee_plugify,
        src.ticket_type,
        src.status,
        src.schedule_status,
        src.cancellation_type,
        src.cancellation_description,
        src.requested_by_name,
        src.employee_name,
        src.delivery_serial,
        src.pickup_serial,
        src.delivery_tracking_number,
        src.pickup_tracking_number,
        src.is_kit_onboarding,
        src.dt_agreed,
        src.dt_contacted,
        src.ts_created,
        src.ts_updated,
        ROW_NUMBER() OVER (
            PARTITION BY
                src.id_ticket
            ORDER BY
                src.ts_load DESC NULLS LAST,
                src.year DESC,
                src.month DESC,
                src.day DESC
        ) AS rn_dedup
    FROM
        datalake_plugify_clean.ticket AS src
)
SELECT
    id_ticket,
    id_employee_plugify,
    ticket_type,
    status,
    schedule_status,
    cancellation_type,
    cancellation_description,
    requested_by_name,
    employee_name,
    delivery_serial,
    pickup_serial,
    delivery_tracking_number,
    pickup_tracking_number,
    is_kit_onboarding,
    dt_agreed,
    dt_contacted,
    ts_created,
    ts_updated,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    src_ranked
WHERE
    rn_dedup = 1
