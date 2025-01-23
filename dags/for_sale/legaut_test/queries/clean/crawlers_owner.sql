SELECT
    id,
    crawlergroup_id AS id_crawler_group,
    matricula_owner_id AS id_matricula_owner,
    user_id AS id_user,
    name,
    rg,
    cpf,
    gender,
    name_mother,
    cnpj,
    extra,
    current AS is_current,
    individual AS is_individual,
    spouse AS has_spouse,
    COALESCE(TO_DATE(birthday),TO_DATE(birthday, "dd/MM/yyyy")) AS dt_birth
FROM
    datalake_legaut_test_raw.crawlers_owner
