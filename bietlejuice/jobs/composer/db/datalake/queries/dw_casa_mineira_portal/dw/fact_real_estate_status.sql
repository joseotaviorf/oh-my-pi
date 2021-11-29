SELECT
    CAST(id_real_estate_agency AS INT) AS sk_real_estate_agency,
    COALESCE(INT(DATE_FORMAT(dt_consider_status_started, 'yyyyMMdd')), -1) AS sk_consider_status_started_date,
    COALESCE(INT(DATE_FORMAT(dt_consider_status_ended, 'yyyyMMdd')), -1) AS sk_consider_status_ended_date,
    status,
    dt_consider_status_started,
    dt_consider_status_ended,
    NOW() AS ts_load
FROM datalake_casa_mineira_portal.real_estate_status