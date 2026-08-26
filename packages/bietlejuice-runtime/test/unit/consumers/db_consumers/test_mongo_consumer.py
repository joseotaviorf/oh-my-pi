from bietlejuice.consumers.db_consumers.mongo_consumer import _summarize_batch


class TestSummarizeBatch:
    def test_empty_batch(self):
        assert _summarize_batch([]) == "batch_len=0"

    def test_summarizes_dict_batch_without_payload(self):
        batch = [
            {"_id": "abc123", "status": "OPEN", "metadata": {"nested": "value"}},
            {"_id": "def456", "status": "CLOSED"},
        ]
        summary = _summarize_batch(batch)
        assert summary == "batch_len=2, field_count=3, sample_id='abc123'"
        assert "nested" not in summary
        assert "metadata" not in summary

    def test_non_dict_documents(self):
        assert _summarize_batch(["a", "b"]) == "batch_len=2"
