SELECT
    id,
    contract_id,
    house_external_id,
    status,
    last_year_amount,
    created_at,
    updated_at,
    year AS year_tax_report
FROM 
    public.tax_report
WHERE
    DATE(updated_at) >= DATE("{{ ds }}")
    AND DATE(updated_at) < DATE(DATE("{{ ds }}") + INTERVAL '1 day')