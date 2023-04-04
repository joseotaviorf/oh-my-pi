SELECT
    Id AS id_info_status,
    Description AS description,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.Info_StatusId
WHERE
    DATE(CONCAT(year,'-',month,'-',day)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')