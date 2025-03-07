WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY MIN(ts_event) ASC) AS id_line,
        REPLACE(REPLACE(owners, 'airflow, ', ''), ', airflow', '') AS line_name,
        MIN(ts_event) AS ts_line_first_event
    FROM
        datalake_airflow.log AS l
    JOIN
        datalake_airflow.dag AS d
            ON d.id_dag = l.id_dag
            AND d.id_dag LIKE 'bietlejuice%'
    GROUP BY 2
)
SELECT
    id_line,
    line_name,
    IF(line_name IN ('Data ForRent', 'Data Growth', 'Data Fintech', 'Data Rede', 'Data ForSale', 'Data SS',
        'Data Engineering', 'Data Agents', 'Data Bedrock', 'Data International', 'Data People'), TRUE, FALSE) AS is_data_line,
    TIMESTAMP(ts_line_first_event) AS ts_line_first_event
FROM
    base