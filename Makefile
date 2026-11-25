.PHONY: release runtime app dmg icon clean distclean publish
release: ; ./scripts/release.sh
runtime: ; ./scripts/build-runtime.sh
app: ; ./scripts/build-app.sh
dmg: ; ./scripts/make-dmg.sh
icon: ; ./scripts/make-icon.sh
clean: ; rm -rf build dist App/.build
distclean: clean ; rm -rf third_party
publish: ; ./scripts/publish-release.sh
