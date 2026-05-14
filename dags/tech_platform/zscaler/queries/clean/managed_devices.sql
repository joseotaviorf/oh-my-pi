SELECT
    TRIM(udid) AS id_device,
    macAddress AS ds_mac_address,
    machineHostname AS nm_hostname,
    user AS ds_user_email,
    owner AS nm_owner,
    detail AS nm_device_model,
    manufacturer AS nm_manufacturer,
    osVersion AS ds_os_version,
    agentVersion AS ds_agent_version,
    policyName AS nm_policy,
    companyName AS nm_company,
    registrationState AS ds_registration_state,
    type AS cd_device_type,
    state AS cd_device_state,
    vpnState AS cd_vpn_state,
    tunnelVersion AS ds_tunnel_version,
    zappArch AS ds_architecture,
    hardwareFingerprint AS ds_hardware_fingerprint,
    download_count AS qt_download_count,
    TRY_CAST(FROM_UNIXTIME(CAST(registration_time AS BIGINT)) AS TIMESTAMP) AS ts_registration,
    TRY_CAST(FROM_UNIXTIME(CAST(last_seen_time AS BIGINT)) AS TIMESTAMP) AS ts_last_seen,
    TRY_CAST(FROM_UNIXTIME(CAST(config_download_time AS BIGINT)) AS TIMESTAMP) AS ts_config_download,
    TRY_CAST(FROM_UNIXTIME(CAST(keepAliveTime AS BIGINT)) AS TIMESTAMP) AS ts_keep_alive,
    year,
    month,
    day
FROM
    datalake_zscaler_raw.managed_devices
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            year,
            month,
            day,
            TRIM(udid)
        ORDER BY
            TRY_CAST(last_seen_time AS BIGINT) DESC NULLS LAST,
            TRY_CAST(machineHostname AS STRING) ASC NULLS LAST
    ) = 1
