SELECT
    id,
    imovel_id AS id_house,
    social_housing_program_id AS id_social_housing_program,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.SocialHousingProgramClassification
