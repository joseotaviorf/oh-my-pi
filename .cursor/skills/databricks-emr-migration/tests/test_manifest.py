import unittest

from manifest import (
    RunManifest,
    ValidationJob,
    dedupe_manifest_jobs,
    manifest_from_dict,
    manifest_to_dict,
    reset_stale_jobs,
)


class TestManifest(unittest.TestCase):
    def test_job_key_and_counts(self) -> None:
        manifest = RunManifest(
            run_id="abc",
            load_start_date="2026-06-04",
            load_end_date="2026-06-05",
            jobs=[
                ValidationJob("fintech", "dag", "dw", "t1", status="compared", verdict="PASS"),
                ValidationJob("fintech", "dag", "dw", "t2", status="running"),
                ValidationJob("fintech", "dag", "dw", "t3", status="error"),
            ],
        )
        self.assertEqual(manifest.jobs[0].key, "fintech/dag/dw/t1")
        counts = manifest.counts()
        self.assertEqual(counts["compared"], 1)
        self.assertEqual(counts["error"], 1)
        self.assertFalse(manifest.is_complete())

    def test_dedupe_manifest_jobs(self) -> None:
        jobs = [
            ValidationJob("fintech", "dag", "enrich", "t1", status="pending"),
            ValidationJob("fintech", "dag", "enrich", "t1", status="compared", verdict="PASS"),
            ValidationJob("fintech", "dag", "enrich", "t2", status="running"),
        ]
        self.assertEqual(len(dedupe_manifest_jobs(jobs)), 2)

    def test_roundtrip_dict(self) -> None:
        manifest = RunManifest(
            run_id="xyz",
            load_start_date="2026-06-04",
            load_end_date="2026-06-05",
            jobs=[ValidationJob("fintech", "dag", "dw", "dim_x")],
        )
        restored = manifest_from_dict(manifest_to_dict(manifest))
        self.assertEqual(restored.run_id, "xyz")
        self.assertEqual(restored.jobs[0].table, "dim_x")

    def test_reset_stale_jobs(self) -> None:
        manifest = RunManifest(
            run_id="abc",
            load_start_date="2026-06-04",
            load_end_date="2026-06-05",
            jobs=[
                ValidationJob("fintech", "dag", "enrich", "t1", status="running", verdict=""),
                ValidationJob("fintech", "dag", "enrich", "t2", status="compared", verdict="PASS"),
                ValidationJob("fintech", "dag", "enrich", "t3", status="pending"),
            ],
        )
        reset_count = reset_stale_jobs(manifest)
        self.assertEqual(reset_count, 1)
        self.assertEqual(manifest.jobs[0].status, "pending")
        self.assertEqual(manifest.jobs[1].status, "compared")
        self.assertEqual(manifest.jobs[2].status, "pending")


if __name__ == "__main__":
    unittest.main()
