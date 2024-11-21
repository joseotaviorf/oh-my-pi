SELECT
    id AS id_commission,
    CreatedByUserId AS id_user_created,
    ConfirmedByUserId AS id_user_confirmed,
    TO_TIMESTAMP(CreatedAt) AS ts_created,
    TO_TIMESTAMP(ConfirmedDate) AS ts_confirmed,
    Year AS year_closing,
    Month AS month_closing
FROM
    datalake_atta_test_raw.commission_revenue_share_periods
