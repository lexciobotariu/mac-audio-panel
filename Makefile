.PHONY: app run cli dmg clean

app:
	./scripts/build-app.sh

run: app
	-pkill -x MacAudioPanel
	open build/MacAudioPanel.app

dmg: app
	./scripts/make-dmg.sh

cli:
	swift build -c release --product audiotap
	@echo "Built .build/release/audiotap"

clean:
	rm -rf build .build
