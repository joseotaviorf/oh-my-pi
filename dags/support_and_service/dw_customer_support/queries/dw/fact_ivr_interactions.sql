SELECT
    MD5(
        CONCAT(
            id_task,
            step_name
        )
    ) AS sk_interaction,
    id_task AS sk_task,
    id_call AS sk_call,
    from_phone_number,
    to_phone_number,
    step_name,
    type,
    value,
    ts_event,
    ts_ivr_started
FROM
    datalake_customer_support.ivr_interactions
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
