"""Scan completeness labels for enrich_anonymization (DPLT-969)."""

SAMPLE_JSON_SIZE_LIMIT = 4000
SCAN_STATUS_COMPLETE = "COMPLETE"
SCAN_STATUS_SAMPLE_TOO_BIG = "SAMPLE_TOO_BIG"


def resolve_scan_status(len_sample: int) -> str:
    if len_sample >= SAMPLE_JSON_SIZE_LIMIT:
        return SCAN_STATUS_SAMPLE_TOO_BIG
    return SCAN_STATUS_COMPLETE
