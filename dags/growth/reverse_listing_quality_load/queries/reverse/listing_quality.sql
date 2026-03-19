-- Ver.  Trino
WITH
    base_fl AS (
        SELECT
            sk_house AS id_house,
            MIN(date) AS dt_fl, -- NOTA: acho que não precisa desse dado
            MIN_BY(planning_operation, date) AS planning_operation -- NOTA: acho que não precisa desse dado
        FROM
            dw_growth.obt_supply
        WHERE
            cd_funnel_step = 'first_listing'
        GROUP BY
            sk_house
        HAVING
            MIN_BY(planning_operation, date) NOT IN ('Rede', 'Mercado Primário BH')
            AND MIN_BY(sk_user_conversion, date) NOT IN (8919771, 11299701, 6001450) -- para não considerar casos de 3P FR
            AND MIN_BY(sk_user_affiliate, date) NOT IN (12306405, 14046860, 14053116, 14046994, 14217303) -- para não considerar casos de 3P FR
            AND MIN(date) >= DATE('{load_start_date}')
            AND MIN(date) < DATE('{load_end_date}')
    ), -- ids de imóveis de 1p publicados em first listing no intervalo


    base_geral_last_job AS (
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
    ), -- registro de todos os ids de imóveis com job, puxando o id do job mais recente, a respectiva data de upload, e o id_photographer_data do FT do job


-- nota: substitui a base_fl_sem_job_sem_ticket
    base_fl_sem_job AS (
        SELECT DISTINCT
            a.id_house,
            a.dt_fl,
            b.id_job,
            b.ts_photos_uploaded
        -- c.sk_ticket
        FROM base_fl a
                 LEFT JOIN base_geral_last_job b ON (a.id_house = b.id_house)
        WHERE b.id_job IS NULL -- condição para considerar o que não tem job
          -- AND c.sk_ticket IS NULL -- condição para considerar o que não passou por LQ
          -- Nota: Precisa mesmo dessa informação? pois agora o hightouch vai garantir que puxa apenas listagens ainda sem tickets criados....

          AND b.user_sender_type IS DISTINCT FROM 'OWNER' -- condição para considerar o que não é de FotosPP
    ), -- ids dos imóveis publicados em first listing que não tiveram job, não vieram de FotosPP


-- nota: substitui a base_last_job_sem_ticket
    base_recent_job AS (
        SELECT
            id_house,
            id_job,
            ts_photos_uploaded,
            id_photographer_data,
            user_sender_type
        FROM base_geral_last_job
        WHERE CAST(ts_photos_uploaded AS DATE) >= DATE('{load_start_date}')
          AND CAST(ts_photos_uploaded AS DATE) < DATE('{load_end_date}')
    ), -- puxa os ids de imóveis e jobs que tiveram o upload de fotos (trigger para publicação) ainda não processados pela DAG


    base_ims_completa AS (
        SELECT
            id_house,
            -- 'fl_sem_job' AS "type",
            NULL AS id_job,
            NULL AS ts_photos_uploaded,
            NULL AS id_photographer_data,
            NULL AS user_sender_type
        FROM base_fl_sem_job

        UNION ALL

        SELECT
            id_house,
            -- 'com_job' AS "type",
            id_job,
            ts_photos_uploaded,
            id_photographer_data,
            user_sender_type
        FROM base_recent_job
    ),

