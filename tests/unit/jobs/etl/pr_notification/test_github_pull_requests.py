from conftest import pytest, mock, GithubService, GithubPullRequests


class TestGithubPullRequests(object):

    @mock.patch.object(GithubService, '_get_json_response',
                       return_value={'data': {'repositoryOwner': {'repository': mock.ANY}}})
    def test_get_json_response(self, mock__get_json_response, github_pull_requests):
        # arrange
        repo_name = 'repo_name'

        # act
        result = github_pull_requests.get_json_response(repo_name)

        # assert
        assert repo_name in mock__get_json_response.call_args[0][0]['query']
        assert result is not None

    @mock.patch.object(GithubService, '_get_json_response',
                       return_value={'data': {'repositoryOwner': {'repository': None}}})
    def test_get_json_response_with_repository_none(self, mock_requests_post, github_pull_requests):
        # arrange
        repo_name = 'repo_name'

        # act & assert
        with pytest.raises(RuntimeError):
            github_pull_requests.get_json_response(repo_name)

    def test_extract_pull_requests_with_empty_edges(self):
        # arrange
        json_response = {
            'data': {
                'repositoryOwner': {
                    'repository': {
                        'pullRequests': {
                            'edges': []
                        }
                    }
                }
            }
        }

        # act
        open_prs, approved_prs = GithubPullRequests.extract_pull_requests(json_response=json_response)

        # assert
        assert len(open_prs) == len(approved_prs) == 0

    @pytest.mark.parametrize('review_edges, approved_prs_length',
                             [[[], 0],
                              [[{'node': {'state': 'COMMENT'}}], 0],
                              [[{'node': {'state': 'CHANGES_REQUESTED'}}], 1]])
    def test_extract_pull_requests_with_no_approved_prs(self, review_edges, approved_prs_length):
        # arrange
        json_response = {
            'data': {
                'repositoryOwner': {
                    'repository': {
                        'pullRequests': {
                            'edges': [{
                                'node': {
                                    'title': 'title',
                                    'author': {
                                        'login': 'login'
                                    },
                                    'url': 'url',
                                    'reviews': {
                                        'edges': review_edges
                                    }
                                }
                            }]
                        }
                    }
                }
            }
        }

        # act
        open_prs, approved_prs = GithubPullRequests.extract_pull_requests(json_response=json_response)

        # assert
        assert len(open_prs) > 0
        assert len(approved_prs) == approved_prs_length

    def test_extract_pull_requests_with_approved_prs(self):
        # arrange
        json_response = {
            'data': {
                'repositoryOwner': {
                    'repository': {
                        'pullRequests': {
                            'edges': [{
                                'node': {
                                    'title': mock.ANY,
                                    'author': {
                                        'login': mock.ANY
                                    },
                                    'url': mock.ANY,
                                    'reviews': {
                                        'edges': [{
                                            'node': {
                                                'state': 'APPROVED'
                                            }
                                        }]
                                    }
                                }
                            }]
                        }
                    }
                }
            }
        }

        # act
        open_prs, approved_prs = GithubPullRequests.extract_pull_requests(json_response=json_response)

        # assert
        assert len(open_prs) == 0
        assert len(approved_prs) > 0
