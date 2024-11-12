select
    business_context,
    dimension_name,
    dimension_value,
    agg_id,
    metric_name,
    metric_numerator,
    metric_denominator,
    metric_value,
    date_granularity,
    date
from
  datalake_search_metrics_service_raw.search_metrics
where MAKE_DATE(year, month, day) = DATE_ADD(MAKE_DATE({year}, {month}, {day}), 1)
