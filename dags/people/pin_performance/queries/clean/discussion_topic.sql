SELECT
    discussion_topic_id AS id_discussion_topic,
    business_group_id AS id_business_group,
    check_in_meeting_id AS id_check_in_meeting,
    object_id AS id_object,
    created_by_person_id AS id_created_by_person,
    topic_type,
    name AS topic_name,
    CAST(object_version_number AS INT) AS object_version_number,
    created_by,
    last_updated_by AS updated_by,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_discussion_topics
