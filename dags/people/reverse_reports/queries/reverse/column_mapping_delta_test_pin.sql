SELECT
    1 AS `test_value(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
