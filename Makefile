.PHONY: check build lib clean

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
