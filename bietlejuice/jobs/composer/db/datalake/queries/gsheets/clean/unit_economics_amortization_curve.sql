SELECT
    NULLIF(business, '') AS business,
    NULLIF(classificacao, '') AS classification,
    NULLIF(amortizacao_mes, '') AS month_amortization,
    CAST(NULLIF(metrica_amortizacao, '') AS FLOAT) AS metric_amortization,
    CAST(NULLIF(ym_inicio_vigencia, '') AS DATE) AS dt_term_start,
    CAST(NULLIF(ym_fim_vigencia, '') AS DATE) AS dt_term_end
FROM
    datalake_gsheets_raw.unit_economics_amortization_curve
