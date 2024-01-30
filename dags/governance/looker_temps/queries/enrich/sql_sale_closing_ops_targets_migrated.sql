WITH modified_pm AS (
  SELECT
    sk_offer,
    CASE
      WHEN payment_method LIKE '%CASH%'
      THEN 'CASH'
      WHEN payment_method LIKE '%FINANCED%'
      THEN 'FINANCED'
      ELSE payment_method
    END AS payment_method
  FROM dw_sale.dim_sale_agreement
), cte_MA AS (
  SELECT
    dim_sale_agreement.sk_offer,
    sale_closing_ops_targets.metric_name,
    metric_flux,
    dim_region.city_group,
    dim_sale_agreement.payment_method,
    dim_sale_agreement.has_used_fgts_in_payment,
    dim_sale_agreement.has_seller_debt_payments,
    TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') AS dt_sale_agreement_signed_date,
    CASE
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-01-01')
      THEN sla_target_backlog
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-02-01')
      THEN sla_target_202201
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-03-01')
      THEN sla_target_202202
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-04-01')
      THEN sla_target_202203
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-05-01')
      THEN sla_target_202204
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-06-01')
      THEN sla_target_202205
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-07-01')
      THEN sla_target_202206
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-08-01')
      THEN sla_target_202207
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-09-01')
      THEN sla_target_202208
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-10-01')
      THEN sla_target_202209
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-11-01')
      THEN sla_target_202210
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-12-01')
      THEN sla_target_202211
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2023-01-01')
      THEN sla_target_202212
      ELSE NULL
    END + COALESCE(sale_closing_ops_targets_extra_slas_tags.extra_sla_days, 0) AS sla_target_sale_agreement_signed_to_house_registry_ended,
    sale_closing_ops_targets_extra_slas_tags.extra_sla_days
  FROM dw_sale.dim_sale_agreement
  LEFT JOIN modified_pm AS mpm
    ON dim_sale_agreement.sk_offer = mpm.sk_offer
  JOIN dw_sale.fact_closing_flows
    ON dim_sale_agreement.sk_offer = fact_closing_flows.sk_offer
  JOIN dw_sale.fact_listings
    ON fact_closing_flows.sk_house = fact_listings.sk_house
  JOIN dw_public.dim_region
    ON fact_listings.sk_region = dim_region.sk_region
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets AS sale_closing_ops_targets
    ON dim_region.city_group = sale_closing_ops_targets.city_group
    AND LOWER(mpm.payment_method) = LOWER(sale_closing_ops_targets.payment_method)
    AND dim_sale_agreement.has_used_fgts_in_payment = sale_closing_ops_targets.has_used_fgts_in_payment
    AND dim_sale_agreement.has_seller_debt_payments = sale_closing_ops_targets.has_seller_debt_payments
    AND sale_closing_ops_targets.metric_flux = 'Sale Agreement Signed -> House Registry Ended'
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets_extra_slas_tags AS sale_closing_ops_targets_extra_slas_tags
    ON dim_sale_agreement.tags_from_salesflow LIKE CONCAT('%', sale_closing_ops_targets_extra_slas_tags.salesflow_tag, '%')
    AND sale_closing_ops_targets.metric_name = sale_closing_ops_targets_extra_slas_tags.metric_name
), cte_DD AS (
  SELECT
    dim_sale_agreement.sk_offer,
    sale_closing_ops_targets.metric_name,
    metric_flux,
    dim_region.city_group,
    dim_sale_agreement.payment_method,
    dim_sale_agreement.has_used_fgts_in_payment,
    dim_sale_agreement.has_seller_debt_payments,
    TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') AS dt_sale_agreement_signed,
    CASE
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-01-01')
      THEN sla_target_backlog
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-02-01')
      THEN sla_target_202201
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-03-01')
      THEN sla_target_202202
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-04-01')
      THEN sla_target_202203
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-05-01')
      THEN sla_target_202204
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-06-01')
      THEN sla_target_202205
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-07-01')
      THEN sla_target_202206
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-08-01')
      THEN sla_target_202207
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-09-01')
      THEN sla_target_202208
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-10-01')
      THEN sla_target_202209
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-11-01')
      THEN sla_target_202210
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-12-01')
      THEN sla_target_202211
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2023-01-01')
      THEN sla_target_202212
      ELSE NULL
    END + COALESCE(sale_closing_ops_targets_extra_slas_tags.extra_sla_days, 0) AS sla_target_sale_agreement_signed_to_legal_analysis_ended,
    sale_closing_ops_targets_extra_slas_tags.extra_sla_days
  FROM dw_sale.dim_sale_agreement
  LEFT JOIN modified_pm AS mpm
    ON dim_sale_agreement.sk_offer = mpm.sk_offer
  JOIN dw_sale.fact_closing_flows
    ON dim_sale_agreement.sk_offer = fact_closing_flows.sk_offer
  JOIN dw_sale.fact_listings
    ON fact_closing_flows.sk_house = fact_listings.sk_house
  JOIN dw_public.dim_region
    ON fact_listings.sk_region = dim_region.sk_region
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets
    ON dim_region.city_group = sale_closing_ops_targets.city_group
    AND LOWER(mpm.payment_method) = LOWER(sale_closing_ops_targets.payment_method)
    AND dim_sale_agreement.has_used_fgts_in_payment = sale_closing_ops_targets.has_used_fgts_in_payment
    AND dim_sale_agreement.has_seller_debt_payments = sale_closing_ops_targets.has_seller_debt_payments
    AND sale_closing_ops_targets.metric_flux = 'Sale Agreement Signed -> Legal Analysis Ended'
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets_extra_slas_tags AS sale_closing_ops_targets_extra_slas_tags
    ON dim_sale_agreement.tags_from_salesflow LIKE CONCAT('%', sale_closing_ops_targets_extra_slas_tags.salesflow_tag, '%')
    AND sale_closing_ops_targets.metric_name = sale_closing_ops_targets_extra_slas_tags.metric_name
), cte_CRN_End AS (
  SELECT
    dim_sale_agreement.sk_offer,
    sale_closing_ops_targets.metric_name,
    metric_flux,
    dim_region.city_group,
    dim_sale_agreement.payment_method,
    dim_sale_agreement.has_used_fgts_in_payment,
    dim_sale_agreement.has_seller_debt_payments,
    TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') AS dt_sale_agreement_signed,
    CASE
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-01-01')
      THEN sla_target_backlog
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-02-01')
      THEN sla_target_202201
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-03-01')
      THEN sla_target_202202
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-04-01')
      THEN sla_target_202203
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-05-01')
      THEN sla_target_202204
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-06-01')
      THEN sla_target_202205
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-07-01')
      THEN sla_target_202206
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-08-01')
      THEN sla_target_202207
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-09-01')
      THEN sla_target_202208
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-10-01')
      THEN sla_target_202209
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-11-01')
      THEN sla_target_202210
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-12-01')
      THEN sla_target_202211
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2023-01-01')
      THEN sla_target_202212
      ELSE NULL
    END + COALESCE(sale_closing_ops_targets_extra_slas_tags.extra_sla_days, 0) AS sla_target_sale_agreement_signed_to_notes_registry_ended,
    sale_closing_ops_targets_extra_slas_tags.extra_sla_days
  FROM dw_sale.dim_sale_agreement
  LEFT JOIN modified_pm AS mpm
    ON dim_sale_agreement.sk_offer = mpm.sk_offer
  JOIN dw_sale.fact_closing_flows
    ON dim_sale_agreement.sk_offer = fact_closing_flows.sk_offer
  JOIN dw_sale.fact_listings
    ON fact_closing_flows.sk_house = fact_listings.sk_house
  JOIN dw_public.dim_region
    ON fact_listings.sk_region = dim_region.sk_region
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets
    ON dim_region.city_group = sale_closing_ops_targets.city_group
    AND LOWER(mpm.payment_method) = LOWER(sale_closing_ops_targets.payment_method)
    AND dim_sale_agreement.has_used_fgts_in_payment = sale_closing_ops_targets.has_used_fgts_in_payment
    AND dim_sale_agreement.has_seller_debt_payments = sale_closing_ops_targets.has_seller_debt_payments
    AND sale_closing_ops_targets.metric_flux = 'Sale Agreement Signed -> Notes Registry Ended'
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets_extra_slas_tags AS sale_closing_ops_targets_extra_slas_tags
    ON dim_sale_agreement.tags_from_salesflow LIKE CONCAT('%', sale_closing_ops_targets_extra_slas_tags.salesflow_tag, '%')
    AND sale_closing_ops_targets.metric_name = sale_closing_ops_targets_extra_slas_tags.metric_name
), cte_CRI_Start_from_ccv AS (
  SELECT
    dim_sale_agreement.sk_offer,
    sale_closing_ops_targets.metric_name,
    metric_flux,
    dim_region.city_group,
    dim_sale_agreement.payment_method,
    dim_sale_agreement.has_used_fgts_in_payment,
    dim_sale_agreement.has_seller_debt_payments,
    TO_TIMESTAMP(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyyMMdd') AS dt_sale_agreement_signed,
    CASE
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-01-01')
      THEN sla_target_backlog
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-02-01')
      THEN sla_target_202201
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-03-01')
      THEN sla_target_202202
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-04-01')
      THEN sla_target_202203
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-05-01')
      THEN sla_target_202204
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-06-01')
      THEN sla_target_202205
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-07-01')
      THEN sla_target_202206
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-08-01')
      THEN sla_target_202207
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-09-01')
      THEN sla_target_202208
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-10-01')
      THEN sla_target_202209
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-11-01')
      THEN sla_target_202210
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-12-01')
      THEN sla_target_202211
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2023-01-01')
      THEN sla_target_202212
      ELSE NULL
    END + COALESCE(sale_closing_ops_targets_extra_slas_tags.extra_sla_days, 0) AS sla_target_sale_agreement_signed_to_house_registry_started,
    sale_closing_ops_targets_extra_slas_tags.extra_sla_days
  FROM dw_sale.dim_sale_agreement
  LEFT JOIN modified_pm AS mpm
    ON dim_sale_agreement.sk_offer = mpm.sk_offer
  JOIN dw_sale.fact_closing_flows
    ON dim_sale_agreement.sk_offer = fact_closing_flows.sk_offer
  JOIN dw_sale.fact_listings
    ON fact_closing_flows.sk_house = fact_listings.sk_house
  JOIN dw_public.dim_region
    ON fact_listings.sk_region = dim_region.sk_region
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets
    ON dim_region.city_group = sale_closing_ops_targets.city_group
    AND LOWER(mpm.payment_method) = LOWER(sale_closing_ops_targets.payment_method)
    AND dim_sale_agreement.has_used_fgts_in_payment = sale_closing_ops_targets.has_used_fgts_in_payment
    AND dim_sale_agreement.has_seller_debt_payments = sale_closing_ops_targets.has_seller_debt_payments
    AND sale_closing_ops_targets.metric_flux = 'Sale Agreement Signed -> House Registry Started'
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets_extra_slas_tags AS sale_closing_ops_targets_extra_slas_tags
    ON dim_sale_agreement.tags_from_salesflow LIKE CONCAT('%', sale_closing_ops_targets_extra_slas_tags.salesflow_tag, '%')
    AND sale_closing_ops_targets.metric_name = sale_closing_ops_targets_extra_slas_tags.metric_name
), cte_CRI_Start_from_bank_legal_analysis_started AS (
  SELECT
    dim_sale_agreement.sk_offer,
    sale_closing_ops_targets.metric_name,
    metric_flux,
    dim_region.city_group,
    dim_sale_agreement.payment_method,
    dim_sale_agreement.has_used_fgts_in_payment,
    dim_sale_agreement.has_seller_debt_payments,
    TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') AS dt_bank_legal_analysis_started,
    CASE
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-01-01')
      THEN sla_target_backlog
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-02-01')
      THEN sla_target_202201
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-03-01')
      THEN sla_target_202202
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-04-01')
      THEN sla_target_202203
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-05-01')
      THEN sla_target_202204
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-06-01')
      THEN sla_target_202205
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-07-01')
      THEN sla_target_202206
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-08-01')
      THEN sla_target_202207
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-09-01')
      THEN sla_target_202208
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-10-01')
      THEN sla_target_202209
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-11-01')
      THEN sla_target_202210
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2022-12-01')
      THEN sla_target_202211
      WHEN TO_DATE(CAST(NULLIF(sk_bank_legal_analysis_started, -1) AS STRING), 'yyyymmdd') < DATE('2023-01-01')
      THEN sla_target_202212
      ELSE NULL
    END + COALESCE(sale_closing_ops_targets_extra_slas_tags.extra_sla_days, 0) AS sla_target_bank_legal_analysis_started_to_house_registry_started,
    sale_closing_ops_targets_extra_slas_tags.extra_sla_days
  FROM dw_sale.dim_sale_agreement
  LEFT JOIN modified_pm AS mpm
    ON dim_sale_agreement.sk_offer = mpm.sk_offer
  JOIN dw_sale.fact_closing_flows
    ON dim_sale_agreement.sk_offer = fact_closing_flows.sk_offer
  JOIN dw_sale.fact_listings
    ON fact_closing_flows.sk_house = fact_listings.sk_house
  JOIN dw_public.dim_region
    ON fact_listings.sk_region = dim_region.sk_region
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets
    ON dim_region.city_group = sale_closing_ops_targets.city_group
    AND LOWER(mpm.payment_method) = LOWER(sale_closing_ops_targets.payment_method)
    AND dim_sale_agreement.has_used_fgts_in_payment = sale_closing_ops_targets.has_used_fgts_in_payment
    AND dim_sale_agreement.has_seller_debt_payments = sale_closing_ops_targets.has_seller_debt_payments
    AND sale_closing_ops_targets.metric_flux = 'Bank Legal Analysis Started -> House Registry Started'
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets_extra_slas_tags AS sale_closing_ops_targets_extra_slas_tags
    ON dim_sale_agreement.tags_from_salesflow LIKE CONCAT('%', sale_closing_ops_targets_extra_slas_tags.salesflow_tag, '%')
    AND sale_closing_ops_targets.metric_name = sale_closing_ops_targets_extra_slas_tags.metric_name
), cte_CCV_to_BankLegalAnalysisStarted AS (
  SELECT
    dim_sale_agreement.sk_offer,
    sale_closing_ops_targets.metric_name,
    metric_flux,
    dim_region.city_group,
    dim_sale_agreement.payment_method,
    dim_sale_agreement.has_used_fgts_in_payment,
    dim_sale_agreement.has_seller_debt_payments,
    TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') AS dt_sale_agreement_signed,
    CASE
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-01-01')
      THEN sla_target_backlog
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-02-01')
      THEN sla_target_202201
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-03-01')
      THEN sla_target_202202
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-04-01')
      THEN sla_target_202203
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-05-01')
      THEN sla_target_202204
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-06-01')
      THEN sla_target_202205
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-07-01')
      THEN sla_target_202206
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-08-01')
      THEN sla_target_202207
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-09-01')
      THEN sla_target_202208
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-10-01')
      THEN sla_target_202209
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-11-01')
      THEN sla_target_202210
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-12-01')
      THEN sla_target_202211
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2023-01-01')
      THEN sla_target_202212
      ELSE NULL
    END + COALESCE(sale_closing_ops_targets_extra_slas_tags.extra_sla_days, 0) AS sla_target_sale_agreement_signed_to_bank_legal_analysis_started,
    sale_closing_ops_targets_extra_slas_tags.extra_sla_days
  FROM dw_sale.dim_sale_agreement
  LEFT JOIN modified_pm AS mpm
    ON dim_sale_agreement.sk_offer = mpm.sk_offer
  JOIN dw_sale.fact_closing_flows
    ON dim_sale_agreement.sk_offer = fact_closing_flows.sk_offer
  JOIN dw_sale.fact_listings
    ON fact_closing_flows.sk_house = fact_listings.sk_house
  JOIN dw_public.dim_region
    ON fact_listings.sk_region = dim_region.sk_region
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets
    ON dim_region.city_group = sale_closing_ops_targets.city_group
    AND LOWER(mpm.payment_method) = LOWER(sale_closing_ops_targets.payment_method)
    AND dim_sale_agreement.has_used_fgts_in_payment = sale_closing_ops_targets.has_used_fgts_in_payment
    AND dim_sale_agreement.has_seller_debt_payments = sale_closing_ops_targets.has_seller_debt_payments
    AND sale_closing_ops_targets.metric_flux = 'Sale Agreement Signed -> Bank Legal Analysis Started'
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets_extra_slas_tags AS sale_closing_ops_targets_extra_slas_tags
    ON dim_sale_agreement.tags_from_salesflow LIKE CONCAT('%', sale_closing_ops_targets_extra_slas_tags.salesflow_tag, '%')
    AND sale_closing_ops_targets.metric_name = sale_closing_ops_targets_extra_slas_tags.metric_name
), cte_CCV_to_FinancingStarted AS (
  SELECT
    dim_sale_agreement.sk_offer,
    sale_closing_ops_targets.metric_name,
    metric_flux,
    dim_region.city_group,
    dim_sale_agreement.payment_method,
    dim_sale_agreement.has_used_fgts_in_payment,
    dim_sale_agreement.has_seller_debt_payments,
    TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') AS dt_sale_agreement_signed,
    CASE
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-01-01')
      THEN sla_target_backlog
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-02-01')
      THEN sla_target_202201
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-03-01')
      THEN sla_target_202202
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-04-01')
      THEN sla_target_202203
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-05-01')
      THEN sla_target_202204
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-06-01')
      THEN sla_target_202205
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-07-01')
      THEN sla_target_202206
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-08-01')
      THEN sla_target_202207
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-09-01')
      THEN sla_target_202208
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-10-01')
      THEN sla_target_202209
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-11-01')
      THEN sla_target_202210
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2022-12-01')
      THEN sla_target_202211
      WHEN TO_DATE(CAST(NULLIF(sk_sale_agreement_signed_date, -1) AS STRING), 'yyyymmdd') < DATE('2023-01-01')
      THEN sla_target_202212
      ELSE NULL
    END + COALESCE(sale_closing_ops_targets_extra_slas_tags.extra_sla_days, 0) AS sla_target_sale_agreement_signed_to_financing_started,
    sale_closing_ops_targets_extra_slas_tags.extra_sla_days
  FROM dw_sale.dim_sale_agreement
  LEFT JOIN modified_pm AS mpm
    ON dim_sale_agreement.sk_offer = mpm.sk_offer
  JOIN dw_sale.fact_closing_flows
    ON dim_sale_agreement.sk_offer = fact_closing_flows.sk_offer
  JOIN dw_sale.fact_listings
    ON fact_closing_flows.sk_house = fact_listings.sk_house
  JOIN dw_public.dim_region
    ON fact_listings.sk_region = dim_region.sk_region
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets
    ON dim_region.city_group = sale_closing_ops_targets.city_group
    AND LOWER(mpm.payment_method) = LOWER(sale_closing_ops_targets.payment_method)
    AND dim_sale_agreement.has_used_fgts_in_payment = sale_closing_ops_targets.has_used_fgts_in_payment
    AND dim_sale_agreement.has_seller_debt_payments = sale_closing_ops_targets.has_seller_debt_payments
    AND sale_closing_ops_targets.metric_flux = 'Sale Agreement Signed -> Financing Started'
  LEFT JOIN datalake_gsheets_clean.sale_closing_ops_targets_extra_slas_tags AS sale_closing_ops_targets_extra_slas_tags
    ON dim_sale_agreement.tags_from_salesflow LIKE CONCAT('%', sale_closing_ops_targets_extra_slas_tags.salesflow_tag, '%')
    AND sale_closing_ops_targets.metric_name = sale_closing_ops_targets_extra_slas_tags.metric_name
)
SELECT
  COALESCE(
    cte_MA.sk_offer,
    cte_DD.sk_offer,
    cte_CRN_End.sk_offer,
    cte_CRI_Start_from_ccv.sk_offer,
    cte_CRI_Start_from_bank_legal_analysis_started.sk_offer,
    cte_CCV_to_BankLegalAnalysisStarted.sk_offer,
    cte_CCV_to_FinancingStarted.sk_offer
  ) AS sk_offer,
  DATE_ADD(
    cte_MA.dt_sale_agreement_signed_date,
    sla_target_sale_agreement_signed_to_house_registry_ended
  ) AS target_sale_agreement_signed_to_house_registry_ended_date,
  sla_target_sale_agreement_signed_to_house_registry_ended,
  DATE_ADD(
    cte_DD.dt_sale_agreement_signed,
    sla_target_sale_agreement_signed_to_legal_analysis_ended
  ) AS target_sale_agreement_signed_to_legal_analysis_ended_date,
  sla_target_sale_agreement_signed_to_legal_analysis_ended,
  DATE_ADD(
    cte_CRN_End.dt_sale_agreement_signed,
    sla_target_sale_agreement_signed_to_notes_registry_ended
  ) AS target_sale_agreement_signed_to_notes_registry_ended,
  sla_target_sale_agreement_signed_to_notes_registry_ended,
  DATE_ADD(
    cte_CRI_Start_from_ccv.dt_sale_agreement_signed,
    cte_CRI_Start_from_ccv.sla_target_sale_agreement_signed_to_house_registry_started
  ) AS target_sale_agreement_signed_to_house_registry_started,
  sla_target_sale_agreement_signed_to_house_registry_started,
  DATE_ADD(
    cte_CCV_to_BankLegalAnalysisStarted.dt_sale_agreement_signed,
    sla_target_sale_agreement_signed_to_bank_legal_analysis_started
  ) AS target_sale_agreement_signed_to_bank_legal_analysis_started,
  sla_target_sale_agreement_signed_to_bank_legal_analysis_started,
  DATE_ADD(
    cte_CCV_to_FinancingStarted.dt_sale_agreement_signed,
    sla_target_sale_agreement_signed_to_financing_started
  ) AS target_sale_agreement_signed_to_financing_started,
  sla_target_sale_agreement_signed_to_financing_started
FROM cte_MA
FULL OUTER JOIN cte_DD
  ON cte_MA.sk_offer = cte_DD.sk_offer
FULL OUTER JOIN cte_CRN_End
  ON cte_MA.sk_offer = cte_CRN_End.sk_offer
FULL OUTER JOIN cte_CRI_Start_from_ccv
  ON cte_MA.sk_offer = cte_CRI_Start_from_ccv.sk_offer
FULL OUTER JOIN cte_CRI_Start_from_bank_legal_analysis_started
  ON cte_MA.sk_offer = cte_CRI_Start_from_bank_legal_analysis_started.sk_offer
FULL OUTER JOIN cte_CCV_to_BankLegalAnalysisStarted
  ON cte_MA.sk_offer = cte_CCV_to_BankLegalAnalysisStarted.sk_offer
FULL OUTER JOIN cte_CCV_to_FinancingStarted
  ON cte_MA.sk_offer = cte_CCV_to_FinancingStarted.sk_offer