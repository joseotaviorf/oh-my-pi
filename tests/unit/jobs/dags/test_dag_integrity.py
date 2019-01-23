class TestDagIntegrity(object):
    LOAD_SECOND_THRESHOLD = 2

    def test_import_dags(self, dag_bag):
        """
        Checks the correctness and the acyclic property of each DAG. Test will fail even if there is a typo in any of
        the DAG
        """
        # assert
        import_errors = dag_bag.import_errors

        assert len(import_errors) == 0, "DAG import failures. Errors: {}".format(
            import_errors)

    def test_import_time(self, dag_bag):
        """
        Checks the load time of each DAG is less than LOAD_SECOND_THRESHOLD
        """
        # assert
        stats = dag_bag.dagbag_stats
        slow_dags = filter(lambda d: d.duration > self.LOAD_SECOND_THRESHOLD, stats)
        res = ', '.join(map(lambda d: d.file[1:], slow_dags))

        assert len(slow_dags) == 0, "The following DAGs take more than {}s to load: {}".format(
            self.LOAD_SECOND_THRESHOLD, res)
