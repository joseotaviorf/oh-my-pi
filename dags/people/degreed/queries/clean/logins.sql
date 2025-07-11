SELECT
    id,
    relationships[0].user.data.id AS id_user,
    attributes.employee_id AS email_employee,
    TO_TIMESTAMP(attributes.logged_in_at) AS ts_logged,
    NOW() AS ts_load
FROM 
    datalake_degreed_raw.logins
WHERE 
    DATE(attributes.logged_in_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')