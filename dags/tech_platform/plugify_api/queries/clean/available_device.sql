SELECT
    serial_number AS serial,
    description,
    stock_type,
    galipro AS is_galipro,
    DATE(begin_validity_date) AS dt_validity_started,
    DATE(end_validity_date) AS dt_validity_ended,
    ts_load,
    year,
    month,
    day
FROM
    datalake_plugify_raw.available_device
