SELECT
    CAST(id AS BIGINT) AS id,
    CAST(audit_id AS BIGINT) AS id_audit,
    CAST(author_id AS BIGINT) AS id_author,
    CAST(ticket_id AS BIGINT) AS id_ticket,
    FROM_JSON(
        attachments,
        'array<struct<content_type:string,content_url:string,file_name:string,height:bigint,id:bigint,inline:boolean,mapped_content_url:string,size:bigint,thumbnails:array<struct<content_type:string,content_url:string,file_name:string,height:bigint,id:bigint,inline:boolean,mapped_content_url:string,size:bigint,url:string,width:bigint>>,url:string,width:bigint>>'
    ) AS attachments,
    body,
    plain_body,
    type,
    FROM_JSON(
        via,
        'struct<channel:string,source:struct<from:struct<address:string,deleted:boolean,id:bigint,name:string,original_recipients:array<string>,subject:string,ticket_id:bigint,ticket_ids:array<bigint>,title:string>,rel:string,to:struct<address:string,name:string>>>'
    ) AS via,
    CAST(public AS BOOLEAN) AS is_public,
    CAST(dt AS DATE) AS dt_extracted,
    created_at AS ts_created,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    datalake_velo_zendesk_raw.ticket_comments
WHERE
    dt = DATE('{year}-{month}-{day}')
