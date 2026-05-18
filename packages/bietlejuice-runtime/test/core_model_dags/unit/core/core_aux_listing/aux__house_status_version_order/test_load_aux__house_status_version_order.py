"""
Unit tests for core_aux_listing SQL query.
"""


class TestAuxHouseStatusVersionOrderQuery:
    """Test class for core_listing.aux__house_status_version_order SQL query."""

    def test_query_basic_functionality(
        self,
        aux__house_status_version_order_result_df,
        aux__house_status_version_order_result_data,
    ):
        """Test basic functionality of the core_aux_listing query."""
        # Assertions
        assert aux__house_status_version_order_result_df is not None
        assert len(aux__house_status_version_order_result_data) > 0

        # Check that basic columns exist
        columns = aux__house_status_version_order_result_df.columns
        expected_columns = [
            "id_house",
            "order_status",
            "order_version",
            "rev",
            "status_history",
            "reason",
            "events_change_status",
            "publication_version_date",
            "ts_first_publication",
            "ts_status_changed",
            "ts_status_changed_next",
        ]

        for col in expected_columns:
            assert col in columns, f"Column {col} missing from result"

    def test_status_history_tracking(self, aux__house_status_version_order_result_data):
        """Test that status history is tracked correctly."""
        result_data = aux__house_status_version_order_result_data

        # Test that status_history captures different statuses
        statuses = set(
            [
                row["status_history"]
                for row in result_data
                if row["status_history"] is not None
            ]
        )
        assert (
            "publicado" in statuses
            or "despublicado" in statuses
            or "alugado" in statuses
        ), "Should track different status values"

    def test_ts_first_publication_consistency(
        self, aux__house_status_version_order_result_data
    ):
        """Test that ts_first_publication is consistent across all revisions of the same house."""
        result_data = aux__house_status_version_order_result_data

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
            assert len(first_publications) <= 1, (
                f"House 1 should have consistent ts_first_publication, got {first_publications}"
            )

    def test_events_change_status(self, aux__house_status_version_order_result_data):
        """Test that version change events ('alugado' or 'despublicado' for 84+ days) are identified correctly."""
        result_data = aux__house_status_version_order_result_data

        # Verify that when events_change_status is populated, it must be only "alugado" or "despublicado"
        for row in result_data:
            if row["events_change_status"] is not None:
                assert row["events_change_status"] in ["alugado", "despublicado"], (
                    f"events_change_status must be 'alugado' or 'despublicado' when populated, "
                    f"got '{row['events_change_status']}' for house {row['id_house']}, rev {row['rev']}"
                )

    def test_order_status_sequence(self, aux__house_status_version_order_result_data):
        """Test that order_status creates a sequential ascending order, same as ts_status_changed."""
        result_data = aux__house_status_version_order_result_data

        house_1_data = sorted(
            [row for row in result_data if row["id_house"] == 1001],
            key=lambda x: x["order_status"],
        )
        assert len(house_1_data) > 0, "House 1 should have data"

        # Check that order_status is sequential
        order_statuses = [row["order_status"] for row in house_1_data]
        expected_sequence = list(range(1, len(order_statuses) + 1))
        assert order_statuses == expected_sequence, (
            f"order_status should be sequential: got {order_statuses}, expected {expected_sequence}"
        )

        # Verify that order_status follows the same ascending order as ts_status_changed
        house_1_sorted_by_time = sorted(
            [row for row in result_data if row["id_house"] == 1001],
            key=lambda x: x["ts_status_changed"],
        )
        order_statuses_by_time = [row["order_status"] for row in house_1_sorted_by_time]

        assert order_statuses_by_time == expected_sequence, (
            f"order_status should follow ascending order of ts_status_changed: "
            f"got {order_statuses_by_time} when sorted by time"
        )

    def test_never_published_houses(self, aux__house_status_version_order_result_data):
        """Test that houses that were never published have order_version = 0."""
        result_data = aux__house_status_version_order_result_data

        house_3_data = [row for row in result_data if row["id_house"] == 1003]
        assert len(house_3_data) > 0, "House 3 should have data"

        # All rows for house 3 should have order_version = 0
        for row in house_3_data:
            assert row["order_version"] == 0, (
                f"House 3 (never published) should have order_version = 0, got {row['order_version']}"
            )

    def test_initial_version(self, aux__house_status_version_order_result_data):
        """Test that the change to initial version works correctly."""
        result_data = aux__house_status_version_order_result_data

        house_1_data = [row for row in result_data if row["id_house"] == 1001]
        assert len(house_1_data) > 0, "House 1 should have data"

        edition_row = [row for row in house_1_data if row["status_history"] == "edicao"]
        published_row = [
            row for row in house_1_data if row["status_history"] == "publicado"
        ]

        assert len(edition_row) > 0, "House 1 should have the started status 'edicao'"
        assert len(published_row) > 0, (
            "House 1 should have a change status to 'publicado'"
        )
        assert edition_row[0]["order_version"] == 0, (
            "House 1 initial version should be 0"
        )
        assert published_row[0]["order_version"] == 1, (
            "House 1 version should be updated to 1"
        )

    def test_multiple_versions(self, aux__house_status_version_order_result_data):
        """Test multiple versions for a house."""
        result_data = aux__house_status_version_order_result_data

        house_4_data = [row for row in result_data if row["id_house"] == 1004]
        versions = set(
            [row["order_version"] for row in house_4_data if row["order_version"] > 0]
        )
        assert len(versions) >= 2, "House 4 should have multiple versions"

    def test_unpublished_trigger(self, aux__house_status_version_order_result_data):
        """Test that days_unpublished is calculated correctly for unpublished status and triggers new version.

        When a house is unpublished for 84+ days and then republished, it should trigger a version change.
        """
        result_data = aux__house_status_version_order_result_data

        house_2_data = [row for row in result_data if row["id_house"] == 1002]
        assert len(house_2_data) > 0, "House 2 should have data"

        # Find the unpublished row
        unpublished_rows = [
            row for row in house_2_data if row["status_history"] == "despublicado"
        ]
        assert len(unpublished_rows) > 0, (
            "House 2 should have an unpublished status row"
        )

        # Sort by ts_status_changed to find the status after unpublishing
        house_2_sorted = sorted(house_2_data, key=lambda x: x["ts_status_changed"])

        # Find rows for initial publication, unpublishing and republishing
        initial_pub = None
        unpublished = None
        republished = None

        for row in house_2_sorted:
            if row["status_history"] == "publicado" and initial_pub is None:
                initial_pub = row
            elif row["status_history"] == "despublicado" and unpublished is None:
                unpublished = row
            elif (
                row["status_history"] == "publicado"
                and unpublished is not None
                and republished is None
            ):
                republished = row
                break

        # Verify we have all the necessary rows
        assert initial_pub is not None, "House 2 should have an initial publication"
        assert unpublished is not None, "House 2 should have an unpublished status row"
        assert republished is not None, (
            "House 2 should have a republished row after being unpublished"
        )

        # Get the version
        initial_version = initial_pub["order_version"]
        republished_version = republished["order_version"]

        # Since House 2 was unpublished for 84+ days, the republished version should be one more than the version before
        assert republished_version == initial_version + 1, (
            f"Republished version ({republished_version}) should equal initial version + 1 ({initial_version + 1}) "
            f"due to 84+ days unpublished triggering a version change"
        )

    def test_unpublished_not_trigger_version(
        self, aux__house_status_version_order_result_data
    ):
        """Test that unpublished status for less than 84 days does not trigger a version change."""
        result_data = aux__house_status_version_order_result_data

        house_5_data = [row for row in result_data if row["id_house"] == 1005]
        assert len(house_5_data) > 0, "House 5 should have data"

        # Find the unpublished and republished rows
        unpublished_rows = [
            row for row in house_5_data if row["status_history"] == "despublicado"
        ]
        assert len(unpublished_rows) > 0, (
            "House 5 should have an unpublished status row"
        )

        # Sort by ts_status_changed to find the chronological order
        house_5_sorted = sorted(house_5_data, key=lambda x: x["ts_status_changed"])

        # Find rows: initial publication, unpublishing, and republishing
        initial_pub = None
        unpublished = None
        republished = None

        for row in house_5_sorted:
            if row["status_history"] == "publicado" and initial_pub is None:
                initial_pub = row
            elif row["status_history"] == "despublicado" and unpublished is None:
                unpublished = row
            elif (
                row["status_history"] == "publicado"
                and unpublished is not None
                and republished is None
            ):
                republished = row
                break

        # Verify we have all the necessary rows
        assert initial_pub is not None, "House 5 should have an initial publication"
        assert unpublished is not None, "House 5 should have an unpublished status row"
        assert republished is not None, (
            "House 5 should have a republished row after being unpublished"
        )

        # Verify that republished version does NOT change (because it was unpublished for < 84 days)
        # The order_version should be the same as the initial publication
        initial_version = initial_pub["order_version"]
        republished_version = republished["order_version"]

        assert republished_version == initial_version, (
            f"Republished version ({republished_version}) should equal initial version ({initial_version}) "
            f"because unpublished for less than 84 days does NOT trigger a version change"
        )

    def test_suspended_not_trigger_version(
        self, aux__house_status_version_order_result_data
    ):
        """Test that suspended status does not trigger a version change."""
        result_data = aux__house_status_version_order_result_data

        house_4_data = [row for row in result_data if row["id_house"] == 1004]
        assert len(house_4_data) > 0, "House 4 should have data"

        # Find the suspended row
        suspended_rows = [
            row for row in house_4_data if row["status_history"] == "suspenso"
        ]
        assert len(suspended_rows) > 0, "House 4 should have a suspended status row"

        # Find the row before suspension
        house_4_sorted = sorted(house_4_data, key=lambda x: x["ts_status_changed"])

        suspended_row = None
        row_before_suspension = None

        for i, row in enumerate(house_4_sorted):
            if row["status_history"] == "suspenso" and suspended_row is None:
                suspended_row = row
                # Get the previous row (before suspension)
                if i > 0:
                    row_before_suspension = house_4_sorted[i - 1]
                break

        assert suspended_row is not None, "Should have found suspended row"
        assert row_before_suspension is not None, (
            "Should have found row before suspension"
        )

        # Verify that suspended status does not change order_version
        # The order_version should be the same as the row before suspension
        suspended_version = suspended_row["order_version"]
        version_before_suspension = row_before_suspension["order_version"]

        assert suspended_version == version_before_suspension, (
            f"Suspended status should not change order_version. "
            f"Version before suspension: {version_before_suspension}, "
            f"Version after suspension: {suspended_version}"
        )

    def test_rented_version(self, aux__house_status_version_order_result_data):
        """Test that version was triggered before the 'alugado' status"""
        result_data = aux__house_status_version_order_result_data

        # Test that all "alugado" status should have order_version > 0
        alugado_rows = [
            row for row in result_data if row["status_history"] == "alugado"
        ]
        assert len(alugado_rows) > 0, (
            "Should have rows with 'alugado' as version change event"
        )

        for row in alugado_rows:
            assert row["order_version"] > 0, (
                f"'alugado' events should have order_version > 0, got {row['order_version']}"
            )

    def test_publication_version_date(
        self, aux__house_status_version_order_result_data
    ):
        """Test that publication_version_date is set correctly for each version."""
        result_data = aux__house_status_version_order_result_data

        house_4_data = [row for row in result_data if row["id_house"] == 1004]

        # Get distinct order_version values
        order_versions = set([row["order_version"] for row in house_4_data])

        # Verify that publication_version_date is the same for all rows with the same order_version
        for order_version in order_versions:
            rows_with_same_version = [
                row for row in house_4_data if row["order_version"] == order_version
            ]
            if len(rows_with_same_version) > 1:
                publication_dates_for_version = set(
                    [row["publication_version_date"] for row in rows_with_same_version]
                )
                assert len(publication_dates_for_version) == 1, (
                    f"All rows with order_version={order_version} should have the same "
                    f"publication_version_date, got {publication_dates_for_version}"
                )
