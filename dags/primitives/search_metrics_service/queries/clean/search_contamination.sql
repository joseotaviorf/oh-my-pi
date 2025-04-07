select
    exp_name,
    date,
    user_contamination_percentange as user_contamination_percentage,
    users_who_swapped_ab as abs_contaminated_users,
    number_of_users as abs_users
from
  datalake_search_metrics_service_raw.search_contamination
