from bietlejuice.governance.anonymization.pii_scan_status import (
    SCAN_STATUS_COMPLETE,
    SCAN_STATUS_SAMPLE_TOO_BIG,
    resolve_scan_status,
)


class TestResolveScanStatus:
    def test_complete_below_json_limit(self):
        # arrange
        sample_bytes = 3999

        # act
        status = resolve_scan_status(sample_bytes)

        # assert
        assert status == SCAN_STATUS_COMPLETE

    def test_sample_too_big_at_limit(self):
        # arrange
        sample_bytes = 4000

        # act
        status = resolve_scan_status(sample_bytes)

        # assert
        assert status == SCAN_STATUS_SAMPLE_TOO_BIG
