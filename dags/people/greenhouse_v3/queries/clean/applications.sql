SELECT
    -- ids
    id AS id_application,
    candidate_id AS id_candidate,
    job_id AS id_job,
    job_post_id AS id_job_post,
    source_id AS id_source,
    referrer_id AS id_referrer,
    -- text fields
    status,
    custom_fields.preferred_name___social_name__optional_.value AS candidate_preferred_name,
    COALESCE(
        custom_fields.qual_o_seu_tipo_de_defici_ncia_.value,
        custom_fields._cu_l_es_su_tipo_de_discapacidad_.value,
        custom_fields.what_is_your_type_of_disability_.value
    ) AS disability_type_details,
    ARRAY(COALESCE(
        custom_fields.pc_d_necessidade_de_acessibilidade.value,
        custom_fields.pc_d_necesidad_de_accesibilidad.value,
        custom_fields.pw_d___request_accessibility.value
    )) AS accessibility_needs,
    custom_fields.if_yes__what_is_the_validity___if_you_are_not_a_foreigner__put_n_a_.value AS work_authorization_validity,
    -- boolean
    CAST(prospect AS BOOLEAN) AS is_prospect,
    CAST(
        custom_fields.are_you_legally_authorized_to_work_in_the_country_where_this_job_is_located_.value
        AS BOOLEAN
    ) AS has_work_authorization,
    COALESCE(
        custom_fields.pt_possui_defici_ncia.value,
        custom_fields.es_possui_defici_ncia.value,
        custom_fields.en_possui_defici_ncia.value
    ) IN ('Sim', 'Sí', 'Yes') AS has_disability,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(rejected_at AS TIMESTAMP) AS ts_rejected,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- arrays
    answers,
    custom_fields,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.applications
