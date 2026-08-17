SELECT
  id_house,
  CAST(NULLIF(
    LAST(has_bathtub) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_bathtub,
  CAST(NULLIF(
    LAST(has_shower_enclosure) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_shower_enclosure,
  CAST(NULLIF(
    LAST(has_balcony) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_balcony,
  CAST(NULLIF(
    LAST(has_stove_and_refrigerator) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_stove_and_refrigerator,
  CAST(NULLIF(
    LAST(has_private_pool) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_private_pool,
  CAST(NULLIF(
    LAST(has_bedroom_closets) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_bedroom_closets,
  CAST(NULLIF(
    LAST(has_bathroom_cabinets) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_bathroom_cabinets,
  CAST(NULLIF(
    LAST(has_kitchen_cabinets) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_kitchen_cabinets,
  CAST(NULLIF(
    LAST(has_air_conditioning) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_air_conditioning,
  CAST(NULLIF(
    LAST(has_gas_shower) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_gas_shower,
  CAST(NULLIF(
    LAST(has_pets_allowed) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_pets_allowed,
  CAST(NULLIF(
    LAST(has_maid_room) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_maid_room,
  CAST(NULLIF(
    LAST(has_maid_bathroom) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_maid_bathroom,
  CAST(NULLIF(
    LAST(has_assigned_parking_space) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_assigned_parking_space,
  CAST(NULLIF(
    LAST(has_gourmet_balcony) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_gourmet_balcony,
  CAST(NULLIF(
    LAST(is_penthouse_apartment) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS is_penthouse_apartment,
  CAST(NULLIF(
    LAST(has_reversible_extra_room) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_reversible_extra_room,
  CAST(NULLIF(
    LAST(has_stove) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_stove,
  CAST(NULLIF(
    LAST(has_refrigerator) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_refrigerator,
  CAST(NULLIF(
    LAST(has_morning_sun) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_morning_sun,
  CAST(NULLIF(
    LAST(has_afternoon_sun) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_afternoon_sun,
  CAST(NULLIF(
    LAST(has_blackout_curtains) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_blackout_curtains,
  CAST(NULLIF(
    LAST(has_sheer_curtain) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_sheer_curtain,
  CAST(NULLIF(
    LAST(has_soundproof_window) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_soundproof_window,
  CAST(NULLIF(
    LAST(has_ceiling_fan) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_ceiling_fan,
  CAST(NULLIF(
    LAST(has_large_windows) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_large_windows,
  CAST(NULLIF(
    LAST(has_unobstructed_view) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_unobstructed_view,
  CAST(NULLIF(
    LAST(has_quiet_street) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_quiet_street,
  CAST(NULLIF(
    LAST(has_electric_shower) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_electric_shower,
  CAST(NULLIF(
    LAST(has_microwave) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_microwave,
  CAST(NULLIF(
    LAST(has_sofa) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_sofa,
  CAST(NULLIF(
    LAST(has_washing_machine) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_washing_machine,
  CAST(NULLIF(
    LAST(has_dryer) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_dryer,
  CAST(NULLIF(
    LAST(has_washer_dryer_combo) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_washer_dryer_combo,
  CAST(NULLIF(
    LAST(has_laundry_sink) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_laundry_sink,
  CAST(NULLIF(
    LAST(has_window_screens) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_window_screens,
  CAST(NULLIF(
    LAST(has_clothesline) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_clothesline,
  CAST(NULLIF(
    LAST(has_three_pin_outlets) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_three_pin_outlets,
  CAST(NULLIF(
    LAST(has_television) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_television,
  CAST(NULLIF(
    LAST(has_dining_tables_and_chairs) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_dining_tables_and_chairs,
  CAST(NULLIF(
    LAST(has_coffee_maker) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_coffee_maker,
  CAST(NULLIF(
    LAST(has_barbecue) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_barbecue,
  CAST(NULLIF(
    LAST(has_step_free_access) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_step_free_access,
  CAST(NULLIF(
    LAST(has_cooktop) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_cooktop,
  CAST(NULLIF(
    LAST(has_kitchen_utensils) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_kitchen_utensils,
  CAST(NULLIF(
    LAST(has_double_bed) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_double_bed,
  CAST(NULLIF(
    LAST(has_single_bed) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_single_bed,
  CAST(NULLIF(
    LAST(has_bathroom_mirror) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_bathroom_mirror,
  CAST(NULLIF(
    LAST(has_electronic_lock) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_electronic_lock,
  CAST(NULLIF(
    LAST(has_electricity_included) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_electricity_included,
  CAST(NULLIF(
    LAST(has_adapted_bathroom) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_adapted_bathroom,
  CAST(NULLIF(
    LAST(has_walk_in_closet) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_walk_in_closet,
  CAST(NULLIF(
    LAST(has_open_kitchen) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_open_kitchen,
  CAST(NULLIF(
    LAST(has_office_tables_and_chairs) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_office_tables_and_chairs,
  CAST(NULLIF(
    LAST(has_garden) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_garden,
  CAST(NULLIF(
    LAST(has_spacious_rooms_and_corridors_doors) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_spacious_rooms_and_corridors_doors,
  CAST(NULLIF(
    LAST(has_backyard) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_backyard,
  CAST(NULLIF(
    LAST(has_single_house_on_the_property) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_single_house_on_the_property,
  CAST(NULLIF(
    LAST(has_laundry_area) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_laundry_area,
  CAST(NULLIF(
    LAST(has_private_garden_area) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_private_garden_area,
  CAST(NULLIF(
    LAST(has_elevator) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_elevator,
  CAST(NULLIF(
    LAST(has_playground) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_playground,
  CAST(NULLIF(
    LAST(has_condo_pool) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_condo_pool,
  CAST(NULLIF(
    LAST(has_condo_grill_area) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_condo_grill_area,
  CAST(NULLIF(
    LAST(has_sports_court) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_sports_court,
  CAST(NULLIF(LAST(has_gym) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change), 'NULL') AS BOOLEAN) AS has_gym,
  CAST(NULLIF(
    LAST(has_party_hall) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_party_hall,
  CAST(NULLIF(
    LAST(has_sauna) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_sauna,
  CAST(NULLIF(
    LAST(has_condo_laundry) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_condo_laundry,
  CAST(NULLIF(
    LAST(has_piped_gas) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_piped_gas,
  CAST(NULLIF(
    LAST(has_automatic_gate) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_automatic_gate,
  CAST(NULLIF(
    LAST(has_gourmet_area) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_gourmet_area,
  CAST(NULLIF(
    LAST(is_near_metro_or_train) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS is_near_metro_or_train,
  CAST(NULLIF(
    LAST(has_playroom) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_playroom,
  CAST(NULLIF(
    LAST(has_handrail) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_handrail,
  CAST(NULLIF(
    LAST(has_tactile_floor) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_tactile_floor,
  CAST(NULLIF(
    LAST(has_access_ramps) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_access_ramps,
  CAST(NULLIF(
    LAST(has_game_room) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_game_room,
  CAST(NULLIF(
    LAST(has_accessible_parking_space) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_accessible_parking_space,
  CAST(NULLIF(
    LAST(has_green_area) IGNORE NULLS OVER (PARTITION BY id_house ORDER BY ts_change),
    'NULL'
  ) AS BOOLEAN) AS has_green_area,
  ROW_NUMBER() OVER (PARTITION BY id_house, CAST(ts_change AS DATE) ORDER BY ts_change DESC) = 1 AS is_last_status_of_day,
  ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_change DESC) = 1 AS is_current_version,
  ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_change) AS version,
  ts_change AS ts_version_started,
  LEAD(ts_change) OVER (PARTITION BY id_house ORDER BY ts_change) AS ts_version_ended
FROM (
  SELECT
    id_house,
    id_amenity,
    is_condo_amenity,
    COALESCE(CAST(has_feature AS STRING), 'NULL') AS has_feature,
    ts_change
  FROM datalake_ebdb_amenities.amenity_change_history AS ah
)
PIVOT(MAX(has_feature) FOR (id_amenity, is_condo_amenity) IN ((1, FALSE) /* House amenities */ AS has_bathtub, (2, FALSE) AS has_shower_enclosure, (3, FALSE) AS has_balcony, (4, FALSE) AS has_stove_and_refrigerator, (5, FALSE) AS has_private_pool, (7, FALSE) AS has_bedroom_closets, (8, FALSE) AS has_bathroom_cabinets, (9, FALSE) AS has_kitchen_cabinets, (10, FALSE) AS has_air_conditioning, (12, FALSE) AS has_gas_shower, (13, FALSE) AS has_pets_allowed, (14, FALSE) AS has_maid_room, (15, FALSE) AS has_maid_bathroom, (16, FALSE) AS has_assigned_parking_space, (17, FALSE) AS has_gourmet_balcony, (18, FALSE) AS is_penthouse_apartment, (19, FALSE) AS has_reversible_extra_room, (20, FALSE) AS has_stove, (21, FALSE) AS has_refrigerator, (22, FALSE) AS has_morning_sun, (23, FALSE) AS has_afternoon_sun, (24, FALSE) AS has_blackout_curtains, (25, FALSE) AS has_sheer_curtain, (26, FALSE) AS has_soundproof_window, (27, FALSE) AS has_ceiling_fan, (28, FALSE) AS has_large_windows, (29, FALSE) AS has_unobstructed_view, (30, FALSE) AS has_quiet_street, (31, FALSE) AS has_electric_shower, (32, FALSE) AS has_microwave, (33, FALSE) AS has_sofa, (34, FALSE) AS has_washing_machine, (35, FALSE) AS has_dryer, (36, FALSE) AS has_washer_dryer_combo, (37, FALSE) AS has_laundry_sink, (38, FALSE) AS has_window_screens, (39, FALSE) AS has_clothesline, (40, FALSE) AS has_three_pin_outlets, (41, FALSE) AS has_television, (42, FALSE) AS has_dining_tables_and_chairs, (43, FALSE) AS has_coffee_maker, (44, FALSE) AS has_barbecue, (45, FALSE) AS has_step_free_access, (46, FALSE) AS has_cooktop, (47, FALSE) AS has_kitchen_utensils, (48, FALSE) AS has_double_bed, (49, FALSE) AS has_single_bed, (50, FALSE) AS has_bathroom_mirror, (51, FALSE) AS has_electronic_lock, (52, FALSE) AS has_electricity_included, (53, FALSE) AS has_adapted_bathroom, (54, FALSE) AS has_walk_in_closet, (55, FALSE) AS has_open_kitchen, (56, FALSE) AS has_office_tables_and_chairs, (57, FALSE) AS has_garden, (58, FALSE) AS has_spacious_rooms_and_corridors_doors, (59, FALSE) AS has_backyard, (60, FALSE) AS has_single_house_on_the_property, (61, FALSE) AS has_laundry_area, (62, FALSE) AS has_private_garden_area, (0, TRUE) /* Condo amenities */ AS has_elevator, (1, TRUE) AS has_playground, (2, TRUE) AS has_condo_pool, (3, TRUE) AS has_condo_grill_area, (4, TRUE) AS has_sports_court, (5, TRUE) AS has_gym, (6, TRUE) AS has_party_hall, (7, TRUE) AS has_sauna, (8, TRUE) AS has_condo_laundry, (9, TRUE) AS has_piped_gas, (10, TRUE) AS has_automatic_gate, (11, TRUE) AS has_gourmet_area, (12, TRUE) AS is_near_metro_or_train, (13, TRUE) AS has_playroom, (14, TRUE) AS has_handrail, (15, TRUE) AS has_tactile_floor, (16, TRUE) AS has_access_ramps, (17, TRUE) AS has_game_room, (18, TRUE) AS has_accessible_parking_space, (19, TRUE) AS has_green_area))