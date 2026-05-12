"""
Unit tests for core_aux_listing SQL query aux__lbc_status_version_order.
"""


class TestAuxLbcStatusVersionOrderQuery:
    """Test class for core_listing.aux__lbc_status_version_order SQL query."""

    def test_query_basic_functionality(
        self,
        aux__lbc_status_version_order_result_df,
        aux__lbc_status_version_order_result_data,
    ):
        """Test basic functionality of the aux__lbc_status_version_order query."""
        # Assertions
        assert aux__lbc_status_version_order_result_df is not None
        assert len(aux__lbc_status_version_order_result_data) > 0

        # Check that basic columns exist
        columns = aux__lbc_status_version_order_result_df.columns
        expected_columns = [
            "id_house",
            "lbc_state_order",
            "state_order",
            "trigger_new_version",
            "listing_version",
            "rev",
            "status",
            "status_reason",
            "revision_reason",
            "is_extended_rental",
            "has_termination_canceled",
            "is_last_state_of_day",
            "ts_first_publication",
            "ts_state_started",
            "ts_state_ended",
        ]

        for col in expected_columns:
            assert col in columns, f"Column {col} missing from result"

    def test_status_tracking(self, aux__lbc_status_version_order_result_data):
        """Test that status is tracked correctly."""
        result_data = aux__lbc_status_version_order_result_data

        # Test that status captures different statuses
        statuses = set(
            [row["status"] for row in result_data if row["status"] is not None]
        )
        assert (
            "EDITING" in statuses
            or "PUBLISHED" in statuses
            or "SUSPENDED" in statuses
            or "UNPUBLISHED" in statuses
            or "publicado" in statuses
            or "alugado" in statuses
        ), "Should track different status values"

    def test_ts_first_publication_consistency(
        self, aux__lbc_status_version_order_result_data
    ):
        """Test that ts_first_publication is consistent across all states of the same house."""
        result_data = aux__lbc_status_version_order_result_data

        house_1_data = [row for row in result_data if row["id_house"] == 1001]
        if len(house_1_data) > 0:
            first_publications = set(
                [
                    row["ts_first_publication"]
                    for row in house_1_data
                    if row["ts_first_publication"] is not None
                ]
            )
            # All rows for the same house should have the same first publication date
            assert (
                len(first_publications) <= 1
            ), f"House 1 should have consistent ts_first_publication, got {first_publications}"

    def test_state_order_sequence(self, aux__lbc_status_version_order_result_data):
        """Test that state_order creates a sequential ascending order."""
        result_data = aux__lbc_status_version_order_result_data

        house_1_data = sorted(
            [row for row in result_data if row["id_house"] == 1001],
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
        )
        assert len(house_1_data) > 0, "House 1 should have data"

        # Check that state_order is sequential
        state_orders = [row["state_order"] for row in house_1_data]
        if len(state_orders) > 1:
            # Verify that state_order follows ascending order
            for i in range(len(state_orders) - 1):
                assert (
                    state_orders[i] < state_orders[i + 1]
                ), f"state_order should be ascending: got {state_orders}"

    def test_lbc_state_order(self, aux__lbc_status_version_order_result_data):
        """Test that lbc_state_order is set correctly for LBC states."""
        result_data = aux__lbc_status_version_order_result_data

        # Find rows with lbc_state_order not NULL (these are LBC states)
        lbc_rows = [row for row in result_data if row["lbc_state_order"] is not None]

        assert len(lbc_rows) > 0, "Should have rows with lbc_state_order"

        # Verify that lbc_state_order is sequential for each house
        for house_id in set([row["id_house"] for row in lbc_rows]):
            house_lbc_rows = sorted(
                [row for row in lbc_rows if row["id_house"] == house_id],
                key=lambda x: x["lbc_state_order"],
            )
            if len(house_lbc_rows) > 1:
                lbc_orders = [row["lbc_state_order"] for row in house_lbc_rows]
                expected_sequence = list(range(1, len(lbc_orders) + 1))
                assert lbc_orders == expected_sequence, (
                    f"lbc_state_order should be sequential for house {house_id}: "
                    f"got {lbc_orders}, expected {expected_sequence}"
                )

    def test_ts_state_started_ended(self, aux__lbc_status_version_order_result_data):
        """Test that ts_state_started and ts_state_ended are set correctly."""
        result_data = aux__lbc_status_version_order_result_data

        # All rows should have ts_state_started
        for row in result_data:
            assert (
                row["ts_state_started"] is not None
            ), f"All rows should have ts_state_started, got None for house {row['id_house']}, rev {row['rev']}"

        # Verify that ts_state_ended is NULL for the last state of each house
        # or that ts_state_ended >= ts_state_started when not NULL
        for row in result_data:
            if row["ts_state_ended"] is not None:
                assert (
                    row["ts_state_ended"] >= row["ts_state_started"]
                ), f"ts_state_ended should be >= ts_state_started for house {row['id_house']}, rev {row['rev']}"

    def test_first_listing_trigger(self, aux__lbc_status_version_order_result_data):
        """Test that first listing (EDITING -> PUBLISHED) triggers a new version."""
        result_data = aux__lbc_status_version_order_result_data

        house_1_data = [row for row in result_data if row["id_house"] == 1001]
        assert len(house_1_data) > 0, "House 1 should have data"

        # Sort by state_order to get chronological order
        house_1_sorted = sorted(
            house_1_data,
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
        )

        # Find the first EDITING row
        editing_row = None
        for row in house_1_sorted:
            if row["status"] == "EDITING":
                editing_row = row
                break

        assert editing_row is not None, "House 1 should have an EDITING status"

        # Find the first PUBLISHED row that comes after EDITING
        published_row = None
        editing_index = house_1_sorted.index(editing_row)
        for i in range(editing_index + 1, len(house_1_sorted)):
            if house_1_sorted[i]["status"] == "PUBLISHED":
                published_row = house_1_sorted[i]
                break

        assert (
            published_row is not None
        ), "House 1 should have a PUBLISHED status after EDITING"

        # The EDITING row that comes right before PUBLISHED should have trigger_new_version = 1
        assert (
            editing_row["trigger_new_version"] == 1
        ), "EDITING status before PUBLISHED should trigger a new version"

        # The PUBLISHED row that comes right after EDITING should have listing_version = 1
        assert (
            published_row["listing_version"] == 1
        ), "First listing (EDITING -> PUBLISHED) should have version 1"

    def test_recovered_trigger(self, aux__lbc_status_version_order_result_data):
        """Test that recovered (UNPUBLISHED for 84+ days -> PUBLISHED) triggers a new version."""
        result_data = aux__lbc_status_version_order_result_data

        house_1_data = [row for row in result_data if row["id_house"] == 1001]
        assert len(house_1_data) > 0, "House 1 should have data"

        # Sort by state_order to find chronological order
        house_1_sorted = sorted(
            house_1_data,
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
        )

        # Find the unpublished row and the republished row (after UNPUBLISHED)
        unpublished_row = None
        republished_row = None
        for i, row in enumerate(house_1_sorted):
            if (
                row["status"] == "PUBLISHED"
                and i > 0
                and house_1_sorted[i - 1]["status"] == "UNPUBLISHED"
            ):
                unpublished_row = house_1_sorted[i - 1]
                republished_row = row
                break

        assert unpublished_row is not None, "House 1 should have an UNPUBLISHED status"
        assert (
            republished_row is not None
        ), "House 1 should have a PUBLISHED status after UNPUBLISHED"

        assert (
            unpublished_row["trigger_new_version"] == 1
        ), "Recovered (UNPUBLISHED for 84+ days -> PUBLISHED) should trigger a new version"
        assert (
            republished_row["listing_version"] == unpublished_row["listing_version"] + 1
        ), "Recovered should have incremented version"

    def test_relisting_trigger(self, aux__lbc_status_version_order_result_data):
        """Test that relisting (SUSPENDED with RENTED -> PUBLISHED) triggers a new version."""
        result_data = aux__lbc_status_version_order_result_data

        house_1_data = [row for row in result_data if row["id_house"] == 1003]
        assert len(house_1_data) > 0, "House 3 should have data"

        # Sort by state_order to find chronological order
        house_1_sorted = sorted(
            house_1_data,
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
        )

        # Find the suspended row (SUSPENDED with RENTED) and the relisting row (PUBLISHED after it)
        suspended_row = None
        relisting_row = None
        for i, row in enumerate(house_1_sorted):
            if (
                row["status"] == "PUBLISHED"
                and i > 0
                and house_1_sorted[i - 1]["status"] == "SUSPENDED"
                and house_1_sorted[i - 1]["status_reason"] == "RENTED"
            ):
                suspended_row = house_1_sorted[i - 1]
                relisting_row = row
                break

        assert (
            suspended_row is not None
        ), "House 1 should have a SUSPENDED status with RENTED reason"
        assert (
            relisting_row is not None
        ), "House 1 should have a PUBLISHED status after SUSPENDED with RENTED"

        # The relisting row should have trigger_new_version = 1
        assert (
            suspended_row["trigger_new_version"] == 1
        ), "Relisting (SUSPENDED with RENTED -> PUBLISHED) should trigger a new version"
        assert (
            relisting_row["listing_version"] == suspended_row["listing_version"] + 1
        ), "Relisting (SUSPENDED with RENTED -> PUBLISHED) should increment version"

    def test_multiple_versions(self, aux__lbc_status_version_order_result_data):
        """Test multiple versions for a house."""
        result_data = aux__lbc_status_version_order_result_data

        house_1_data = [row for row in result_data if row["id_house"] == 1001]
        versions = set(
            [
                row["listing_version"]
                for row in house_1_data
                if row["listing_version"] is not None and row["listing_version"] > 0
            ]
        )
        # House 2 should have 3 versions (initial publication + recovered + relisting)
        assert len(versions) == 3, "House 1 should have multiple versions"

    def test_termination_canceled_flags(
        self, aux__lbc_status_version_order_result_data
    ):
        """Test that is_extended_rental and has_termination_canceled are True for the last record of house 1001 with TERMINATION_CANCELED."""
        result_data = aux__lbc_status_version_order_result_data

        house_1_data = [row for row in result_data if row["id_house"] == 1001]
        assert len(house_1_data) > 0, "House 1 should have data"

        # Sort by state_order to find the last record (highest state_order)
        house_1_sorted = sorted(
            house_1_data,
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
            reverse=True,
        )

        # Get the last record (first in reverse sorted list)
        last_record = house_1_sorted[0]

        # Verify that the last record has TERMINATION_CANCELED in revision_reason
        assert (
            last_record["revision_reason"] is not None
            and "TERMINATION_CANCELED" in last_record["revision_reason"]
        ), (
            f"Last record of house 1001 should have TERMINATION_CANCELED in revision_reason. "
            f"Got revision_reason={last_record['revision_reason']} for rev {last_record['rev']}"
        )

        # Verify that is_extended_rental is True
        assert last_record["is_extended_rental"] is True, (
            f"is_extended_rental should be True for last record with TERMINATION_CANCELED. "
            f"Got {last_record['is_extended_rental']} for house {last_record['id_house']}, rev {last_record['rev']}"
        )

        # Verify that has_termination_canceled is True
        assert last_record["has_termination_canceled"] is True, (
            f"has_termination_canceled should be True for last record with TERMINATION_CANCELED. "
            f"Got {last_record['has_termination_canceled']} for house {last_record['id_house']}, rev {last_record['rev']}"
        )

    def test_no_trigger_for_non_rented_suspension(
        self, aux__lbc_status_version_order_result_data
    ):
        """Test that SUSPENDED with status_reason != RENTED does not trigger a new version."""
        result_data = aux__lbc_status_version_order_result_data

        house_2_data = [row for row in result_data if row["id_house"] == 1002]
        assert len(house_2_data) > 0, "House 2 should have data"

        # Sort by state_order to find chronological order
        house_2_sorted = sorted(
            house_2_data,
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
        )

        # Find SUSPENDED row with status_reason != RENTED and the PUBLISHED that comes after it
        suspended_row = None
        published_row = None
        for i, row in enumerate(house_2_sorted):
            if row["status"] == "SUSPENDED" and row["status_reason"] != "RENTED":
                suspended_row = row
                # Look for the first PUBLISHED after this SUSPENDED
                for j in range(i + 1, len(house_2_sorted)):
                    if house_2_sorted[j]["status"] == "PUBLISHED":
                        published_row = house_2_sorted[j]
                        break
                if published_row is not None:
                    break

        assert (
            suspended_row is not None
        ), "House 2 should have a SUSPENDED status with status_reason != RENTED"
        assert (
            published_row is not None
        ), "House 2 should have a PUBLISHED status after SUSPENDED with status_reason != RENTED"

        # This should NOT trigger a new version
        assert (
            suspended_row["trigger_new_version"] == 0
        ), "SUSPENDED with status_reason != RENTED should NOT trigger a new version"

        # The PUBLISHED row should NOT have an incremented listing_version
        suspended_listing_version = (
            suspended_row["listing_version"]
            if suspended_row["listing_version"] is not None
            else 0
        )
        published_listing_version = (
            published_row["listing_version"]
            if published_row["listing_version"] is not None
            else 0
        )

        assert published_listing_version == suspended_listing_version, (
            f"PUBLISHED after SUSPENDED with status_reason != RENTED should NOT increment listing_version. "
            f"SUSPENDED listing_version: {suspended_listing_version}, "
            f"PUBLISHED listing_version: {published_listing_version}, "
            f"Expected: {suspended_listing_version}"
        )

    def test_no_trigger_for_short_unpublished(
        self, aux__lbc_status_version_order_result_data
    ):
        """Test that UNPUBLISHED for less than 84 days does not trigger a new version."""
        result_data = aux__lbc_status_version_order_result_data

        house_2_data = [row for row in result_data if row["id_house"] == 1002]
        assert len(house_2_data) > 0, "House 2 should have data"

        # Sort by state_order to find chronological order
        house_2_sorted = sorted(
            house_2_data,
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
        )

        # Find UNPUBLISHED row and the PUBLISHED that comes after it
        unpublished_row = None
        published_row = None
        for i, row in enumerate(house_2_sorted):
            if row["status"] == "UNPUBLISHED":
                unpublished_row = row
                # Look for the first PUBLISHED after this UNPUBLISHED
                for j in range(i + 1, len(house_2_sorted)):
                    if house_2_sorted[j]["status"] == "PUBLISHED":
                        published_row = house_2_sorted[j]
                        break
                if published_row is not None:
                    break

        assert unpublished_row is not None, "House 2 should have an UNPUBLISHED status"
        assert (
            published_row is not None
        ), "House 2 should have a PUBLISHED status after UNPUBLISHED"

        # This should NOT trigger a new version
        assert (
            unpublished_row["trigger_new_version"] == 0
        ), "UNPUBLISHED for less than 84 days should NOT trigger a new version"

        # The PUBLISHED row should NOT have an incremented listing_version
        unpublished_listing_version = (
            unpublished_row["listing_version"]
            if unpublished_row["listing_version"] is not None
            else 0
        )
        published_listing_version = (
            published_row["listing_version"]
            if published_row["listing_version"] is not None
            else 0
        )

        assert published_listing_version == unpublished_listing_version, (
            f"PUBLISHED after UNPUBLISHED for less than 84 days should NOT increment listing_version. "
            f"UNPUBLISHED listing_version: {unpublished_listing_version}, "
            f"PUBLISHED listing_version: {published_listing_version}, "
            f"Expected: {unpublished_listing_version}"
        )

    def test_historical_lbc_compatibility(
        self, aux__lbc_status_version_order_result_data
    ):
        """Test compatibility between historical aux__house_status_version_order and listing_business_context_aud for house 1003."""
        result_data = aux__lbc_status_version_order_result_data

        house_3_data = [row for row in result_data if row["id_house"] == 1003]
        assert len(house_3_data) > 0, "House 3 should have data"

        # Sort by state_order to verify sequential order
        house_3_sorted = sorted(
            house_3_data,
            key=lambda x: x["state_order"] if x["state_order"] is not None else 0,
        )

        # Verify that state_order is sequential (should include both historical and LBC data)
        state_orders = [
            row["state_order"]
            for row in house_3_sorted
            if row["state_order"] is not None
        ]
        if len(state_orders) > 1:
            expected_sequence = list(range(1, len(state_orders) + 1))
            assert state_orders == expected_sequence, (
                f"state_order should be sequential for house 1003, "
                f"got {state_orders}, expected {expected_sequence}"
            )

        # Verify that listing_version is consistent across the transition
        listing_versions = set(
            [
                row["listing_version"]
                for row in house_3_sorted
                if row["listing_version"] is not None
            ]
        )
        assert (
            len(listing_versions) == 3
        ), "House 3 should have 3 different listing_version"

        # Verify that ts_first_publication is consistent across all records
        first_publications = set(
            [
                row["ts_first_publication"]
                for row in house_3_sorted
                if row["ts_first_publication"] is not None
            ]
        )
        assert len(first_publications) <= 1, (
            f"House 3 should have consistent ts_first_publication across historical and LBC data, "
            f"got {first_publications}"
        )
