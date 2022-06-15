SELECT
    id,
    google_drive_folder_id AS id_google_drive_folder,
    crawlergroup_id AS id_crawler_group,
    unit_id AS id_unit,
    which_crawlers_id AS id_which_crawlers,
    which_crawlers_overwrite_id AS id_which_crawlers_overwrite,
    city_id AS id_city,
    obs,
    status,
    type
FROM
    datalake_legaut_raw.crawlers_crawlergroup
