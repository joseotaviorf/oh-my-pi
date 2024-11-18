SELECT
    id,
    uuid,
    chat_group_id AS id_chat_group,
    from_chat_user_id AS id_from_chat_user,
    to_chat_user_id AS id_to_chat_user,
    vendor_id AS id_vendor,
    version,
    state,
    result,
    from_leg_type,
    from_leg_state,
    from_leg_result,
    from_leg_duration,
    to_leg_type,
    to_leg_state,
    to_leg_result,
    to_leg_duration,
    to_voip_rang,
    vendor_name,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_chatmanager_raw.call
