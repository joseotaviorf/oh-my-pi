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
    NOW() AS ts_load
FROM datalake_cyber_legal_homolog_raw.caalert
