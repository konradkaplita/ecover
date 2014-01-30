ECOVER = $(CURDIR)/deps/ecover

cover-instrument-release:
	@$(ECOVER)/utils/cover-instrument-release enable

cover-deinstrument-release:
	@$(ECOVER)/utils/cover-instrument-release disable

cover-compile:
	@echo "Cover compiling release modules"
	@escript $(ECOVER)/utils/nodetool -sname $(ECOVER_SNAME) -setcookie $(ECOVER_COOKIE) rpc ecover compile

cover-analyse:
	@echo "Cover analysing release modules"
	@escript $(ECOVER)/utils/nodetool -sname $(ECOVER_SNAME) -setcookie $(ECOVER_COOKIE) rpc ecover analyse
	@echo "For acceptance coverage report look at _rel/log/cover/index.html"
	@echo "To produce unit+acceptance merged code coverage run 'make cover-merge'"

cover-merge:
	@echo "Merging unit and acceptance tests coverage data"
	@escript $(ECOVER)/utils/nodetool -sname $(ECOVER_SNAME) -setcookie $(ECOVER_COOKIE) rpc ecover merge
	@echo "For total coverage report look at: _rel/log/cover/total/index.html"

cover-check:
	@$(ECOVER)/utils/check-coverage $(ECOVER_THRESHOLDS)

cover-cobertura:
	@$(ECOVER)/utils/cobertura
