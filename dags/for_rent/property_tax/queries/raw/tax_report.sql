SELECT
    id,
    contract_id,
    house_external_id,
    status,
    last_year_amount,
    created_at,
    updated_at,
    year AS year_tax_report,
    YEAR(DATE('{execution_date}')) AS year,
    MONTH(DATE('{execution_date}')) AS month,
    DAY(DATE('{execution_date}')) AS day
FROM 
    public.tax_report
WHERE
    DATE(updated_at) >= DATE('{execution_date}')
    AND DATE(updated_at) < DATE(DATE('{execution_date}') + INTERVAL '1 day')