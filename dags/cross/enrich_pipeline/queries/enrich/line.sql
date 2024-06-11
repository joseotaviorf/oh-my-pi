WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY MIN(ts_event) ASC) AS id_line,
        REPLACE(REPLACE(owners, 'airflow, ', ''), ', airflow', '') AS line_name,
        MIN(ts_event) AS ts_line_first_event
    FROM
        datalake_composer_clean.log AS l
    JOIN
        datalake_composer_clean.dag AS d
            ON d.id_dag = l.id_dag
            AND d.id_dag LIKE 'bietlejuice%'
    GROUP BY 2
)
SELECT
    id_line,
    line_name,
    IF(line_name LIKE 'Data%', TRUE, FALSE) AS is_data_line,
    TIMESTAMP(ts_line_first_event) AS ts_line_first_event
FROM
    base