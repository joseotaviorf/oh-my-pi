SELECT
    -- ids
    id,
    candidate_id AS id_candidate,
    job_post_id AS id_job_post,
    source.id AS id_source,
    credited_to.id AS id_credited_to,
    recruiter.id AS id_recruiter,
    coordinator.id AS id_coordinator,
    CAST(
        FROM_JSON(CAST(rejection_reason AS STRING), 
        'struct<id:bigint, name:string>').id AS BIGINT
    ) AS id_rejection_reason,
    -- text fields
    status,
    source.public_name AS source_name,
    current_stage.name AS current_stage_name,
    CAST(
        FROM_JSON(CAST(rejection_reason AS STRING), 
        'struct<id:bigint, name:string>').name AS STRING
    ) AS rejection_reason_name,
    credited_to.name AS credited_to_name,
    credited_to.first_name AS credited_to_first_name,
    credited_to.last_name AS credited_to_last_name,
    recruiter.name AS recruiter_name,
    recruiter.first_name AS recruiter_first_name,
    recruiter.last_name AS recruiter_last_name,
    coordinator.name AS coordinator_name,
    coordinator.first_name AS coordinator_first_name,
    coordinator.last_name AS coordinator_last_name,
    CAST(
        FROM_JSON(CAST(prospect_detail AS STRING), 
        'struct<prospect_pool:struct<name:string>>').prospect_pool.name AS STRING
    ) AS prospect_pool_name,
    CAST(
        FROM_JSON(CAST(prospect_detail AS STRING), 
        'struct<prospect_stage:struct<name:string>>').prospect_stage.name AS STRING
    ) AS prospect_stage_name,
    CAST(
        FROM_JSON(CAST(prospect_detail AS STRING), 
        'struct<prospect_owner:struct<name:string>>').prospect_owner.name AS STRING
    ) AS prospect_owner_name,
    CAST(
        FROM_JSON(CAST(keyed_custom_fields.preferred_name___social_name__optional_ AS STRING), 
        'struct<value:string>').value AS STRING
    ) AS social_name,
    CAST(
        FROM_JSON(CAST(keyed_custom_fields.are_you_legally_authorized_to_work_in_the_country_where_this_job_is_located_ AS STRING), 
        'struct<value:string>').value AS BOOLEAN) 
    AS work_authorization_status,
    COALESCE(
        CAST(FROM_JSON(CAST(keyed_custom_fields.qual_o_seu_tipo_de_defici_ncia_ AS STRING), 'struct<value:string>').value AS STRING),
        CAST(FROM_JSON(CAST(keyed_custom_fields._cu_l_es_su_tipo_de_discapacidad_ AS STRING), 'struct<value:string>').value AS STRING)
    ) AS disability_type_details,
    ARRAY(COALESCE(
        CAST(FROM_JSON(CAST(keyed_custom_fields.pc_d_necessidade_de_acessibilidade AS STRING), 'struct<value:string>').value AS STRING),
        CAST(FROM_JSON(CAST(keyed_custom_fields.pc_d_necesidad_de_accesibilidad AS STRING), 'struct<value:string>').value AS STRING)
    )) AS accessibility_needs,
    -- boolean
    CAST(prospect AS BOOLEAN) AS is_prospect,
    -- timestamps
    CAST(applied_at AS TIMESTAMP) AS ts_applied,
    CAST(rejected_at AS TIMESTAMP) AS ts_rejected,
    CAST(last_activity_at AS TIMESTAMP) AS ts_last_activity,
    NOW() AS ts_load,
    -- array
    attachments,
    jobs,
    answers,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.applications