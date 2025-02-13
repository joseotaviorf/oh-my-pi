SELECT
    id,
    house_info,
    acquisition_campaign,
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) as day
FROM
    datalake_rene_descartes_raw.acquisition_misc_data
