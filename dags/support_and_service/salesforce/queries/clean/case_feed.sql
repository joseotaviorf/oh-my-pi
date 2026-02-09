SELECT
    Id AS id_case_feed,
    ParentId AS id_parent,
    CreatedById AS id_created_by,
    RelatedRecordId AS id_related_record,
    InsertedById AS id_inserted_by,
    BestCommentId AS id_best_comment,
    Type AS feed_type,
    Title AS title,
    Body AS body,
    LinkUrl AS link_url,
    NetworkScope AS network_scope,
    Visibility AS visibility,
    CAST(CommentCount AS INT) AS comment_count,
    CAST(LikeCount AS INT) AS like_count,
    CAST(IsDeleted AS BOOLEAN) AS is_deleted,
    CAST(IsRichText AS BOOLEAN) AS is_rich_text,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
    CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.case_feed
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
