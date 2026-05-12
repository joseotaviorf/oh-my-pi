"""
Unit tests for CoreHouseSparkJob.
"""


class TestCoreHouseSparkJob:
    """Test class for CoreHouseSparkJob."""

    # ==================== Core Model Tests ====================

    def test_create_core_model_has_all_expected_columns(self, core_model_df):
        """Test that create_core_model returns all expected columns."""
        expected_columns = [
            "id_house",
            "id_external",
            "id_region",
            "id_user_registrant",
            "id_owner",
            "uuid_owner",
            "address",
            "number",
            "neighborhood",
            "complement",
            "zipcode",
            "city",
            "type",
            "total_area",
            "lat",
            "lng",
            "total_bathrooms",
            "total_bedrooms",
            "total_suites",
            "floor",
            "ts_created",
            "ts_updated",
            "ts_load",
            "sk_core_house",
            "year",
            "month",
            "day",
        ]

        for col in expected_columns:
            assert col in core_model_df.columns, f"Column {col} missing from result"

    def test_create_core_model_adds_partitioning_columns(self, core_model_df):
        """Test that create_core_model adds year, month, day partitioning columns."""
        assert "year" in core_model_df.columns, "year column should exist"
        assert "month" in core_model_df.columns, "month column should exist"
        assert "day" in core_model_df.columns, "day column should exist"

        # Check values are derived from ts_updated
        for row in core_model_df.select("ts_updated", "year", "month", "day").collect():
            if row["ts_updated"] is not None:
                assert row["year"] == row["ts_updated"].year
                assert row["month"] == row["ts_updated"].month
                assert row["day"] == row["ts_updated"].day

    def test_create_core_model_adds_ts_load(self, core_model_df):
        """Test that create_core_model adds ts_load column."""
        assert "ts_load" in core_model_df.columns, "ts_load column should exist"

        for row in core_model_df.select("ts_load").collect():
            assert row["ts_load"] is not None, "ts_load should not be null"

    def test_create_core_model_adds_surrogate_key(self, core_model_df):
        """Test that create_core_model adds sk_core_house column."""
        assert (
            "sk_core_house" in core_model_df.columns
        ), "sk_core_house column should exist"

        for row in core_model_df.select("sk_core_house").collect():
            assert row["sk_core_house"] is not None, "sk_core_house should not be null"

    # ==================== Config Tests ====================

    def test_get_house_config_returns_correct_structure(self, core_house_job):
        """Test get_house_config method returns correct structure."""
        config = core_house_job.get_house_config()

        expected_keys = [
            "ENTITY_TYPE",
            "HOUSE_TABLE",
            "HOUSE_LISTING_RELATION_TABLE",
            "USER_TABLE",
        ]

        for key in expected_keys:
            assert key in config, f"Config should contain {key}"

        assert config["ENTITY_TYPE"] == "HOUSE"

    # ==================== Filtered Houses Test ====================

    def test_filtered_houses_excludes_legacy_records(self, filtered_houses_df):
        """Test that legacy houses (created <= 2015 with no updates) are filtered out."""
        house_ids = [row["id"] for row in filtered_houses_df.collect()]

        # House 1004 should be filtered out (dt_creation <= 2015 AND ts_updated IS NULL)
        assert (
            1004 not in house_ids
        ), "House 1004 should be filtered out (legacy record)"

        # House 1005 should be included (has ts_updated even though old)
        assert 1005 in house_ids, "House 1005 should be included (has ts_updated)"

        # Normal houses should be included
        assert 1001 in house_ids, "House 1001 should be included"
        assert 1002 in house_ids, "House 1002 should be included"
        assert 1003 in house_ids, "House 1003 should be included"

    # ==================== Latest House Listing Relation Tests ====================

    def test_latest_hlr_filters_property_owner_main_user(self, latest_hlr_df):
        """Test that only PROPERTY_OWNER with MAIN_USER source type is selected."""
        house_ids = [row["id_house"] for row in latest_hlr_df.collect()]

        # House 1001 and 1002 should have relations
        assert 1001 in house_ids, "House 1001 should have a relation"
        assert 1002 in house_ids, "House 1002 should have a relation"

        # House 1003 has no PROPERTY_OWNER with MAIN_USER
        assert 1003 not in house_ids, "House 1003 should not have a relation"

    def test_latest_hlr_picks_latest_by_ts_updated(self, latest_hlr_df):
        """Test that the latest relation by ts_updated is selected."""
        house_1001_row = [
            row for row in latest_hlr_df.collect() if row["id_house"] == 1001
        ][0]

        # Should select id_related = 202 (latest ts_updated)
        assert (
            house_1001_row["id_related"] == 202
        ), "Should select the latest relation (id_related=202)"

    def test_latest_hlr_is_unique_per_house(self, latest_hlr_df):
        """Test that there's only one relation per house after deduplication."""
        house_ids = [row["id_house"] for row in latest_hlr_df.collect()]

        assert len(house_ids) == len(
            set(house_ids)
        ), "Each house should have at most one relation"

    # ==================== Owner Resolution Tests ====================

    def test_owner_from_house_listing_relation(self, core_model_df):
        """Test that owner is resolved from house_listing_relation when available."""
        house_1001_row = [
            row for row in core_model_df.collect() if row["id_house"] == 1001
        ][0]

        # House 1001 should use id_related from house_listing_relation (202)
        assert (
            house_1001_row["id_owner"] == 202
        ), "id_owner should be from house_listing_relation (202)"
        assert (
            house_1001_row["uuid_owner"] == "uuid-person-202"
        ), "uuid_owner should be from the owner user (uuid-person-202)"

        house_1002_row = [
            row for row in core_model_df.collect() if row["id_house"] == 1002
        ][0]

        # House 1002 should use id_related from house_listing_relation (203)
        assert (
            house_1002_row["id_owner"] == 203
        ), "id_owner should be from house_listing_relation (203)"
        assert (
            house_1002_row["uuid_owner"] == "uuid-person-203"
        ), "uuid_owner should be from the owner user (uuid-person-203)"

    def test_owner_fallback_to_id_user(self, core_model_df):
        """Test that owner falls back to house.id_user when no relation exists or
        when there is no matching ID for the relation in User table."""
        house_1003_row = [
            row for row in core_model_df.collect() if row["id_house"] == 1003
        ][0]
        house_1005_row = [
            row for row in core_model_df.collect() if row["id_house"] == 1005
        ][0]

        # House 1003 has no PROPERTY_OWNER with MAIN_USER, should use id_user (103)
        assert (
            house_1003_row["id_owner"] == 103
        ), "id_owner should fallback to house.id_user (103)"
        assert (
            house_1003_row["uuid_owner"] == "uuid-person-103"
        ), "uuid_owner should be from the fallback user (uuid-person-103)"
        assert (
            house_1005_row["id_owner"] == 105
        ), "id_owner should fallback to house.id_user (105)"
        assert (
            house_1005_row["uuid_owner"] == "uuid-person-105"
        ), "uuid_owner should be from the fallback user (uuid-person-105)"

    # ==================== Timestamp Test ====================

    def test_ts_created_is_mapped_from_dt_creation(self, core_model_df):
        """Test that ts_created is mapped from dt_creation."""
        from datetime import datetime

        house_1001_row = [
            row for row in core_model_df.collect() if row["id_house"] == 1001
        ][0]

        expected_ts_created = datetime(2020, 3, 15, 10, 0)
        assert (
            house_1001_row["ts_created"] == expected_ts_created
        ), "ts_created should be mapped from dt_creation"

    # ==================== Record Count Tests ====================

    def test_core_model_excludes_filtered_houses(self, core_model_df):
        """Test that the core model excludes legacy filtered houses."""
        house_ids = [row["id_house"] for row in core_model_df.collect()]

        # Should have 5 houses (1001, 1002, 1003, 1005, 1006) - excluding 1004 (legacy)
        assert len(house_ids) == 5, f"Expected 5 houses, got {len(house_ids)}"
        assert 1004 not in house_ids, "House 1004 should be excluded"

    # ==================== Incremental Load Test ====================

    def test_incremental_load_filters_by_date_range(
        self, core_model_incremental_july_df
    ):
        """Test that incremental load filters houses by ts_database_transaction (July 2024).

        Expected houses based on ts_database_transaction:
        - House 1001: 2024-07-10 -> House updated in July
        - House 1002: 2024-08-15 -> Not included (August)
        - House 1003: 2024-05-20 -> Not included (May)
        - House 1004: 2015-06-01 -> Not included (filtered by legacy rule)
        - House 1005: 2024-01-15 -> Not included (January)
        - House 1006: 2024-05-15 -> Included because HLR was updated in July
        """
        house_ids = [
            row["id_house"] for row in core_model_incremental_july_df.collect()
        ]
        house_ids.sort()

        assert house_ids == [1001, 1006], (
            f"Houses 1001 (house updated) and 1006 (HLR updated) "
            f"should be included for July 2024, got {house_ids}"
        )
