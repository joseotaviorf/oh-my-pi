SELECT
    id,
    contract_id,
    house_external_id,
    status,
    last_year_amount,
    created_at,
    updated_at,
    year AS year_tax_report,
    CAST(EXTRACT(YEAR FROM DATE('{execution_date}')) AS INT) AS year,
    CAST(EXTRACT(MONTH FROM DATE('{execution_date}')) AS INT) AS month,
    CAST(EXTRACT(DAY FROM DATE('{execution_date}')) AS INT) AS day
FROM 
    public.tax_report
WHERE
    DATE(updated_at) >= DATE('{execution_date}')
    AND DATE(updated_at) < DATE(DATE('{execution_date}') + INTERVAL '1 day')