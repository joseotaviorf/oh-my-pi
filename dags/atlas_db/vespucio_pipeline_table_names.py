class Tables:
    source_clustering_image_model = (
        "vespucio_sources_delta.source_clustering_image_model"
    )
    source_ebdb_condo = "vespucio_sources_delta.source_ebdb_condo"
    source_kodak_metadata_condo = "vespucio_sources_delta.source_kodak_metadata_condo"
    source_navent_condo = "vespucio_sources_delta.source_navent_condo"
    source_union_condo = "vespucio_sources_delta.source_union_condo"
    source_iptu_condo = "vespucio_sources_delta.source_iptu_condo"
    source_ebdb_house = "vespucio_sources_delta.source_ebdb_house"
    # Prefer source_navent_houses_composed over source_navent_houses: recomposed each run with blocklist updates.
    source_navent_houses_composed = (
        "vespucio_sources_delta.source_navent_houses_composed"
    )
    source_navent_publisher_reputation_score = (
        "vespucio_sources_delta.source_navent_publisher_reputation"
    )
    source_union_houses = "vespucio_sources_delta.source_union_house"
    source_idactum_houses = "vespucio_sources_delta.source_idactum_houses"
    source_idactum_transactions = "vespucio_sources_delta.source_idactum_transactions"
    source_itbi_houses = "vespucio_sources_delta.source_itbi_house"
    source_iptu_houses = "vespucio_sources_delta.source_iptu_house"
    source_cnefe_houses = "vespucio_sources_delta.source_cnefe_house"
    source_loft_houses = "vespucio_sources_delta.source_loft_house"
    source_viva_real_houses = "vespucio_sources_delta.source_viva_real_house"
    source_zap_imoveis_houses = "vespucio_sources_delta.source_zap_imoveis_house"

    stage_step_condos = "vespucio_pipeline_delta.stage_step_condos"
    stage_step_houses = "vespucio_pipeline_delta.stage_step_houses"
    address_details_hash = "vespucio_pipeline_delta.address_details_hash"
    address_details_hasher_link = "vespucio_pipeline_delta.address_details_hasher_link"
    staged_parsed_complements = "vespucio_pipeline_delta.staged_parsed_complements"
    address_details_parser_join_houses = (
        "vespucio_pipeline_delta.address_details_parser_join_houses"
    )
    source_adapter_step_condos = "vespucio_pipeline_delta.source_adapter_step_condos"
    source_adapter_step_houses = "vespucio_pipeline_delta.source_adapter_step_houses"
    extract_step_condos = "vespucio_pipeline_delta.extract_step_condos"
    extract_step_houses = "vespucio_pipeline_delta.extract_step_houses"
    extract_step_houses_images = "vespucio_pipeline_delta.extract_step_houses_images"
    prioritize_step_condos = "vespucio_pipeline_delta.prioritize_step_condos"
    prioritize_step_houses = "vespucio_pipeline_delta.prioritize_step_houses"
    geocode_step_cache = "vespucio_pipeline_delta.geocode_step_cache"
    geocode_step_condos = "vespucio_pipeline_delta.geocode_step_condos"
    geocode_step_houses = "vespucio_pipeline_delta.geocode_step_houses"
    address_adjusted_step_condos = (
        "vespucio_pipeline_delta.address_adjusted_step_condos"
    )
    address_adjusted_step_houses = (
        "vespucio_pipeline_delta.address_adjusted_step_houses"
    )
    cluster_step_condos = "vespucio_pipeline_delta.cluster_step_condos"
    cluster_step_houses = "vespucio_pipeline_delta.cluster_step_houses"
    source_predict_step_houses = "vespucio_pipeline_delta.source_predict_step_houses"
    join_step_condos = "vespucio_pipeline_delta.join_step_condos"
    join_step_houses = "vespucio_pipeline_delta.join_step_houses"
    images_step_houses = "vespucio_pipeline_delta.images_step_houses"
    link_step = "vespucio_pipeline_delta.link_step"
    condo_compounds = "vespucio_prod_delta.condo_compounds"
    house_compounds = "vespucio_prod_delta.house_compounds"
    listings = "vespucio_prod_delta.listings"

    # v2 pipeline (steps_v2: core_v2_registry_step / normalization_step / address_enrich_step).
    # Sources are duplicated (own copies, suffixed _v2) so the v2 DAG runs independently of v1.
    # address_enrich_step calls the unified geocoder directly (no more reuse of v1's
    # geocode_step_cache / address_details_hasher_link / staged_parsed_complements tables).
    source_cnefe_houses_v2 = "vespucio_sources_delta.source_cnefe_house_v2"
    source_ebdb_houses_v2 = "vespucio_sources_delta.source_ebdb_house_v2"
    source_navent_houses_composed_v2 = (
        "vespucio_sources_delta.source_navent_houses_composed_v2"
    )
    source_navent_24mx_houses_composed_v2 = (
        "vespucio_sources_delta.source_navent_24mx_houses_composed_v2"
    )
    source_union_houses_v2 = "vespucio_sources_delta.source_union_house_v2"
    source_idactum_houses_v2 = "vespucio_sources_delta.source_idactum_houses_v2"
    source_idactum_transactions_v2 = (
        "vespucio_sources_delta.source_idactum_transactions_v2"
    )
    source_itbi_houses_v2 = "vespucio_sources_delta.source_itbi_house_v2"
    source_iptu_houses_v2 = "vespucio_sources_delta.source_iptu_house_v2"
    source_zap_imoveis_houses_v2 = "vespucio_sources_delta.source_zap_imoveis_house_v2"

    source_ebdb_condo_observations_v2 = (
        "vespucio_sources_delta.source_ebdb_condo_observations"
    )
    source_ebdb_condo_kodak_inference_v2 = (
        "vespucio_sources_delta.source_ebdb_condo_kodak_inference"
    )
    source_ebdb_condo_description_inference_v2 = (
        "vespucio_sources_delta.source_ebdb_condo_description_inference"
    )
    source_ebdb_house_amenities_kodak_inference_v2 = (
        "vespucio_sources_delta.source_ebdb_house_amenities_kodak_inference"
    )
    source_ebdb_house_amenities_description_inference_v2 = (
        "vespucio_sources_delta.source_ebdb_house_amenities_description_inference"
    )

    registry_step_v2 = "vespucio_pipeline_delta.registry_step"
    claims_step_v2 = "vespucio_pipeline_delta.claims_step"
    address_normalization_step_v2 = "vespucio_pipeline_delta.address_normalization_step"
    image_normalization_step_v2 = "vespucio_pipeline_delta.image_normalization_step"
    general_normalization_step_v2 = "vespucio_pipeline_delta.general_normalization_step"
    address_enrich_step_v2 = "vespucio_pipeline_delta.address_enrich_step"
    source_kodak_atlas_images_v2 = "vespucio_sources_delta.source_kodak_atlas_images"
    image_enrich_step_v2 = "vespucio_pipeline_delta.image_enrich_step"
    images_upsert_step_v2 = "vespucio_pipeline_delta.images_upsert_step"
    artifacts_v2 = "vespucio_pipeline_delta.artifacts_step"
    match_anchors_v2 = "vespucio_pipeline_delta.match_anchors_v2"
    match_pairs_v2 = "vespucio_pipeline_delta.match_pairs_v2"
    artifact_groups = "vespucio_pipeline_delta.artifact_groups"
    group_merges = "vespucio_pipeline_delta.group_merges"
    groups_step_v2 = "vespucio_pipeline_delta.groups_step"
    pins_step_v2 = "vespucio_pipeline_delta.pins_step"
    typology_built_area_predictor = (
        "vespucio_pipeline_delta.typology_built_area_predictor"
    )
    condominium_pins_step_v2 = "vespucio_pipeline_delta.condominium_pins_step"
    condominium_step_v2 = "vespucio_pipeline_delta.condominium_step"
    resolved_identities_publish_checkpoint = (
        "vespucio_pipeline_delta.resolved_identities_publish_checkpoint"
    )
    artifacts_publish_checkpoint = (
        "vespucio_pipeline_delta.artifacts_publish_checkpoint"
    )
    images_upsert_backlog_queue = "vespucio_pipeline_delta.images_upsert_backlog_queue"
    images_upsert_backlog_progress = (
        "vespucio_pipeline_delta.images_upsert_backlog_progress"
    )
    images_upsert_backlog_failed = (
        "vespucio_pipeline_delta.images_upsert_backlog_failed"
    )

    zordominium_compounds = "zordominium_vespucio_plugin.zordominium_official_condos"

    classifieds_house_id = "vespucio_classifieds.classifieds_house_id"
    classified_v2_compounds = "vespucio_classifieds.classifieds_v2"
    classified_logging_table = "vespucio_classifieds.classifieds_publish_log"
    classified_published_listings = (
        "vespucio_classifieds.classifieds_published_listings"
    )
    classifieds_to_delete = "vespucio_classifieds.classifieds_to_delete"

    external_references = "vespucio_external_references.external_references"
    external_references_to_delete = (
        "vespucio_external_references.external_references_to_delete"
    )
    external_references_publish_log = "vespucio_external_references.publish_log"
    external_references_published = "vespucio_external_references.published"

    # golden_set_condo_compounds = (
    #     "vespucio_goldenset_delta.condo_compounds_employee_sample_v1"
    # )
    # golden_set_condo_compounds_diff = (
    #     "vespucio_goldenset_delta.condo_compounds_goldenset_diff"
    # )

    kodak_photo = "datalake_kodak_clean.photo"
    kodak_photo_invalid_source = "datalake_kodak_clean.photo_invalid_source"

    ebdb_clean_house_enrichment = "datalake_ebdb_clean.house_enrichment"
    ebdb_clean_house = "datalake_ebdb_clean.house"
    ebdb_clean_region = "datalake_ebdb_clean.region"
    ebdb_clean_state = "datalake_ebdb_clean.state"
    ebdb_country_table = "datalake_ebdb_clean.country"
    ebdb_clean_map_region = "datalake_ebdb_clean.map_region"
