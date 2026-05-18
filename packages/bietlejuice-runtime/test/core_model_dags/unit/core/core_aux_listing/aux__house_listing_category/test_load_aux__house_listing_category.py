"""
Unit tests for core_aux_listing SQL query aux__house_listing_category.
"""


class TestAuxHouseListingCategoryQuery:
    """Test class for core_listing.aux__house_listing_category SQL query."""

    def test_query_basic_functionality(
        self,
        aux__house_listing_category_result_df,
        aux__house_listing_category_result_data,
    ):
        """Test basic functionality of the aux__house_listing_category query."""
        # Assertions
        assert aux__house_listing_category_result_df is not None
        assert len(aux__house_listing_category_result_data) > 0

        # Check that basic columns exist
        columns = aux__house_listing_category_result_df.columns
        expected_columns = [
            "id_house",
            "id_house_listing",
            "version",
            "status",
            "status_history",
            "status_reason",
            "revision_reason",
            "listing_category",
            "is_extended_rental",
            "has_termination_canceled",
            "ts_status_changed",
            "ts_listing_version_start",
            "ts_listing_version_end",
            "ts_last_unpublished",
        ]

        for col in expected_columns:
            assert col in columns, f"Column {col} missing from result"

    def test_id_house_listing_format(self, aux__house_listing_category_result_data):
        """Test that id_house_listing is correctly formatted (id_house + zero-padded version)."""
        result_data = aux__house_listing_category_result_data

        for row in result_data:
            id_house = row["id_house"]
            version = row["version"]
            id_house_listing = row["id_house_listing"]

            # Calculate expected id_house_listing
            expected = int(f"{id_house}{version:03d}")

            assert id_house_listing == expected, (
                f"id_house_listing should be {expected} for id_house={id_house}, version={version}, got {id_house_listing}"
            )

    def test_version_sequence(self, aux__house_listing_category_result_data):
        """Test that versions are sequential for each house."""
        result_data = aux__house_listing_category_result_data

        # Group by house
        houses = set([row["id_house"] for row in result_data])

        for house_id in houses:
            house_records = sorted(
                [row for row in result_data if row["id_house"] == house_id],
                key=lambda x: x["version"],
            )

            # Verify versions are sequential (no gaps) for each house
            # Different houses may start from different versions (e.g., 0 or 1)
            versions = [row["version"] for row in house_records]

            if len(versions) > 1:
                # Find the minimum and maximum versions for this house
                min_version = min(versions)
                max_version = max(versions)

                # Expected versions should be sequential from min_version to max_version
                # e.g., if min=0 and max=3, expected = [0, 1, 2, 3]
                # e.g., if min=1 and max=2, expected = [1, 2]
                expected_versions = list(range(min_version, max_version + 1))

                assert versions == expected_versions, (
                    f"Versions should be sequential (no gaps) for house {house_id}, "
                    f"got {versions}, expected {expected_versions}"
                )

    def test_timestamps_consistency(self, aux__house_listing_category_result_data):
        """Test that timestamps are consistent and logical."""
        result_data = aux__house_listing_category_result_data

        for row in result_data:
            # ts_listing_version_start should be set
            assert row["ts_listing_version_start"] is not None, (
                f"ts_listing_version_start should not be NULL for house {row['id_house']}, version {row['version']}"
            )

            # ts_status_changed should be set
            assert row["ts_status_changed"] is not None, (
                f"ts_status_changed should not be NULL for house {row['id_house']}, version {row['version']}"
            )

            # ts_listing_version_start should be <= ts_status_changed
            if row["ts_listing_version_start"] and row["ts_status_changed"]:
                assert row["ts_listing_version_start"] <= row["ts_status_changed"], (
                    f"ts_listing_version_start should be <= ts_status_changed for house {row['id_house']}, "
                    f"version {row['version']}"
                )

            # If ts_listing_version_end is set, it should be >= ts_listing_version_start
            if (
                row["ts_listing_version_end"] is not None
                and row["ts_listing_version_start"] is not None
            ):
                assert (
                    row["ts_listing_version_end"] >= row["ts_listing_version_start"]
                ), (
                    f"ts_listing_version_end should be >= ts_listing_version_start for house {row['id_house']}, "
                    f"version {row['version']}"
                )

    def test_version_0_category(self, aux__house_listing_category_result_data):
        """Test that version 0 has NULL category."""
        result_data = aux__house_listing_category_result_data

        # Find all version 0 records
        version_0_records = [row for row in result_data if row["version"] == 0]

        # Version 0 may or may not exist in test data
        for row in version_0_records:
            assert row["listing_category"] is None, (
                f"Version 0 should have NULL category, got {row['listing_category']}"
            )

    def test_first_listing_category(self, aux__house_listing_category_result_data):
        """Test that version 1 is categorized as 'First Listing'."""
        result_data = aux__house_listing_category_result_data

        # Find all version 1 records
        version_1_records = [row for row in result_data if row["version"] == 1]

        assert len(version_1_records) > 0, "Should have at least one version 1 record"

        for row in version_1_records:
            assert row["listing_category"] == "First Listing", (
                f"Version 1 should be categorized as 'First Listing', got {row['listing_category']} for house {row['id_house']}"
            )

    def test_recovered_category(
        self, aux__house_listing_category_result_data, aux__lbc_status_version_order_df
    ):
        """Test that version > 1 after UNPUBLISHED for 84+ days is categorized as 'Recovered'."""
        result_data = aux__house_listing_category_result_data

        # Get the UNPUBLISHED record from aux__lbc_status_version_order that triggered version 2
        # This is the UNPUBLISHED with listing_version=1, trigger_new_version=1, and 84+ days
        lbc_data = aux__lbc_status_version_order_df.collect()
        unpublished_record = None
        for row in lbc_data:
            if (
                row["id_house"] == 1001
                and row["status"] == "UNPUBLISHED"
                and row["listing_version"] == 1
                and row["trigger_new_version"] == 1
                and row["days_in_status"] is not None
                and row["days_in_status"] >= 84
            ):
                unpublished_record = row
                break

        assert unpublished_record is not None, (
            "Should find the UNPUBLISHED record that triggered version 2"
        )

        # Get the PUBLISHED record that occurred after UNPUBLISHED (version 2)
        published_record = None
        for row in lbc_data:
            if (
                row["id_house"] == 1001
                and row["status"] == "PUBLISHED"
                and row["listing_version"] == 2
                and row["ts_state_started"] == unpublished_record["ts_state_ended"]
            ):
                published_record = row
                break

        assert published_record is not None, (
            "Should find the PUBLISHED record that started version 2"
        )

        # Find house 1, version 1 record
        house_1_version_1 = [
            row
            for row in result_data
            if row["id_house"] == 1001 and row["version"] == 1
        ]

        assert len(house_1_version_1) == 1, (
            "House 1 should have exactly one version 1 record"
        )

        version_1_record = house_1_version_1[0]

        # Find house 1, version 2 record
        house_1_version_2 = [
            row
            for row in result_data
            if row["id_house"] == 1001 and row["version"] == 2
        ]

        assert len(house_1_version_2) == 1, (
            "House 1 should have exactly one version 2 record"
        )

        version_2_record = house_1_version_2[0]

        # Verify version 2 is categorized as Recovered
        assert version_2_record["listing_category"] == "Recovered", (
            f"Version 2 after UNPUBLISHED for 84+ days should be 'Recovered', got {version_2_record['listing_category']}"
        )

        # Verify ts_status_changed in version 1 equals the timestamp of UNPUBLISHED status (84+ days)
        expected_ts_status_changed_v1 = unpublished_record["ts_state_started"]
        actual_ts_status_changed_v1 = version_1_record["ts_status_changed"]

        assert actual_ts_status_changed_v1 == expected_ts_status_changed_v1, (
            f"ts_status_changed of version 1 should match the ts_state_started of the UNPUBLISHED "
            f"status (84+ days). Expected {expected_ts_status_changed_v1}, got {actual_ts_status_changed_v1}"
        )

        # Verify ts_last_unpublished in version 1 equals the timestamp of UNPUBLISHED status (84+ days)
        expected_ts_last_unpublished_v1 = unpublished_record["ts_state_started"]
        actual_ts_last_unpublished_v1 = version_1_record["ts_last_unpublished"]

        assert actual_ts_last_unpublished_v1 == expected_ts_last_unpublished_v1, (
            f"ts_last_unpublished of version 1 should match the ts_state_started of the UNPUBLISHED "
            f"status (84+ days). Expected {expected_ts_last_unpublished_v1}, got {actual_ts_last_unpublished_v1}"
        )

        # Verify ts_listing_version_start in version 2 equals the timestamp when PUBLISHED started
        # (the status that came after UNPUBLISHED for 84+ days)
        expected_ts_listing_version_start_v2 = published_record["ts_state_started"]
        actual_ts_listing_version_start_v2 = version_2_record[
            "ts_listing_version_start"
        ]

        assert (
            actual_ts_listing_version_start_v2 == expected_ts_listing_version_start_v2
        ), (
            f"ts_listing_version_start of version 2 should match the ts_state_started of the PUBLISHED "
            f"status that came after UNPUBLISHED (84+ days). "
            f"Expected {expected_ts_listing_version_start_v2}, got {actual_ts_listing_version_start_v2}"
        )

    def test_relisting_category(
        self, aux__house_listing_category_result_data, aux__lbc_status_version_order_df
    ):
        """Test that version > 1 after being rented is categorized as 'Re-Listing'."""
        result_data = aux__house_listing_category_result_data

        # Get the SUSPENDED with RENTED record from aux__lbc_status_version_order (version 2)
        lbc_data = aux__lbc_status_version_order_df.collect()
        suspended_rented_record = None
        for row in lbc_data:
            if (
                row["id_house"] == 1001
                and row["status"] == "SUSPENDED"
                and row["status_reason"] == "RENTED"
                and row["listing_version"] == 2
                and row["trigger_new_version"] == 1
            ):
                suspended_rented_record = row
                break

        assert suspended_rented_record is not None, (
            "Should find the SUSPENDED with RENTED record that triggered version 3"
        )

        # Get the PUBLISHED record that occurred after SUSPENDED + RENTED (version 3)
        published_record = None
        for row in lbc_data:
            if (
                row["id_house"] == 1001
                and row["status"] == "PUBLISHED"
                and row["listing_version"] == 3
                and row["ts_state_started"] == suspended_rented_record["ts_state_ended"]
            ):
                published_record = row
                break

        assert published_record is not None, (
            "Should find the PUBLISHED record that started version 3"
        )

        # Find house 1, version 2 record
        house_1_version_2 = [
            row
            for row in result_data
            if row["id_house"] == 1001 and row["version"] == 2
        ]

        assert len(house_1_version_2) == 1, (
            "House 1 should have exactly one version 2 record"
        )

        version_2_record = house_1_version_2[0]

        # Find house 1, version 3 (should be Re-Listing)
        house_1_version_3 = [
            row
            for row in result_data
            if row["id_house"] == 1001 and row["version"] == 3
        ]

        assert len(house_1_version_3) == 1, (
            "House 1 should have exactly one version 3 record"
        )

        relisting_record = house_1_version_3[0]
        assert relisting_record["listing_category"] == "Re-Listing", (
            f"Version 3 after being rented should be 'Re-Listing', got {relisting_record['listing_category']}"
        )

        # Verify ts_status_changed in version 2 equals the timestamp of SUSPENDED with RENTED
        expected_ts_status_changed_v2 = suspended_rented_record["ts_state_started"]
        actual_ts_status_changed_v2 = version_2_record["ts_status_changed"]

        assert actual_ts_status_changed_v2 == expected_ts_status_changed_v2, (
            f"ts_status_changed of version 2 should match the ts_state_started of the SUSPENDED "
            f"status with status_reason RENTED. Expected {expected_ts_status_changed_v2}, got {actual_ts_status_changed_v2}"
        )

        # Verify ts_listing_version_start in version 3 equals the timestamp when PUBLISHED started
        # (the status that came after SUSPENDED + RENTED)
        expected_ts_listing_version_start_v3 = published_record["ts_state_started"]
        actual_ts_listing_version_start_v3 = relisting_record[
            "ts_listing_version_start"
        ]

        assert (
            actual_ts_listing_version_start_v3 == expected_ts_listing_version_start_v3
        ), (
            f"ts_listing_version_start of version 3 should match the ts_state_started of the PUBLISHED "
            f"status that came after SUSPENDED + RENTED. "
            f"Expected {expected_ts_listing_version_start_v3}, got {actual_ts_listing_version_start_v3}"
        )

    def test_relisting_over_recovered(
        self, aux__house_listing_category_result_data, aux__lbc_status_version_order_df
    ):
        """Test that version 2 of house 1002 is categorized as 'Re-Listing' instead of Recovered."""
        result_data = aux__house_listing_category_result_data

        # Get the SUSPENDED with RENTED record from aux__lbc_status_version_order (version 1)
        # This is the record that indicates the house was rented in version 1
        lbc_data = aux__lbc_status_version_order_df.collect()
        suspended_rented_record = None
        for row in lbc_data:
            if (
                row["id_house"] == 1002
                and row["status"] == "SUSPENDED"
                and row["status_reason"] == "RENTED"
                and row["listing_version"] == 1
            ):
                suspended_rented_record = row
                break

        assert suspended_rented_record is not None, (
            "Should find the SUSPENDED with RENTED record in version 1 for house 1002"
        )

        # Get the PUBLISHED record that started version 2 (after UNPUBLISHED)
        published_record = None
        for row in lbc_data:
            if (
                row["id_house"] == 1002
                and row["status"] == "PUBLISHED"
                and row["listing_version"] == 2
            ):
                published_record = row
                break

        assert published_record is not None, (
            "Should find the PUBLISHED record that started version 2 for house 1002"
        )

        # Get the UNPUBLISHED record from aux__lbc_status_version_order (version 1, 84+ days)
        # This is the UNPUBLISHED that occurred before the PUBLISHED that started version 2
        unpublished_record = None
        for row in lbc_data:
            if (
                row["id_house"] == 1002
                and row["status"] == "UNPUBLISHED"
                and row["listing_version"] == 1
                and row["days_in_status"] is not None
                and row["days_in_status"] >= 84
                and row["ts_state_ended"] == published_record["ts_state_started"]
            ):
                unpublished_record = row
                break

        assert unpublished_record is not None, (
            "Should find the UNPUBLISHED record (84+ days) that preceded version 2 for house 1002"
        )

        # Find house 2, version 1 record
        house_2_version_1 = [
            row
            for row in result_data
            if row["id_house"] == 1002 and row["version"] == 1
        ]

        assert len(house_2_version_1) == 1, (
            "House 2 should have exactly one version 1 record"
        )

        version_1_record = house_2_version_1[0]

        # Find house 2, version 2 record
        house_2_version_2 = [
            row
            for row in result_data
            if row["id_house"] == 1002 and row["version"] == 2
        ]

        assert len(house_2_version_2) == 1, (
            "House 2 should have exactly one version 2 record"
        )

        relisting_record = house_2_version_2[0]

        # Verify it's categorized as Re-Listing (not Recovered, because it was rented)
        assert relisting_record["listing_category"] == "Re-Listing", (
            f"Version 2 of house 1002 after being rented should be 'Re-Listing', got {relisting_record['listing_category']}"
        )

        # Verify ts_status_changed in version 1 equals the timestamp of UNPUBLISHED status (84+ days)
        expected_ts_status_changed_v1 = unpublished_record["ts_state_started"]
        actual_ts_status_changed_v1 = version_1_record["ts_status_changed"]

        assert actual_ts_status_changed_v1 == expected_ts_status_changed_v1, (
            f"ts_status_changed of version 1 should match the ts_state_started of the UNPUBLISHED "
            f"status (84+ days). Expected {expected_ts_status_changed_v1}, got {actual_ts_status_changed_v1}"
        )

        # Verify ts_last_unpublished in version 1 equals the timestamp of UNPUBLISHED status (84+ days)
        expected_ts_last_unpublished_v1 = unpublished_record["ts_state_started"]
        actual_ts_last_unpublished_v1 = version_1_record["ts_last_unpublished"]

        assert actual_ts_last_unpublished_v1 == expected_ts_last_unpublished_v1, (
            f"ts_last_unpublished of version 1 should match the ts_state_started of the UNPUBLISHED "
            f"status (84+ days). Expected {expected_ts_last_unpublished_v1}, got {actual_ts_last_unpublished_v1}"
        )

        # Verify ts_listing_version_start in version 2 equals the timestamp when PUBLISHED started
        # (the status that came after UNPUBLISHED by 84+ days)
        expected_ts_listing_version_start_v2 = published_record["ts_state_started"]
        actual_ts_listing_version_start_v2 = relisting_record[
            "ts_listing_version_start"
        ]

        assert (
            actual_ts_listing_version_start_v2 == expected_ts_listing_version_start_v2
        ), (
            f"ts_listing_version_start of version 2 should match the ts_state_started of the PUBLISHED "
            f"status that came after UNPUBLISHED (84+ days). "
            f"Expected {expected_ts_listing_version_start_v2}, got {actual_ts_listing_version_start_v2}"
        )
