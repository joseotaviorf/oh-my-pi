SELECT
    *,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    public."Session"
WHERE
    updated_at >= DATE('{year}-{month}-{day}')
    AND updated_at < DATE('{year}-{month}-{day}') + 1
