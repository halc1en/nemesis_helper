default: gen lint

gen:
    flutter pub get
    # dart run build_runner build
    flutter gen-l10n

lint:
    dart format .

clean:
    flutter clean