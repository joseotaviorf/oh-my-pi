SELECT 
    email_address AS experiment_owner_email,
    experiment_name,
    line AS line_owner,
    squad AS squad_owner,
    experiment_type,
    user_property_on_amplitude AS amplitude_tag,
    hypothesis,
    success_metric,
    experiment_link,
    TO_DATE(expected_start_date, 'MM/dd/yyyy') AS dt_expected_start,
    TO_DATE(expected_end_date, 'MM/dd/yyyy') AS dt_expected_end,
    TO_TIMESTAMP(timestamp, 'MM/dd/yyyy HH:mm:ss') AS ts_created
FROM
    datalake_gsheets_raw.experiments_catalog