.PHONY: environment
## create environment
environment:
	pyenv install -s 3.5.2
	pyenv virtualenv 3.5.2 bi-etl-ejuice
	pyenv local bi-etl-ejuice

.PHONY: version
version:
	@grep __version__ setup.py | head -1 | cut -d \" -f2 | cut -d \' -f2 > .version

.PHONY: package-name
package-name:
	@grep __package_name__ setup.py | head -1 | cut -d \" -f2 | cut -d \' -f2 > .package_name

.PHONY: repository-url
repository-url:
	@grep __repository_url__ setup.py | head -1 | cut -d \" -f2 | cut -d \' -f2 > .repository_url

.PHONY: package
package:
	@PYTHONPATH=. python -m setup3 sdist bdist_wheel