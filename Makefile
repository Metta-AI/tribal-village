.PHONY: check build lib clean test test-nim test-python test-integration

# CI gate for nim check - syncs deps first
check:
	./scripts/nim_check.sh

# Build the shared library
build lib:
	nimble buildLib

# Clean build artifacts
clean:
	rm -f libtribal_village.so libtribal_village.dylib libtribal_village.dll
	rm -f nim.cfg

# Run all tests
test: test-nim test-python

# Run Nim unit and integration tests
test-nim:
	nim r --path:src tests/test_balance_scorecard.nim
	nim r --path:src tests/test_map_determinism.nim
	nim r --path:src tests/integration_behaviors.nim

# Run Python integration tests (requires lib to be built first)
test-python: lib
	pytest tests/test_python_integration.py -v

# Run full integration test suite
test-integration: lib
	nim r --path:src tests/integration_behaviors.nim
	pytest tests/test_python_integration.py -v -k "EndToEnd"
