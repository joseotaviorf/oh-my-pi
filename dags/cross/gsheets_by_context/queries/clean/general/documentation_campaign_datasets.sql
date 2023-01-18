SELECT
    quarter,
    year_month,
    line,
    layer,
    table_name,
    CAST(table_has_description as BOOLEAN) as has_description,
    CAST(count_columns as INTEGER) as count_columns,
    CAST(pct_columns_have_description as FLOAT) pct_columns_has_description,
    comment,
    ts_load
FROM
    datalake_gsheets_raw.documentation_campaign_datasets
