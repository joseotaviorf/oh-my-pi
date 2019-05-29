with t_rows as (
SELECT count(1) as total_rows FROM datalake_raw.{table_name}
WHERE dt = '{date}' AND acc = '{account}'
UNION ALL
SELECT count(1) * -1 as total_rows FROM datalake_clean.{table_name}
WHERE dt_created = '{date}' AND acc = '{account}'
)
select sum(total_rows) >= 0
as validation_result
from t_rows