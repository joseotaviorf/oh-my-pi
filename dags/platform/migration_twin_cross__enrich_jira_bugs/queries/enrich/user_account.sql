WITH issues AS (
    SELECT 
        key,
        GET_JSON_OBJECT(fields,'$.comment.comments') AS comments,
        GET_JSON_OBJECT(fields, '$.attachment') AS attachment,
        GET_JSON_OBJECT(fields, '$.assignee') AS assignee,
        GET_JSON_OBJECT(fields, '$.reporter') AS reporter,
        GET_JSON_OBJECT(fields, '$.creator') AS creator,
        MAKE_DATE(year, month, day) AS ts_updated
    FROM
        datalake_jira_clean.issues
    WHERE
        INT(GET_JSON_OBJECT(fields, '$.project.id')) = 10400
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
comment_author AS (
    SELECT
        comment.author.accountId AS id_author_account,
        comment.author.displayName AS author_name,
        comment.author.emailAddress AS author_email,
        comment.author.timeZone AS author_time_zone,
        comment.author.accountType AS author_account_type,
        CAST(comment.author.active AS BOOLEAN) AS is_author_active,
        comment.updateAuthor.accountId AS id_update_author_account,
        comment.updateAuthor.displayName AS update_author_name,
        comment.updateAuthor.emailAddress AS update_author_email,
        comment.updateAuthor.timeZone AS update_author_time_zone,
        comment.updateAuthor.accountType AS update_author_account_type,
        CAST(comment.updateAuthor.active AS BOOLEAN) AS is_update_author_active,
        ts_updated
    FROM 
        issues
    LATERAL VIEW EXPLODE(
        FROM_JSON(
            comments,
            "ARRAY<
                STRUCT<
                    author: STRUCT<
                        accountId: STRING, 
                        accountType: STRING, 
                        active: BOOLEAN, 
                        avatarUrls: STRUCT<`16x16`: STRING, `24x24`: STRING, `32x32`: STRING, `48x48`: STRING>, 
                        displayName: STRING, 
                        emailAddress: STRING, 
                        self: STRING, 
                        timeZone: STRING
                    >,
                    updateAuthor: STRUCT<
                        accountId: STRING, 
                        accountType: STRING, active: BOOLEAN, avatarUrls: STRUCT<`16x16`: STRING, `24x24`: STRING, `32x32`: STRING, `48x48`: STRING>, 
                        displayName: STRING, 
                        emailAddress: STRING, 
                        self: STRING, 
                        timeZone: STRING
                    >
                >
            >"
        )
    ) t AS comment
),
attachment_author AS (
    SELECT
        att.author.accountId AS id_account,
        att.author.displayName AS name,
        att.author.emailAddress AS email,
        att.author.timeZone AS time_zone,
        att.author.accountType AS account_type,
        CAST(att.author.active AS BOOLEAN) AS is_active,
        ts_updated
    FROM 
        issues
    LATERAL VIEW EXPLODE(
        FROM_JSON(
            attachment,
            "ARRAY<
                STRUCT<
                    author: STRUCT<
                        accountId: STRING, 
                        accountType: STRING, 
                        active: BOOLEAN, 
                        avatarUrls: STRUCT<`16x16`: STRING, `24x24`: STRING, `32x32`: STRING, `48x48`: STRING>, 
                        displayName: STRING, 
                        emailAddress: STRING, 
                        self: STRING, 
                        timeZone: STRING
                    >
                >
            >"
        )
    ) t AS att
),
union_account AS (
    SELECT -- Assignee
        GET_JSON_OBJECT(assignee, '$.accountId') AS id_account,
        GET_JSON_OBJECT(assignee, '$.displayName') AS name,
        GET_JSON_OBJECT(assignee, '$.emailAddress') AS email,
        GET_JSON_OBJECT(assignee, '$.timeZone') AS time_zone,
        GET_JSON_OBJECT(assignee, '$.accountType') AS account_type,
        CAST(GET_JSON_OBJECT(assignee, '$.active') AS BOOLEAN) AS is_active,
        ts_updated
    FROM
        issues
    WHERE
        assignee IS NOT NULL
    UNION ALL
    SELECT -- Reporter
        GET_JSON_OBJECT(reporter, '$.accountId') AS id_account,
        GET_JSON_OBJECT(reporter, '$.displayName') AS name,
        GET_JSON_OBJECT(reporter, '$.emailAddress') AS email,
        GET_JSON_OBJECT(reporter, '$.timeZone') AS time_zone,
        GET_JSON_OBJECT(reporter, '$.accountType') AS account_type,
        CAST(GET_JSON_OBJECT(reporter, '$.active') AS BOOLEAN) AS is_active,
        ts_updated
    FROM
        issues
    WHERE
        reporter IS NOT NULL
    UNION ALL
    SELECT -- Creator
        GET_JSON_OBJECT(creator, '$.accountId') AS id_account,
        GET_JSON_OBJECT(creator, '$.displayName') AS name,
        GET_JSON_OBJECT(creator, '$.emailAddress') AS email,
        GET_JSON_OBJECT(creator, '$.timeZone') AS time_zone,
        GET_JSON_OBJECT(creator, '$.accountType') AS account_type,
        CAST(GET_JSON_OBJECT(creator, '$.active') AS BOOLEAN) AS is_active,
        ts_updated
    FROM
        issues
    WHERE
        creator IS NOT NULL
    UNION ALL
    SELECT -- Comment author
        id_author_account AS id_account,
        author_name AS name,
        author_email AS email,
        author_time_zone AS time_zone,
        author_account_type AS account_type,
        is_author_active AS is_active,
        ts_updated
    FROM 
        comment_author
    WHERE
        id_author_account IS NOT NULL
    UNION ALL
    SELECT -- Comment update author
        id_update_author_account AS id_account,
        update_author_name AS name,
        update_author_email AS email,
        update_author_time_zone AS time_zone,
        update_author_account_type AS account_type,
        is_update_author_active AS is_active,
        ts_updated
    FROM 
        comment_author
    WHERE
        id_update_author_account IS NOT NULL
    UNION ALL
    SELECT -- Attachment author
        id_account,
        name,
        email,
        time_zone,
        account_type,
        is_active,
        ts_updated
    FROM 
        attachment_author
    WHERE
        id_account IS NOT NULL
)
SELECT
    id_account,
    name,
    email,
    time_zone,
    account_type,
    is_active,
    ts_updated
FROM
    union_account
QUALIFY
    1 = ROW_NUMBER() OVER(PARTITION BY id_account ORDER BY ts_updated DESC)