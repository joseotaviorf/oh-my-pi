WITH earnings AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.earnings
)

SELECT
    id,
    id_agency,
    id_program,
    id_external_domain,
    id_external_receiver,
    status,
    type,
    failure_count,
    details,
    remuneration_value,
    external_domain_type,
    external_receiver_type,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    earnings
WHERE
    row_n = 1
