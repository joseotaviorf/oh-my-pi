select
    exp_name,
    execution_date,
    user_contamination_percentage,
    abs_contaminated_users,
    abs_users
from
  datalake_search_metrics_service_raw.experiment_contamination
