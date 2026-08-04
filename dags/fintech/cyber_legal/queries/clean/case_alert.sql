WITH ranked AS (
    SELECT
        ALID AS id_alert,
        ALCASENO AS id_case,
        ALCOLLID AS id_generating_attorney,
        ALREVCOL AS id_revising_attorney,
        ALALERTTP AS alert_type_code,
        ALDESC AS alert_comment,
        ALCREATOR AS alert_creator,
        IF(ALSTATUS = 'Y', TRUE, FALSE) AS is_reviewed,
        ALCREDT AS dt_created,
        ALREVDT AS dt_reviewed,
        ALALERTDT AS dt_alert_expired,
        ALDTUPD AS ts_updated,
        year,
        month,
        day,
        NOW() AS ts_load,
        ROW_NUMBER() OVER(PARTITION BY ALID ORDER BY MAKE_DATE(year,month,day) DESC) AS rn
    FROM datalake_cyber_legal_raw.caalert
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_alert,
    id_case,
    id_generating_attorney,
    id_revising_attorney,
    alert_type_code,
    alert_comment,
    alert_creator,
    is_reviewed,
    dt_created,
    dt_reviewed,
    dt_alert_expired,
    ts_updated,
    year,
    month,
    day,
    ts_load
FROM
    ranked
WHERE
    rn = 1
