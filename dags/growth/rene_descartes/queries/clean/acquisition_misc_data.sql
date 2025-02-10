SELECT
    id,
    house_info,
    acquisition_campaign,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rene_descartes_raw.acquisition_misc_data
