SELECT
    device_id AS id_device,
    serial_number AS ds_serial_number,
    udid AS id_udid,
    device_name AS nm_device,
    model AS nm_model,
    platform AS ds_platform,
    os_version AS ds_os_version,
    supplemental_build_version AS ds_supplemental_build_version,
    blueprint_id AS id_blueprint,
    blueprint_name AS nm_blueprint,
    asset_tag AS ds_asset_tag,
    user.id AS id_user,
    user.name AS nm_user,
    user.email AS ds_user_email,
    user.is_archived AS is_user_archived,
    user.active AS is_user_active,
    agent_version AS ds_agent_version,
    lost_mode_status AS ds_lost_mode_status,
    mdm_enabled AS is_mdm_enabled,
    agent_installed AS is_agent_installed,
    is_missing AS is_missing,
    is_removed AS is_removed,
    TRY_CAST(first_enrollment AS TIMESTAMP) AS ts_first_enrollment,
    TRY_CAST(last_enrollment AS TIMESTAMP) AS ts_last_enrollment,
    TRY_CAST(last_check_in AS TIMESTAMP) AS ts_last_check_in,
    year,
    month,
    day
FROM
    datalake_iru_raw.managed_devices
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
