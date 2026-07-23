WITH issues AS (
  SELECT
    id,
    key AS id_issue,
    GET_JSON_OBJECT(fields, attachment) AS attachment,
    MAKE_DATE(year, month, day) AS ts_updated
  FROM datalake_jira_clean.issues
  WHERE
    CAST(GET_JSON_OBJECT(fields, project.id) AS INT) = 10400
    AND MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
), exploded_attachments AS (
  SELECT
    i.id_issue,
    att.id AS id_attachment,
    att.author.accountId AS id_author_account,
    att.filename AS file_name,
    att.mimeType AS file_type,
    att.content AS file_content_url,
    att.thumbnail AS file_thumbnail,
    att.size AS file_size,
    CAST(att.created AS TIMESTAMP) AS ts_created,
    i.ts_updated,
    YEAR(TO_DATE(CAST(att.created AS TIMESTAMP))) AS year,
    MONTH(TO_DATE(CAST(att.created AS TIMESTAMP))) AS month,
    DAY(TO_DATE(CAST(att.created AS TIMESTAMP))) AS day
  FROM issues AS i
  LATERAL VIEW
  EXPLODE(
    FROM_JSON(
      attachment,
      'ARRAY<STRUCT<\n                author: STRUCT<\n                    accountId: STRING, \n                    accountType: STRING, \n                    active: BOOLEAN, \n                    avatarUrls: STRUCT<`16x16`: STRING, `24x24`: STRING, `32x32`: STRING, `48x48`: STRING>, \n                    displayName: STRING, \n                    emailAddress: STRING, \n                    self: STRING, timeZone: STRING\n                >, \n                content: STRING, \n                created: STRING, \n                filename: STRING, \n                id: STRING, \n                mimeType: STRING, \n                self: STRING, \n                size: BIGINT, \n                thumbnail: STRING\n            >>'
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
FROM (
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
    day,
    ROW_NUMBER() OVER (PARTITION BY id_issue, id_attachment ORDER BY ts_updated DESC) AS _w
  FROM exploded_attachments
) AS _t
WHERE
  1 = _w