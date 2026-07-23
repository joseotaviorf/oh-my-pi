WITH issues AS (
    SELECT
        key AS id_issue,
        GET_JSON_OBJECT(fields,'$.comment.comments') AS comments,
        MAKE_DATE(year, month, day) AS ts_load
    FROM
        datalake_jira_clean.issues
    WHERE
        INT(GET_JSON_OBJECT(fields, '$.project.id')) = 10400
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY key ORDER BY MAKE_DATE(year, month, day) DESC)
),
comments AS (
    SELECT
        id_issue,
        comment.id AS id_comment,
        comment.author.accountId AS id_author_account,
        comment.updateAuthor.accountId AS id_update_author_account,
        row_number() OVER(PARTITION BY id_issue ORDER BY TIMESTAMP(comment.created)) AS comment_order,
        comment.body.content AS content,
        TIMESTAMP(comment.created) AS ts_created,
        TIMESTAMP(comment.updated) AS ts_updated,
        ts_load,
        YEAR(TIMESTAMP(comment.created)) AS year,
        MONTH(TIMESTAMP(comment.created)) AS month,
        DAY(TIMESTAMP(comment.created)) AS day
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
                    body: STRUCT<
                        type: STRING, 
                        version: BIGINT,
                        content: ARRAY<
                            STRUCT<
                                type: STRING, 
                                content: ARRAY<MAP<STRING, STRING>>
                            >
                        >
                    >,
                    created: STRING, 
                    id: STRING, 
                    jsdPublic: BOOLEAN, 
                    self: STRING, 
                    updateAuthor: STRUCT<
                        accountId: STRING, 
                        accountType: STRING, 
                        active: BOOLEAN, 
                        avatarUrls: STRUCT<`16x16`: STRING, `24x24`: STRING, `32x32`: STRING, `48x48`: STRING>, 
                        displayName: STRING, 
                        emailAddress: STRING, 
                        self: STRING, timeZone: STRING
                    >, 
                    updated: STRING
                >
            >"
        )
    ) t AS comment
),
explode_content AS (
    SELECT
        c.id_issue,
        c.id_comment,
        c.id_author_account,
        c.id_update_author_account,
        c.content AS original_content,
        c.comment_order AS comment_index,
        cs.ctt_index AS content_index,
        cs.ctt.type,
        cs.ctt.content,
        c.ts_created,
        c.ts_updated,
        c.ts_load,
        c.year,
        c.month,
        c.day
    FROM 
        comments AS c
    LATERAL VIEW POSEXPLODE(
        content 
    ) cs AS ctt_index, ctt
),
explode_text AS (
    SELECT
        id_issue,
        id_comment,
        comment_index,
        content_index,
        p_content_index,
        CASE
            WHEN ctt.type IN ('listItem', 'paragraph')
                THEN REGEXP_EXTRACT_ALL(
                    ctt.content,
                    '"text":"(.*?)"'
                )
            WHEN ctt.type = 'text' 
                THEN ARRAY(ctt.text)
            WHEN ctt.type = 'mention' 
                THEN REGEXP_EXTRACT_ALL(
                    ctt.attrs,
                    '"text":"(.*?)"'
                )
            WHEN ctt.type = 'media' 
                THEN REGEXP_EXTRACT_ALL(
                    ctt.attrs,
                    '"alt":"(.*?)"'
                )
            WHEN ctt.type = 'hardBreak'
                THEN ARRAY('\n')
        END AS text_array
    FROM 
        explode_content AS c   
    LATERAL VIEW POSEXPLODE(
        content 
    ) cs AS p_content_index, ctt
),
join_text AS (
    SELECT
        id_issue,
        id_comment,
        CONCAT(comment_index || content_index || p_content_index) AS new_index,
        ARRAY_JOIN(
            FLATTEN(COLLECT_LIST(text_array) OVER (
                PARTITION BY id_issue, id_comment
                ORDER BY comment_index, content_index, p_content_index
            )),
            '\n'
        ) AS full_comment_text
    FROM 
        explode_text
)
SELECT
    ec.id_issue,
    ec.id_comment,
    ec.id_author_account,
    ec.id_update_author_account AS id_last_modified_by_account,
    IF(TRIM(jt.full_comment_text) = '', NULL, jt.full_comment_text) AS comment,
    ec.ts_created,
    ec.ts_updated,
    ec.ts_load,
    ec.year,
    ec.month,
    ec.day
FROM 
    explode_content AS ec
LEFT JOIN
    join_text AS jt
        ON jt.id_issue = ec.id_issue
        AND jt.id_comment = ec.id_comment
QUALIFY
    1 = ROW_NUMBER() OVER(PARTITION BY ec.id_issue, ec.id_comment ORDER BY jt.new_index DESC, ec.ts_load DESC)