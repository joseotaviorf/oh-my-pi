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
    expected_start_date AS dt_expected_start,
    expected_end_date AS dt_expected_end,
    timestamp AS ts_created
FROM
    datalake_gsheets_raw.experiments_catalog