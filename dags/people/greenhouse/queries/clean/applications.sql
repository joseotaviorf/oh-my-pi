SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    jobs[0].id AS id_job,
    job_post_id AS id_job_post,
    current_stage.id AS id_current_stage,
    source.id AS id_source,
    credited_to.id AS id_credited_to,
    recruiter.id AS id_recruiter,
    coordinator.id AS id_coordinator,
    prospect_detail.prospect_pool.id AS id_prospect_pool,
    prospect_detail.prospect_stage.id AS id_prospect_stage,
    prospect_detail.prospect_owner.id AS id_prospect_owner,
    prospective_office.id AS id_prospective_office,
    CAST(rejection_reason.type.id AS BIGINT) AS id_rejection_reason_type,
    CAST(rejection_reason.id AS BIGINT) AS id_rejection_reason,
    -- text fields
    status,
    jobs[0].name AS job_name,
    source.public_name AS source_name,
    current_stage.name AS current_stage_name,
    CAST(rejection_reason.type.name AS STRING) AS rejection_reason_type_name,
    CAST(rejection_reason.name AS STRING) AS rejection_reason_name,
    rejection_details.keyed_custom_fields.if_candidate_accepted_another_offer__indicate_where_.value AS external_offer_accepted_from_company,
    keyed_custom_fields.preferred_name___social_name__optional_.value AS candidate_preferred_name,
    credited_to.name AS credited_to_name,
    credited_to.first_name AS credited_to_first_name,
    credited_to.last_name AS credited_to_last_name,
    recruiter.name AS recruiter_name,
    recruiter.first_name AS recruiter_first_name,
    recruiter.last_name AS recruiter_last_name,
    coordinator.name AS coordinator_name,
    coordinator.first_name AS coordinator_first_name,
    coordinator.last_name AS coordinator_last_name,
    prospect_detail.prospect_pool.name AS prospect_pool_name,
    prospect_detail.prospect_stage.name AS prospect_stage_name,
    prospect_detail.prospect_owner.name AS prospect_owner_name,
    prospective_office.name AS prospective_office_name,
    keyed_custom_fields.preferred_name___social_name__optional_.value AS social_name,
    COALESCE(
        keyed_custom_fields.qual_o_seu_tipo_de_defici_ncia_.value,
        keyed_custom_fields._cu_l_es_su_tipo_de_discapacidad_.value,
        keyed_custom_fields.what_is_your_type_of_disability_.value
    ) AS disability_type_details,
    ARRAY(COALESCE(
        keyed_custom_fields.pc_d_necessidade_de_acessibilidade.value,
        keyed_custom_fields.pc_d_necesidad_de_accesibilidad.value,
        keyed_custom_fields.pw_d___request_accessibility.value
    )) AS accessibility_needs,
    keyed_custom_fields.if_yes__what_is_the_validity___if_you_are_not_a_foreigner__put_n_a_.value AS work_authorization_validity,
    -- boolean
    CAST(prospect AS BOOLEAN) AS is_prospect,
    CAST(
      keyed_custom_fields.are_you_legally_authorized_to_work_in_the_country_where_this_job_is_located_.value
      AS BOOLEAN
      ) AS has_work_authorization,
    COALESCE(
      keyed_custom_fields.pt_possui_defici_ncia.value,
      keyed_custom_fields.es_possui_defici_ncia.value,
      keyed_custom_fields.en_possui_defici_ncia.value
    ) IN ('Sim', 'Sí', 'Yes') AS has_disability,
    -- timestamps
    CAST(applied_at AS TIMESTAMP) AS ts_applied,
    CAST(rejected_at AS TIMESTAMP) AS ts_rejected,
    CAST(last_activity_at AS TIMESTAMP) AS ts_last_activity,
    NOW() AS ts_load,
    -- array
    attachments,
    answers,
    rejection_details,
    jobs,
    prospective_office,
    keyed_custom_fields
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.applications