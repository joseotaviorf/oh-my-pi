WITH member_profile_aud AS (
    SELECT DISTINCT
        XXHASH64(mpa.id, mpa.id_business_unit, COALESCE(mpa.id_parent_member_profile, -1), mpa.rev) AS id_revision,
        XXHASH64(mpa.id, mpa.id_business_unit, COALESCE(mpa.id_parent_member_profile, -1)) AS id_member_relationship,
        mpa.id,
        mpa.id_user,
        COALESCE(mpa.id_parent_member_profile, -1) AS id_parent_member_profile,
        mpa.id_business_unit,
        mpa.rev,
        mpa.profile,
        ROW_NUMBER() OVER(PARTITION BY mpa.id ORDER BY mpa.ts_updated DESC) = 1 AS is_last_update,
        mpa.is_active,
        mpa.ts_created AS ts_relationship_started,
        COALESCE(rev.ts_created, LEAD(mpa.ts_created) OVER(PARTITION BY mpa.id ORDER BY mpa.ts_updated)) AS ts_relationship_ended,
        mpa.ts_created,
        mpa.ts_updated,
        mpa.year,
        mpa.month,
        mpa.day
    FROM 
        datalake_hub_services_clean.member_profile_aud AS mpa
    LEFT JOIN 
        datalake_hub_services_clean.rev_info AS rev 
            ON rev.id = mpa.rev_end
            AND rev.ts_created >= mpa.ts_created
),
member_profile_last_user AS (
    SELECT
        mpa.id,
        mpa.id_user,
        u.id_main_user,
        u.id_agent,
        u.uuid_person,
        u.name,
        u.email,
        u.phone_number,
        u.secondary_phone_number,
        u.cpf
    FROM 
        datalake_hub_services_clean.member_profile AS mpa
    JOIN
        datalake_hub_services.users AS u
            ON u.id_user = mpa.id_user
),
relationship_ended AS (
    SELECT
        mpa.id_revision,
        CASE
            WHEN mpa.ts_relationship_ended IS NULL AND mpa.is_active IS FALSE THEN mpa.ts_updated
            WHEN mpa.ts_relationship_ended IS NULL AND mpa.is_active IS TRUE THEN NOW()
            ELSE mpa.ts_relationship_ended
        END AS ts_relationship_ended
    FROM
        member_profile_aud AS mpa
),
deduped_member_profile AS (
    SELECT
        mpa.id_revision,
        mpa.id_member_relationship,
        mpa.id AS id_member_profile,
        mpu.id_user,
        mpu.id_main_user,
        mpu.id_agent,
        mpu.uuid_person,
        ad.uuid_company,
        mpa.id_parent_member_profile,
        mpu_parent.id_user AS id_parent_user,
        mpu_parent.id_main_user AS id_parent_main_user,
        mpu_parent.id_agent AS id_parent_agent,
        mpu_parent.uuid_person AS uuid_parent_person,
        mpa.id_business_unit,
        bu.id_region,
        mpa.profile,
        ad.agent_type,
        bu.hub_name,
        bu.city_group,
        bu.city_name,
        bu.short_region_name,
        bu.lead_types,
        bu.business_context,
        mpu.name,
        mpu.email,
        mpu.phone_number,
        mpu.secondary_phone_number,
        mpu.cpf,
        mpu_parent.name AS parent_name,
        mpu_parent.email AS parent_email,
        mpu_parent.phone_number AS parent_phone_number,
        mpu_parent.secondary_phone_number AS parent_secondary_phone_number,
        mpu_parent.cpf AS parent_cpf,
        mpa.is_active AS is_member_active_in_period,
        ROW_NUMBER() OVER(PARTITION BY mpa.id_member_relationship ORDER BY mpa.ts_updated DESC) = 1 AS is_latest_relationship_state,
        mpa.ts_relationship_started,
        mre.ts_relationship_ended,
        NOW() AS ts_load,
        ROW_NUMBER() OVER(
            PARTITION BY mpa.id_revision
            ORDER BY mre.ts_relationship_ended DESC
        ) AS rn
    FROM
        member_profile_aud AS mpa
    JOIN
        relationship_ended AS mre
            ON mre.id_revision = mpa.id_revision
    LEFT JOIN
        member_profile_last_user AS mpu
            ON mpu.id = mpa.id
    LEFT JOIN
        member_profile_last_user AS mpu_parent
            ON mpu_parent.id = mpa.id_parent_member_profile
    LEFT JOIN
        datalake_ebdb_clean.agent_data AS ad
            ON ad.id = mpu.id_agent
    LEFT JOIN
        datalake_hub_services.business_unit AS bu
            ON bu.id_business_unit = mpa.id_business_unit
            AND bu.is_last_region_associated IS TRUE
)
SELECT
    id_revision,
    id_member_relationship,
    id_member_profile,
    id_user,
    id_main_user,
    id_agent,
    uuid_person,
    uuid_company,
    id_parent_member_profile,
    id_parent_user,
    id_parent_main_user,
    id_parent_agent,
    uuid_parent_person,
    id_business_unit,
    id_region,
    profile,
    agent_type,
    hub_name,
    city_group,
    city_name,
    short_region_name,
    lead_types,
    business_context,
    name,
    email,
    phone_number,
    secondary_phone_number,
    cpf,
    parent_name,
    parent_email,
    parent_phone_number,
    parent_secondary_phone_number,
    parent_cpf,
    is_member_active_in_period,
    is_latest_relationship_state,
    ts_relationship_started,
    ts_relationship_ended,
    ts_load
FROM
    deduped_member_profile
WHERE
    rn = 1