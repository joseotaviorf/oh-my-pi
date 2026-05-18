"""
Unit tests for CoreListingSparkJob.
"""


class TestCoreListingSparkJob:
    """Test class for CoreListingSparkJob."""

    # ==================== Core Model Tests ====================

    def test_create_core_model_has_all_expected_columns(self, core_model_df):
        """Test that create_core_model returns all expected columns."""
        expected_columns = [
            "id_house",
            "id_listing_business_context",
            "id_house_listing",
            "id_listing",
            "version",
            "price",
            "total_value",
            "condo_value",
            "iptu_value",
            "condo_type",
            "iptu_type",
            "status",
            "status_reason",
            "category",
            "ownership",
            "business_context",
            "is_extended_rental",
            "has_termination_canceled",
            "is_last_listing_version",
            "ts_first_publication",
            "ts_last_publication",
            "ts_created",
            "ts_updated",
            "ts_load",
            "sk_core_listing",
            "year",
            "month",
            "day",
        ]

        for col in expected_columns:
            assert col in core_model_df.columns, f"Column {col} missing from result"

    def test_create_core_model_unions_rent_and_sale(self, core_model_df):
        """Test that create_core_model unions RENT and SALE listings."""
        contexts = [row["business_context"] for row in core_model_df.collect()]

        assert "RENT" in contexts, "Result should contain RENT listings"
        assert "SALE" in contexts, "Result should contain SALE listings"

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

    # ==================== Config Tests ====================

    def test_get_listing_config_returns_correct_structure(self, core_listing_job):
        """Test get_listing_config method returns correct structure."""
        config = core_listing_job.get_listing_config()

        expected_keys = [
            "ENTITY_TYPE",
            "LISTING_BUSINESS_CONTEXT_TABLE",
            "HOUSE_TABLE",
            "AUX_LBC_STATUS_VERSION_ORDER_TABLE",
            "AUX_HOUSE_LISTING_CATEGORY_TABLE",
        ]

        for key in expected_keys:
            assert key in config, f"Config should contain {key}"

        assert config["ENTITY_TYPE"] == "LISTING"

    # ==================== SALE Listings Tests ====================

    def test_sale_listings_all_have_sale_context(self, sale_listings_df):
        """Test all SALE listings have business_context = SALE."""
        contexts = [row["business_context"] for row in sale_listings_df.collect()]
        assert all(ctx == "SALE" for ctx in contexts), "All records should be SALE"

    def test_sale_listings_all_have_version_zero(self, sale_listings_df):
        """Test all SALE listings have version = 0."""
        versions = [row["version"] for row in sale_listings_df.collect()]
        assert all(v == 0 for v in versions), "All SALE listings should have version 0"

    def test_sale_listings_all_have_category_na(self, sale_listings_df):
        """Test all SALE listings have category = 'NA'."""
        categories = [row["category"] for row in sale_listings_df.collect()]
        assert all(c == "NA" for c in categories), "All SALE should have category 'NA'"

    def test_sale_listings_boolean_defaults(self, sale_listings_df):
        """Test that SALE listings have correct boolean defaults."""
        for row in sale_listings_df.collect():
            assert row["is_extended_rental"] is False
            assert row["has_termination_canceled"] is False
            assert row["is_last_listing_version"] is True

    def test_sale_listings_id_house_listing_format(self, sale_listings_df):
        """Test that id_house_listing is correctly formatted: id_house || '000'."""
        for row in sale_listings_df.collect():
            expected_id = int(f"{row['id_house']}000")
            assert row["id_house_listing"] == expected_id, (
                f"id_house_listing should be {expected_id}, got {row['id_house_listing']}"
            )

    def test_sale_listings_filters_old_data(self, sale_listings_df):
        """Test that old SALE listings (ts_created <= 2022 AND ts_updated IS NULL) are filtered."""
        house_ids = [row["id_house"] for row in sale_listings_df.collect()]

        assert 2003 not in house_ids, "House 2003 should be filtered out"
        assert 2001 in house_ids, "House 2001 should be included"

    # ==================== RENT Listings Tests ====================

    def test_rent_listings_all_have_rent_context(self, rent_listings_df):
        """Test all RENT listings have business_context = RENT."""
        contexts = [row["business_context"] for row in rent_listings_df.collect()]
        assert all(ctx == "RENT" for ctx in contexts), "All records should be RENT"

    def test_rent_listings_deduplication(self, rent_listings_df):
        """Test id_house_listing is unique after deduplication."""
        id_house_listings = [
            row["id_house_listing"] for row in rent_listings_df.collect()
        ]
        assert len(id_house_listings) == len(set(id_house_listings)), (
            "id_house_listing should be unique after deduplication"
        )

    def test_rent_listings_is_last_listing_version(self, rent_listings_df):
        """Test is_last_listing_version calculation for RENT listings."""
        for row in rent_listings_df.collect():
            if row["id_house"] == 1001:
                if row["version"] == 3:
                    assert row["is_last_listing_version"] is True, (
                        "Version 3 should be last version for house 1001"
                    )
                    assert row["status"] == "PUBLISHED"
                elif row["version"] == 2:
                    assert row["is_last_listing_version"] is False, (
                        "Version 2 should not be last version for house 1001"
                    )
                    assert row["status"] == "UNPUBLISHED"

    def test_rent_listings_category_na_for_version_zero(self, rent_listings_df):
        """Test that category is 'NA' when version=0 and listing_category is NULL."""
        for row in rent_listings_df.collect():
            if row["id_house"] == 1001 and row["version"] == 0:
                assert row["category"] == "NA", (
                    "Category should be 'NA' for version 0 with NULL listing_category"
                )

    def test_rent_listings_recovered_category(self, rent_listings_df):
        """Test Recovered category for listings unpublished 84+ days then republished."""
        for row in rent_listings_df.collect():
            if row["id_house"] == 1001 and row["version"] == 3:
                assert row["category"] == "Recovered", (
                    "House 1001 version 3 should have category 'Recovered'"
                )
                assert row["status"] == "PUBLISHED"
                assert row["is_last_listing_version"] is True

    # ==================== Dual Context Tests ====================

    def test_same_house_can_have_rent_and_sale_contexts(self, core_model_df):
        """Test that same house can have both RENT and SALE contexts as separate listings."""
        result_data = core_model_df.collect()

        # House 1002 should appear twice: once for RENT and once for SALE
        house_1002_records = [row for row in result_data if row["id_house"] == 1002]

        assert len(house_1002_records) == 2, (
            f"House 1002 should have 2 records (RENT + SALE), got {len(house_1002_records)}"
        )

        # Verify both contexts exist
        contexts = [row["business_context"] for row in house_1002_records]
        assert "RENT" in contexts, "House 1002 should have RENT context"
        assert "SALE" in contexts, "House 1002 should have SALE context"

    def test_dual_context_rent_properties(self, core_model_df):
        """Test RENT listing properties for dual-context house."""
        result_data = core_model_df.collect()
        rent_record = [
            row
            for row in result_data
            if row["id_house"] == 1002 and row["business_context"] == "RENT"
        ][0]

        assert rent_record["version"] == 1
        assert rent_record["id_house_listing"] == 1002001
        assert rent_record["category"] == "First Listing"
        assert rent_record["status"] == "SUSPENDED"
        assert rent_record["status_reason"] == "RENTED"

    def test_dual_context_sale_properties(self, core_model_df):
        """Test SALE listing properties for dual-context house."""
        result_data = core_model_df.collect()
        sale_record = [
            row
            for row in result_data
            if row["id_house"] == 1002 and row["business_context"] == "SALE"
        ][0]

        assert sale_record["version"] == 0
        assert sale_record["id_house_listing"] == 1002000
        assert sale_record["category"] == "NA"
        assert sale_record["status"] == "SUSPENDED"

    def test_dual_context_different_id_listing(self, core_model_df):
        """Test that id_listing is different for RENT and SALE contexts."""
        result_data = core_model_df.collect()
        house_1002_records = [row for row in result_data if row["id_house"] == 1002]

        rent_id = [
            r["id_listing"]
            for r in house_1002_records
            if r["business_context"] == "RENT"
        ][0]
        sale_id = [
            r["id_listing"]
            for r in house_1002_records
            if r["business_context"] == "SALE"
        ][0]

        assert rent_id != sale_id, (
            "id_listing should be different for RENT and SALE contexts"
        )

    # ==================== Price Fields Tests ====================

    def test_rent_listings_have_price_from_house_rent(self, rent_listings_df):
        """Test that RENT listings get price from house.rent."""
        for row in rent_listings_df.collect():
            if row["id_house"] == 1001:
                assert row["price"] == 2500.0, (
                    "House 1001 should have rent price 2500.0"
                )
            elif row["id_house"] == 1002:
                assert row["price"] == 3000.0, (
                    "House 1002 should have rent price 3000.0"
                )

    def test_sale_listings_have_price_from_house_sale_price(self, sale_listings_df):
        """Test that SALE listings get price from house.sale_price."""
        for row in sale_listings_df.collect():
            if row["id_house"] == 2001:
                assert row["price"] == 800000.0, (
                    "House 2001 should have sale price 800000.0"
                )
            elif row["id_house"] == 1002:
                assert row["price"] == 500000.0, (
                    "House 1002 should have sale price 500000.0"
                )
