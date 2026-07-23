WITH issues AS (
    SELECT
        id,
        key AS id_issue,
        GET_JSON_OBJECT(fields, '$.attachment') AS attachment,
        MAKE_DATE(year, month, day) AS ts_updated
    FROM
        datalake_jira_clean.issues
    WHERE
        INT(GET_JSON_OBJECT(fields, '$.project.id')) = 10400
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
exploded_attachments AS (
    SELECT
        i.id_issue,
        att.id AS id_attachment,
        att.author.accountId AS id_author_account,
        att.filename AS file_name,
        att.mimeType AS file_type,
        att.content AS file_content_url,
        att.thumbnail AS file_thumbnail,
        att.size AS file_size,
        TIMESTAMP(att.created) AS ts_created,
        i.ts_updated,
        YEAR(TIMESTAMP(att.created)) AS year,
        MONTH(TIMESTAMP(att.created)) AS month,
        DAY(TIMESTAMP(att.created)) AS day
    FROM 
        issues AS i
    LATERAL VIEW EXPLODE(
        FROM_JSON(
            attachment,
            "ARRAY<STRUCT<
                author: STRUCT<
                    accountId: STRING, 
                    accountType: STRING, 
                    active: BOOLEAN, 
                    avatarUrls: STRUCT<`16x16`: STRING, `24x24`: STRING, `32x32`: STRING, `48x48`: STRING>, 
                    displayName: STRING, 
                    emailAddress: STRING, 
                    self: STRING, timeZone: STRING
                >, 
                content: STRING, 
                created: STRING, 
                filename: STRING, 
                id: STRING, 
                mimeType: STRING, 
                self: STRING, 
                size: BIGINT, 
                thumbnail: STRING
            >>"
        )
    ) t AS att
)
SELECT
    id_issue,
    id_attachment,
    id_author_account,
    file_name,
    file_type,
    file_content_url,
    file_thumbnail,
    file_size,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM 
    exploded_attachments
QUALIFY
    1 = ROW_NUMBER() OVER(PARTITION BY id_issue, id_attachment ORDER BY ts_updated DESC)