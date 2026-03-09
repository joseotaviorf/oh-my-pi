SELECT 
    dag_run_id as id_run,
    event_id as id_event,
    year,
    month,
    day
from datalake_astro_raw.dagrun_dataset_event