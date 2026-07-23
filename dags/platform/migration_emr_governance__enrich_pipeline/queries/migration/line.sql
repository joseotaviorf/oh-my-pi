WITH base AS (
    SELECT
        REPLACE(REPLACE(owners, 'airflow, ', ''), ', airflow', '') AS line_name,
        MIN(ts_event) AS ts_line_first_event
    FROM
        datalake_airflow.log AS l
    JOIN
        datalake_airflow.dag AS d
            ON d.id_dag = l.id_dag
            AND d.id_dag LIKE 'bietlejuice%'
    GROUP BY 
        line_name
)
SELECT
    MD5(line_name) AS id_line,
    line_name,
    line_name IN (
        'Data 3P Partners',
        'Data Agents',
        'Data Engineering',
        'Data Fintech',
        'Data ForRent',
        'Data ForSale',
        'Data Growth',
        'Data People',
        'Data Primitives',
        'Data SS'
    ) AS is_data_line,
    TIMESTAMP(ts_line_first_event) AS ts_line_first_event
FROM
    base