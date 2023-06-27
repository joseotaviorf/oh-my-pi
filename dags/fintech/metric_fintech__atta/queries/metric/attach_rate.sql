SELECT
      DATE_TRUNC('month', TO_DATE(CAST(fcf.sk_credit_analysis_ended_date AS string), 'yyyyMMdd')) AS credit_analysis_ended_month,
      COUNT(DISTINCT CASE WHEN (dsa.credit_model = 'ATTA') THEN fcf.sk_offer ELSE NULL END)*1.00 / COUNT(DISTINCT fcf.sk_offer) AS attach_rate
FROM dw_sale.fact_closing_flows fcf
LEFT JOIN dw_sale.dim_sale_agreement AS dsa
      ON fcf.sk_offer = dsa.sk_offer WHERE 1=1 AND dsa.credit_model IN ('ATTA','EXTERNAL','UNDEFINED') AND dsa.payment_method LIKE '%FINANCED%' AND (NOT (dsa.is_ccv_canceled ) OR (dsa.is_ccv_canceled ) IS NULL)
AND fcf.sk_credit_analysis_ended_date <> -1
GROUP BY 1 ORDER BY 1 DESC
