SELECT
    id,
    google_drive_folder_id AS id_google_drive_folder,
    google_spreadsheet_id AS id_google_spreadsheet,
    company_id AS id_company,
    activated,
    type,
    name,
    slug,
    created_at AS ts_created
FROM
    datalake_legaut_test_raw.meuSite_project
