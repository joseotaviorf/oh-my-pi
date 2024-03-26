SELECT
    *,
    CAST(EXTRACT(YEAR FROM DATE('{execution_date}')) AS INT) AS year,
    CAST(EXTRACT(MONTH FROM DATE('{execution_date}')) AS INT) AS month,
    CAST(EXTRACT(DAY FROM DATE('{execution_date}')) AS INT) AS day
FROM
    public.entry
WHERE
    DATE(retsuko_updated_at) >= DATE('{execution_date}')
    AND DATE(retsuko_updated_at) <= DATE(DATE('{execution_date}') + INTERVAL '1 day')
