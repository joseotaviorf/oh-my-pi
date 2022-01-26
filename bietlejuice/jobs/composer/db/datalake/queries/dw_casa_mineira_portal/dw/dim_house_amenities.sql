WITH data_amenities AS (
    WITH data_houses AS (
        SELECT 
            house.id,
            house.total_area,
            house.bathrooms,
            house.bedrooms,
            house.living_rooms,
            house.suites,
            house.parking_slots,
            house.liquidity,
            house.ts_created
        FROM 
            datalake_casa_mineira_portal_clean.house AS house
        WHERE
            house.id IS NOT NULL
            AND house.id NOT REGEXP '[a-zA-Z]'
    ), 
    data_house_attributes AS (
        SELECT *
        FROM 
            (
            SELECT 
                house_attribute.id_house,
                concat(attribute.attribute_name, '_',attribute_type.attribute_name) AS nome_atributo,
                1 AS has_attribute 
            FROM 
                datalake_casa_mineira_portal_clean.house_attribute AS house_attribute
            LEFT JOIN 
                datalake_casa_mineira_portal_clean.attribute AS attribute 
                    ON house_attribute.id_attribute = attribute.id
            LEFT JOIN 
                datalake_casa_mineira_portal_clean.attribute_type AS attribute_type 
                    ON attribute.id_attribute_type = attribute_type.id
            WHERE 
                house_attribute.ts_deleted IS NULL
            )
            PIVOT (
                MAX(has_attribute)
            FOR (nome_atributo) IN (
                'Academia_Edifício' AS has_gym_edifice,
                'Acessibilidade_Edifício' AS has_accessibility_edifice,
                'Banho Empregada_Imóvel' AS has_housekeeper_bathroom_house,
                'Bicicletário_Edifício' AS has_bicycle_stand_edifice,
                'Box Blindex_Imóvel' AS has_blindex_box_house,
                'Churrasqueira_Edifício' AS has_grill_edifice,
                'Closet_Imóvel' AS has_closet_house,
                'Cozinha Americana_Imóvel' AS has_american_kitchen_house,
                'Cozinha_Armário' AS has_kitchen_cabinet,
                'Câmeras de Segurança_Edifício' AS has_security_camera_edifice,
                'Despensa_Imóvel' AS has_pantry_house,
                'Elevador_Edifício' AS has_elevator_edifice,
                'Espaço Gourmet_Edifício' AS has_gourmet_space_edifice,
                'Espaço Kids_Edifício' AS has_kids_space_edifice,
                'Guarita_Edifício' AS has_security_cabin_edifice,
                'Gás Canalizado_Edifício' AS has_canalized_gas_edifice,
                'Hidromassagem_Imóvel' AS has_whirlpool_house,
                'Interfone_Edifício' AS has_intercom_edifice,
                'Lareira_Imóvel' AS has_fireplace_house,
                'Mobiliado_Imóvel' AS is_furnished_house,
                'Ofurô_Imóvel' AS has_ofuro_house,
                'Piscina Aquecida_Edifício' AS has_hot_pool_edifice,
                'Piscina Coberta_Edifício' AS has_roof_pool_edifice,
                'Piscina Infantil_Edifício' AS has_kid_pool_edifice,
                'Piscina Raia_Edifício' AS has_pool_edifice,
                'Piscina_Edifício' AS has_pool_streak_edifice,
                'Porteiro Físico_Edifício' AS has_doorman_edifice,
                'Portão Eletrônico_Edifício' AS has_electronic_gate_edifice,
                'Quarto Empregada_Imóvel' AS has_housekeeper_bedroom_house,
                'Quarto de Despejo _Imóvel' AS has_wasteroom_house, -- The space is necessary because of the attribute name
                'Rouparia_Armário' AS has_wardrobe_cabinet,
                'Salão Festas_Edifício' AS has_party_room_edifice,
                'Salão Jogos_Edifício' AS has_game_room_edifice,
                'Sauna_Edifício' AS has_sauna_edifice,
                'Sistema de Alarme_Edifício' AS has_alarm_system_edifice,
                'Spa Hidromassagem_Edifício' AS has_spa_whirlpool_edifice,
                'Vagas de Visitantes_Edifício' AS has_visitors_slot_edifice,
                'Varanda Gourmet_Imóvel' AS has_balcony_gourmet_house,
                'Varanda_Imóvel' AS has_balcony_house,
                'Vista Panorâmica_Imóvel' AS has_panoramic_view_house,
                'Água Individualizada_Edifício' AS has_individual_water_edifice,
                'Área Livre_Edifício' AS has_free_area_edifice,
                'Área Privativa_Imóvel' AS has_privace_area_house,
                'Área Serviço_Imóvel' AS has_service_area_house
            )
        )
    )
    SELECT *
    FROM
        data_house_attributes
    RIGHT JOIN
        data_houses 
            ON data_houses.id = data_house_attributes.id_house
)
SELECT
    CAST(id AS INT) AS sk_house,
    CAST(id AS INT) AS id_house,
    CAST(total_area AS SMALLINT) AS total_area,
    CAST(bathrooms AS INT) AS bathrooms,
    CAST(bedrooms AS INT) AS bedrooms,
    CAST(living_rooms AS INT) AS living_rooms,
    CAST(suites AS INT) AS suites,
    CAST(parking_slots AS INT) AS parking_slots,
    CAST(liquidity AS SMALLINT) AS liquidity,
    (has_gym_edifice IS NOT DISTINCT FROM 1) AS has_gym_edifice,
    (has_accessibility_edifice IS NOT DISTINCT FROM 1) AS has_accessibility_edifice,
    (has_housekeeper_bathroom_house IS NOT DISTINCT FROM 1) AS has_housekeeper_bathroom_house,
    (has_bicycle_stand_edifice IS NOT DISTINCT FROM 1) AS has_bicycle_stand_edifice,
    (has_blindex_box_house IS NOT DISTINCT FROM 1) AS has_blindex_box_house,
    (has_grill_edifice IS NOT DISTINCT FROM 1) AS has_grill_edifice,
    (has_closet_house IS NOT DISTINCT FROM 1) AS has_closet_house,
    (has_american_kitchen_house IS NOT DISTINCT FROM 1) AS has_american_kitchen_house,
    (has_kitchen_cabinet IS NOT DISTINCT FROM 1) AS has_kitchen_cabinet,
    (has_security_camera_edifice IS NOT DISTINCT FROM 1) AS has_security_camera_edifice,
    (has_pantry_house IS NOT DISTINCT FROM 1) AS has_pantry_house,
    (has_elevator_edifice IS NOT DISTINCT FROM 1) AS has_elevator_edifice,
    (has_gourmet_space_edifice IS NOT DISTINCT FROM 1) AS has_gourmet_space_edifice,
    (has_kids_space_edifice IS NOT DISTINCT FROM 1) AS has_kids_space_edifice,
    (has_security_cabin_edifice IS NOT DISTINCT FROM 1) AS has_security_cabin_edifice,
    (has_canalized_gas_edifice IS NOT DISTINCT FROM 1) AS has_canalized_gas_edifice,
    (has_whirlpool_house IS NOT DISTINCT FROM 1) AS has_whirlpool_house,
    (has_intercom_edifice IS NOT DISTINCT FROM 1) AS has_intercom_edifice,
    (has_fireplace_house IS NOT DISTINCT FROM 1) AS has_fireplace_house,
    (is_furnished_house IS NOT DISTINCT FROM 1) AS is_furnished_house,
    (has_ofuro_house IS NOT DISTINCT FROM 1) AS has_ofuro_house,
    (has_hot_pool_edifice IS NOT DISTINCT FROM 1) AS has_hot_pool_edifice,
    (has_roof_pool_edifice IS NOT DISTINCT FROM 1) AS has_roof_pool_edifice,
    (has_kid_pool_edifice IS NOT DISTINCT FROM 1) AS has_kid_pool_edifice,
    (has_pool_edifice IS NOT DISTINCT FROM 1) AS has_pool_edifice,
    (has_pool_streak_edifice IS NOT DISTINCT FROM 1) AS has_pool_streak_edifice,
    (has_doorman_edifice IS NOT DISTINCT FROM 1) AS has_doorman_edifice,
    (has_electronic_gate_edifice IS NOT DISTINCT FROM 1) AS has_electronic_gate_edifice,
    (has_housekeeper_bedroom_house IS NOT DISTINCT FROM 1) AS has_housekeeper_bedroom_house,
    (has_wasteroom_house IS NOT DISTINCT FROM 1) AS has_wasteroom_house,
    (has_wardrobe_cabinet IS NOT DISTINCT FROM 1) AS has_wardrobe_cabinet,
    (has_party_room_edifice IS NOT DISTINCT FROM 1) AS has_party_room_edifice,
    (has_game_room_edifice IS NOT DISTINCT FROM 1) AS has_game_room_edifice, 
    (has_sauna_edifice IS NOT DISTINCT FROM 1) AS has_sauna_edifice,
    (has_alarm_system_edifice IS NOT DISTINCT FROM 1) AS has_alarm_system_edifice,
    (has_spa_whirlpool_edifice IS NOT DISTINCT FROM 1) AS has_spa_whirlpool_edifice,
    (has_visitors_slot_edifice IS NOT DISTINCT FROM 1) AS has_visitors_slot_edifice,
    (has_balcony_gourmet_house IS NOT DISTINCT FROM 1) AS has_balcony_gourmet_house,
    (has_balcony_house IS NOT DISTINCT FROM 1) AS has_balcony_house,
    (has_panoramic_view_house IS NOT DISTINCT FROM 1) AS has_panoramic_view_house,
    (has_individual_water_edifice IS NOT DISTINCT FROM 1) AS has_individual_water_edifice,
    (has_free_area_edifice IS NOT DISTINCT FROM 1) AS has_free_area_edifice,
    (has_privace_area_house IS NOT DISTINCT FROM 1) AS has_privace_area_house,
    (has_service_area_house IS NOT DISTINCT FROM 1) AS has_service_area_house,
    CAST(ts_created AS TIMESTAMP) AS ts_created,
    NOW() AS ts_load
FROM
    data_amenities
