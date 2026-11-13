.PHONY: app run cli clean

app:
	./scripts/build-app.sh

run: app
	-pkill -x MacAudioPanel
	open build/MacAudioPanel.app

cli:
	swift build -c release --product audiotap
	@echo "Built .build/release/audiotap"

clean:
	rm -rf build .build