-- 5. Join com 'base_ims_completa'
    ims_details AS (
        SELECT
            a.id_house,
            a.id_job,
            CAST(MIN(c.ts_first_publication) AS DATE) AS dt_first_publication,
            CAST(MAX(c.ts_last_publication) AS DATE) AS dt_last_publication,

            a.ts_photos_uploaded,
            e.bathrooms,
            (e.bathrooms + e.bedrooms + 2) AS comodos_from_house,
            CASE WHEN e.type = 'StudioOuKitchenette' THEN true ELSE false END AS studio_kitnet,
            e.internal_admin_info,

            e.id_user AS pp_user_id

        FROM base_ims_completa a

            LEFT JOIN datalake_ebdb_clean.listing_business_context c
            ON a.id_house = c.id_house

            LEFT JOIN datalake_ebdb_clean.house e
            ON a.id_house = e.id

            LEFT JOIN datalake_ebdb_user.user g
            ON e.id_user = g.id

            LEFT JOIN dw_public.dim_region h
            ON e.id_region = h.sk_region

            LEFT JOIN dw_datamarts.house_media i
            ON a.id_house = CAST(i.id_house AS BIGINT)

            LEFT JOIN datalake_ebdb_user.user j
            ON (a.id_photographer_data = j.id_photographer_data) -- JOIN agora usa 'a'

        GROUP BY a.id_house, a.id_job, a.ts_photos_uploaded, e.bathrooms, e.bedrooms, e.type, e.internal_admin_info, e.id_user
    ), -- reune as informações dos imóveis como quantidade de quartos e banheiros (informados pelo pp), a descrição do im, informação interna vindo do admin, contagem de vídeos por imóvel, dados do fotógrado e do proprietário


    last_inspection AS (
        SELECT
            id_house,
            MAX(id_group) AS last_id_group
        FROM dw_public.fact_kodak_image_inspection
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
        --CAST(b.ts_created AS DATE) AS inspection_restb
        FROM last_inspection a
            LEFT JOIN dw_public.fact_kodak_image_inspection b
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
            a.dt_last_publication,
            a.ts_photos_uploaded,
            COUNT(DISTINCT b.sk_image_inspection) AS images
        FROM ims_details a
            LEFT JOIN fact_kodak_consolidated b ON (a.id_house = b.id_house)
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
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
            comodos_from_house,
            ROUND(CAST(SUM(a.images) AS DOUBLE) / comodos_from_house, 1) AS images_per_room_from_house
        FROM details_inspection a
            LEFT JOIN ims_details b ON (a.id_house = b.id_house)
        GROUP BY 1, 2, 4
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
            MAX_BY(id_source, id) AS id_source,
            MAX_BY(video_source, id) AS video_source,
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
    a.dt_last_publication,
    a.ts_photos_uploaded,
    date_diff(DAY, a.ts_photos_uploaded, a.inspection_restb) AS dif_publication_inspection,

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    ELSE a.property_condition END AS property_condition, -- property_condition do im, desconsiderando quando a data da inspeção vem antes da data do último upload de fotos (publicação)

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    WHEN a.property_condition <= 2.7 OR a.property_condition IS NULL THEN true
    ELSE false END AS verificacao_score, -- se o property_condition é menor ou igual a 2.7 ou nulo, será necessária verificação manual

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    ELSE NOT d.has_bathroom END AS verificacao_banheiro, -- se não há pelo menos 1 foto de banheiro identificada, será necessária verificação manual

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    WHEN (b.studio_kitnet AND b.images_per_room_from_house < 1.5) THEN true
    WHEN (NOT b.studio_kitnet AND b.images_per_room_from_house < 3) THEN true
    ELSE false END AS verificacao_fotos_x_comodo, -- quando o im é studio ou kitnet e a média de fotos por cômodo é inferior a 1.5 ou quando o im não é studio ou kitnet e a média de fotos por cômodo é inferior a 3, necessita verificação manual

    CASE
    WHEN date_diff(MINUTE, a.ts_photos_uploaded, a.inspection_restb) NOT BETWEEN 0 AND 30 THEN NULL
    ELSE c.placa_identificada END AS verificacao_placa, -- puxa a flag que sinaliza a verificação quando há placa identificada, excluindo casos em que a inspeção do restb aconteceu antes da data da última publicação

    b.total_internal_images,
    b.comodos_from_house,
    b.images_per_room_from_house
FROM details_inspection a
    LEFT JOIN images_x_rooms b ON (a.id_house = b.id_house)
    LEFT JOIN placas_check c ON (a.id_house = c.id_house)
    LEFT JOIN basic_room_bathroom d ON (a.id_house = d.id_house)
    ) -- consolida as informações relacionadas à inspeção do restb e cria as regras de verificação, incluindo em todos os cenários que casos em que a data da inspeção vem antes da data da última publicação, será tratado como se não houvesse inspeção


SELECT  DISTINCT
    a.id_house as house_id, -- houseId
    a.id_job as job_id, -- photo jobId
    a.internal_admin_info as photographer_comment, -- commentPhotographer
    c.link_video, -- videoLink
    b.total_internal_images as num_internal_photos, -- numInternalPhotos
    b.images_per_room_from_house as images_per_room, -- imagesPerRoom
    b.property_condition, -- propertyCondition
    NOT b.verificacao_banheiro as has_bathroom_photo, -- bathrooms
    NOT b.verificacao_placa as has_plaque, -- hasPlaque
    CASE
        WHEN b.property_condition IS NULL THEN 0
        WHEN (b.verificacao_score OR b.verificacao_banheiro OR b.verificacao_fotos_x_comodo) THEN 1
        WHEN (NOT b.verificacao_score OR NOT b.verificacao_banheiro OR NOT b.verificacao_fotos_x_comodo) AND b.verificacao_placa THEN 2
        WHEN (NOT b.verificacao_score OR NOT b.verificacao_banheiro OR NOT b.verificacao_fotos_x_comodo) AND NOT b.verificacao_placa THEN 3
        END AS analyst_queue -- analystQueue
-- casos sem inspeção ou com inspeção inválida são identificados quando a coluna property_condition é nula e terão encaminhamento 0.
-- casos que sinalizam a necessidade de pelo menos uma das verificações de padrão (property_condition abaixo da nota de corte, sem foto de banheiro ou média de fotos por cômodo abaixo do esperado) terão encaminhamento 1.
-- casos sem sinalização de necessidade de verificação de padrão, mas com placa identificada pelo restb, terão encaminhamento 2.
-- casos sem sinalização de necessidade de verificação de padrão e sem placa identificada pelo restb, terão encaminhamento 3.
FROM ims_details a
         LEFT JOIN base_formatada_kodak b ON (a.id_house = b.id_house)
         LEFT JOIN videos c ON (c.id_external_domain = a.id_house)
ORDER BY analyst_queue ASC, property_condition ASC
