SELECT
    sk_exp_visit_metric,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    business_context,
    metric_cohort,
    metric_name,
    control_metric_value,
    control_metric_error,
    treatment_metric_value,
    treatment_metric_error,
    dt_ref,
    YEAR(dt_ref) AS year,
    MONTH(dt_ref) AS month,
    DAY(dt_ref) AS day
FROM
    metric_sale.exp_visit_metric_conversion_inc
WHERE
    dt_ref BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL
SELECT
    sk_exp_visit_metric,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    business_context,
    metric_cohort,
    metric_name,
    control_metric_value,
    control_metric_error,
    treatment_metric_value,
    treatment_metric_error,
    dt_ref,
    YEAR(dt_ref) AS year,
    MONTH(dt_ref) AS month,
    DAY(dt_ref) AS day
FROM
    metric_sale.exp_visit_identifier_metric_inc
WHERE
    dt_ref BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
