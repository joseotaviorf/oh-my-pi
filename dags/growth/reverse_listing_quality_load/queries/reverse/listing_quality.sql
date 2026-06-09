-- Ver.  Trino
WITH
    base_recent_job AS (
        SELECT
            id_house,
            MAX(id) AS id_job,
            MAX_BY(ts_photos_uploaded, id) AS ts_photos_uploaded,
            MAX_BY(id_photographer_data, id) AS id_photographer_data,
            MAX_BY(photo_sender_user_type, id) AS user_sender_type
        FROM
            datalake_ebdb_clean.photographer_job
        WHERE
            status IN ('Publicado', 'Completado')
        GROUP BY
            id_house
        HAVING
            CAST(MAX_BY(ts_photos_uploaded, id) AS DATE) >= DATE('{load_start_date}')
            AND CAST(MAX_BY(ts_photos_uploaded, id) AS DATE) < DATE('{load_end_date}')
    ), -- imóveis com job publicado/completado cujo upload de fotos ocorreu no intervalo da DAG


-- 5. Join com 'base_recent_job'
    ims_details AS (
        SELECT
            a.id_house,
            a.id_job,

            a.ts_photos_uploaded,
            e.bathrooms,
            (e.bathrooms + e.bedrooms + 2) AS comodos_from_house,
            CASE WHEN e.type = 'StudioOuKitchenette' THEN true ELSE false END AS studio_kitnet,
            e.internal_admin_info

        FROM base_recent_job a

            LEFT JOIN datalake_ebdb_clean.house e
            ON a.id_house = e.id

GROUP BY a.id_house, a.id_job, a.ts_photos_uploaded, e.bathrooms, e.bedrooms, e.type, e.internal_admin_info
    ), -- reune as informações dos imóveis como quantidade de quartos e banheiros (informados pelo pp), a descrição do im, informação interna vindo do admin, contagem de vídeos por imóvel, dados do fotógrado e do proprietário

    -- Core join kodak clean tables
    kodak_inspection_houses AS (
        SELECT
            id,
            id_external
        FROM
            datalake_ebdb_clean.house
        WHERE
            id_external IS NOT NULL
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY id_external ORDER BY dt_creation) = 1
    ),
    fact_kodak_image_inspection_inline AS (
        SELECT
            im.id AS sk_image_inspection,
            im.id_group,
            h.id AS id_house,
            im.house_place,
            im.room_type,
            ig.property_condition,
            im.ts_created
        FROM
            datalake_kodak_clean.image_inspection AS im
        INNER JOIN
            datalake_kodak_clean.image_inspection_group AS ig
                ON ig.id = im.id_group
        LEFT JOIN
            kodak_inspection_houses AS h
            ON (ig.external_domain = 'LEAD3P' AND ig.id_external_domain = h.id_external
                OR ig.external_domain != 'LEAD3P' AND ig.id_external_domain = h.id)
    ),

    last_inspection AS (
        SELECT
            id_house,
            MAX(id_group) AS last_id_group
        FROM
                fact_kodak_image_inspection_inline
        GROUP BY id_house
    ), -- id_group mais recente para cada id_house inspecionado (que passou pelo restb)

    fact_kodak_consolidated AS (
        SELECT
            a.id_house,
            a.last_id_group,
            b.property_condition,
            b.room_type,
            b.sk_image_inspection,
            b.ts_created AS inspection_restb
        FROM
            last_inspection AS a
        LEFT JOIN
            fact_kodak_image_inspection_inline AS b
            ON a.last_id_group = b.id_group
            AND b.house_place = 'INTERNAL'
    ), -- ids das imagens inspecionadas identificadas como de ambiente interno, seu respectivo cômodo identificado, e o score (property_condition) do im, de acordo com o id_group mais recente de cada imóvel inspecionado pelo restb


    details_inspection AS (
        SELECT
            a.id_house,
            b.last_id_group AS id_group,
            b.property_condition,
            CASE WHEN b.room_type = 'bathroom' THEN true ELSE false END AS has_bathroom,
            b.room_type,
            b.inspection_restb,
            a.ts_photos_uploaded,
            COUNT(DISTINCT b.sk_image_inspection) AS images
        FROM ims_details a
            LEFT JOIN fact_kodak_consolidated b ON (a.id_house = b.id_house)
        GROUP BY 1, 2, 3, 4, 5, 6, 7
    ), -- reúne informações puxadas nas CTEs anteriores, adionando uma coluna para identificar quando o cômodo for um banheiro e a contagem de fotos por cômodo

    basic_room_bathroom AS (
        SELECT
            id_house,
            BOOL_OR(has_bathroom) AS has_bathroom
        FROM details_inspection
        GROUP BY 1
    ), -- a partir de CTE anterior, identifica os IMs que possuem pelo menos 1 foto de banheiro

    images_x_rooms AS (
        SELECT
            a.id_house,
            b.studio_kitnet,
            SUM(a.images) AS total_internal_images,
            SUM(IF(a.room_type = 'bathroom', a.images, 0)) AS total_bathroom_images,
            comodos_from_house,
            ROUND(CAST(SUM(a.images) AS DOUBLE) / comodos_from_house, 1) AS images_per_room_from_house
        FROM details_inspection a
            LEFT JOIN ims_details b ON (a.id_house = b.id_house)
        GROUP BY 1, 2, 5
    ), -- soma de fotos por cômodo, cálculo de média de fotos por cômodo - possui outras colunas no select apenas porque serão usadas mais pra frente

    placas_check AS (
        SELECT DISTINCT
            a.id_house,
            b.id_inspection_group,
            CASE
            WHEN result LIKE '%qr_code%'
            OR result LIKE '%phone_number%'
            OR result LIKE '%sign_post%'
            THEN true ELSE false
            END AS placa_identificada
        FROM details_inspection a
            LEFT JOIN datalake_kodak_clean.group_analysis b ON (a.id_group = b.id_inspection_group)
    ), -- consulta diretamente no JSON da inspeção do restb os termos 'qr_code', 'phone_number' ou 'sign_post', criando uma flag que será considerada como 'placa_identificada'

    videos AS (
        SELECT
            id_external_domain,
            MAX_BY(id, id) AS id,
            MAX_BY(
            CASE
            WHEN video_source = 'VIMEO' THEN CONCAT('https://vimeo.com/', id_source)
            WHEN video_source = 'YOUTUBE' THEN CONCAT('https://www.youtube.com/watch', chr(63), 'v=', id_source)
            ELSE CONCAT('sourceDesconhecida', id_source)
            END,
            id
            ) AS link_video
        FROM datalake_kodak_clean.video
        GROUP BY id_external_domain
    ), -- url de vídeo mais recente para o im

    base_formatada_kodak AS (
SELECT DISTINCT
    a.id_house,
    a.id_group,
    a.inspection_restb,
    a.ts_photos_uploaded,
    date_diff(DAY, a.ts_photos_uploaded, a.inspection_restb) AS dif_publication_inspection,

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    ELSE a.property_condition END AS property_condition, -- property_condition do im, desconsiderando quando a data da inspeção vem antes da data do último upload de fotos (publicação)

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    WHEN a.property_condition <= 2.7 OR a.property_condition IS NULL THEN true
    ELSE false END AS verificar_ai_score, -- se o property_condition é menor ou igual a 2.7 ou nulo, será necessária verificação manual

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    ELSE NOT d.has_bathroom END AS verificar_banheiro, -- se não há pelo menos 1 foto de banheiro identificada, será necessária verificação manual

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    WHEN (b.studio_kitnet AND b.images_per_room_from_house < 1.5) THEN true
    WHEN (NOT b.studio_kitnet AND b.images_per_room_from_house < 3) THEN true
    ELSE false END AS verificar_fotos_x_comodo, -- quando o im é studio ou kitnet e a média de fotos por cômodo é inferior a 1.5 ou quando o im não é studio ou kitnet e a média de fotos por cômodo é inferior a 3, necessita verificação manual

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    ELSE c.placa_identificada END AS verificar_placa, -- puxa a flag que sinaliza a verificação quando há placa identificada, excluindo casos em que a inspeção do restb aconteceu antes da data da última publicação

    b.total_internal_images,
    b.total_bathroom_images,
    b.comodos_from_house,
    b.images_per_room_from_house
FROM details_inspection a
    LEFT JOIN images_x_rooms b ON (a.id_house = b.id_house)
    LEFT JOIN placas_check c ON (a.id_house = c.id_house)
    LEFT JOIN basic_room_bathroom d ON (a.id_house = d.id_house)
    ), -- consolida as informações relacionadas à inspeção do restb e cria as regras de verificação, incluindo em todos os cenários que casos em que a data da inspeção vem antes da data da última publicação, será tratado como se não houvesse inspeção

    base_analysis_request AS (
        SELECT
            id_house
        FROM datalake_ebdb_clean.listing_quality_analysis_request
        WHERE ts_created >= DATE('{load_start_date}')
          AND ts_created < DATE('{load_end_date}')
          AND analysis_requested = true
          AND id_house NOT IN (SELECT id_house FROM ims_details)
    ) -- requisições de análise submetidas no magiclink (após enviar fotos pelo magiclink)


