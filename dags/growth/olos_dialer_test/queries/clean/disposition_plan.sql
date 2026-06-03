SELECT
    DispositionPlanId AS id_disposition_plan,
    LastModifiedUserId AS id_last_modified_user,
    Description AS description,
    Activated AS is_activated,
    LastModified AS ts_last_modified,
    year,
    month,
    day
FROM
    datalake_olos_dialer_test_raw.DispositionPlan
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')