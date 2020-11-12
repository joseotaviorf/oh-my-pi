SELECT
    id,
    split(campaign,'[\:]')[3] AS id_campaign,
    status,
    type,
    acc,
    year,
    month,
    day
FROM datalake_marketing_costs_raw.linkedin_creatives
WHERE
    year={year} and month={month} and day={day}
