SELECT
    MD5(id_task, step_name) AS sk_interaction,
    MD5(id_task) AS sk_task,
    from_phone_number,
    to_phone_number,
    step_name,
    type,
    value,
    ts_event,
    ts_ivr_started
FROM
    datalake_customer_support_test.ivr_interactions
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
