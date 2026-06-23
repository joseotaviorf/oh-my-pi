WITH deduped AS (
    SELECT
        id,
        business_unit_id AS id_business_unit,
        user_id AS id_user,
        version,
        parent_member_profile_id AS id_parent_member_profile,
        profile,
        active AS is_active,
        relationship_start_date AS dt_relationship_started,
        created_at AS ts_created,
        updated_at AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.member_profile
)
SELECT
    id,
    id_business_unit,
    id_user,
    version,
    id_parent_member_profile,
    profile,
    is_active,
    dt_relationship_started,
    ts_created,
    ts_updated,
    year,
    month,
    day,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    deduped
WHERE
    rn = 1
