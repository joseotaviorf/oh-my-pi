SELECT
    city_group,
    payment_method,
    metric_name,
    metric_flux,
    INT(NULLIF(sla_target_backlog, '')) AS sla_target_backlog,
    INT(NULLIF(sla_target_202201, '')) AS sla_target_202201,
    INT(NULLIF(sla_target_202202, '')) AS sla_target_202202,
    INT(NULLIF(sla_target_202203, '')) AS sla_target_202203,
    INT(NULLIF(sla_target_202204, '')) AS sla_target_202204,
    INT(NULLIF(sla_target_202205, '')) AS sla_target_202205,
    INT(NULLIF(sla_target_202206, '')) AS sla_target_202206,
    INT(NULLIF(sla_target_202207, '')) AS sla_target_202207,
    INT(NULLIF(sla_target_202208, '')) AS sla_target_202208,
    INT(NULLIF(sla_target_202209, '')) AS sla_target_202209,
    INT(NULLIF(sla_target_202210, '')) AS sla_target_202210,
    INT(NULLIF(sla_target_202211, '')) AS sla_target_202211,
    INT(NULLIF(sla_target_202212, '')) AS sla_target_202212,
    BOOLEAN(NULLIF(has_used_fgts_in_payment, '')) AS has_used_fgts_in_payment,
    BOOLEAN(NULLIF(has_seller_debt_payments, '')) AS has_seller_debt_payments
FROM
    datalake_gsheets_raw.sale_closing_ops_targets
