WITH interactions AS (
    SELECT
        EXPLODE(interactions) AS interactions, 
        ts_load,
        year,
        month,
        day 
    FROM 
        datalake_stilingue_clean.calls_report 
)
SELECT
    interactions.conversationId AS id_conversation,
    interactions.postId AS id_post,
    interactions.caseId AS id_case,
    interactions.rootId AS id_root,
    interactions.pid,
    interactions.page,
    interactions.user,
    interactions.channel,
    interactions.tags,
    interactions.conversationStatus AS conversation_status,
    interactions.operatorName AS agent_name,
    interactions.text AS message,
    interactions.polarity,
    interactions.originalChannel AS original_channel,
    interactions.interactionType AS interaction_type,
    interactions.themes,
    interactions.postUrl AS post_url,
    interactions.delay,
    interactions.outsideDateRange AS is_outside_date_range,
    interactions.fromPromoted AS is_promoted,
    interactions.proprietary AS is_proprietary,
    interactions.belongsToSacCall AS is_sac_call,
    interactions.root AS is_root,
    interactions.duplicated AS is_duplicated,
    interactions.postedAt AS ts_posted,
    interactions.processedAt AS ts_processed,
    ts_load,
    year,
    month,
    day
FROM
    interactions