SELECT
    -- temporary uuid, used only on hightouch (for handling key|duplicates)
    cast(uuid() AS string) AS uuid_listing_quality,
    t.house_id,
    t.job_id,
    t.photographer_comment,
    t.link_video,
    t.num_internal_photos,
    t.num_bathroom_photos,
    t.images_per_room,
    t.property_condition,
    t.has_plaque,
    t.analyst_queue
FROM (
    SELECT DISTINCT
        a.id_house AS house_id, -- houseId
        a.id_job AS job_id, -- photo jobId
        a.internal_admin_info AS photographer_comment, -- commentPhotographer
        c.link_video, -- videoLink
        b.total_internal_images AS num_internal_photos, -- numInternalPhotos
        b.total_bathroom_images AS num_bathroom_photos, -- numBathroomPhotos
        b.images_per_room_from_house AS images_per_room, -- imagesPerRoom
        b.property_condition, -- propertyCondition
        b.verificar_placa AS has_plaque, -- hasPlaque
        CASE
            WHEN b.property_condition IS NULL THEN 0
            WHEN (b.verificar_ai_score OR b.verificar_banheiro OR b.verificar_fotos_x_comodo) THEN 1
            WHEN (NOT b.verificar_ai_score OR NOT b.verificar_banheiro OR NOT b.verificar_fotos_x_comodo) AND b.verificar_placa THEN 2
            WHEN (NOT b.verificar_ai_score OR NOT b.verificar_banheiro OR NOT b.verificar_fotos_x_comodo) AND NOT b.verificar_placa THEN 3
            END AS analyst_queue -- analystQueue
    -- casos sem inspeção ou com inspeção inválida são identificados quando a coluna property_condition é nula e terão encaminhamento 0.
    -- casos que sinalizam a necessidade de pelo menos uma das verificações de padrão (property_condition abaixo da nota de corte, sem foto de banheiro ou média de fotos por cômodo abaixo do esperado) terão encaminhamento 1.
    -- casos sem sinalização de necessidade de verificação de padrão, mas com placa identificada pelo restb, terão encaminhamento 2.
    -- casos sem sinalização de necessidade de verificação de padrão e sem placa identificada pelo restb, terão encaminhamento 3.
    FROM ims_details a
        LEFT JOIN base_formatada_kodak b ON (a.id_house = b.id_house)
        LEFT JOIN videos c ON (c.id_external_domain = a.id_house)

    UNION ALL

    SELECT DISTINCT
        ar.id_house AS house_id,
        NULL AS job_id,
        NULL AS photographer_comment,
        NULL AS link_video,
        NULL AS num_internal_photos,
        NULL AS num_bathroom_photos,
        NULL AS images_per_room,
        NULL AS property_condition,
        NULL AS has_plaque,
        0 AS analyst_queue
    FROM base_analysis_request ar
) t
ORDER BY t.analyst_queue ASC, t.property_condition ASC
