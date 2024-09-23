SELECT
    id AS id_closing,
    started_by_user_id AS id_user_started,
    finished_by_user_id AS id_user_finished,
    conciliation_finished_by_user_id AS id_user_conciliation_finished,
    DATE(closing_date) AS dt_closing,
    TO_TIMESTAMP(initialized_at) AS ts_started,
    TO_TIMESTAMP(finished_at) AS ts_ended,
    TO_TIMESTAMP(conciliation_finished_at) AS ts_conciliation_ended
FROM
    datalake_atta_raw.closing
