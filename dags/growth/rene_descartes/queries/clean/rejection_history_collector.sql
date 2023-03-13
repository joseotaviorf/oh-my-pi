SELECT
    id,
    phone AS phone_number,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rene_descartes_raw.rejection_history_collector
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY dt DESC) = 1    