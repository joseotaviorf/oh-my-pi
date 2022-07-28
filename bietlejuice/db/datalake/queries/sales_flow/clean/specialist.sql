SELECT
    id AS id_specialist,
    sales_flow_id AS id_sales_flow,
    main_user_id AS id_main_user,
    kind,
    email,
    name AS specialist_name,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.specialist
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}