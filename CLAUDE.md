# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Photo2driveは、SwiftUIベースのiOSアプリケーションです。iOS 26.1以上をターゲットにしています。

## Common Commands

### Build and Run
```bash
# Build the app
xcodebuild -scheme Photo2drive -configuration Debug build

# Build for release
xcodebuild -scheme Photo2drive -configuration Release build

# Clean build
xcodebuild -scheme Photo2drive clean
```

### Testing
```bash
# Run all tests
xcodebuild test -scheme Photo2drive -destination 'platform=iOS Simulator,name=iPhone 16'

# Run unit tests only
xcodebuild test -scheme Photo2drive -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Photo2driveTests

# Run UI tests only
xcodebuild test -scheme Photo2drive -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Photo2driveUITests

# Run a specific test
xcodebuild test -scheme Photo2drive -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:Photo2driveTests/Photo2driveTests/example
```

Note: このプロジェクトはSwift Testingフレームワーク(@Testing)を使用しています。XCTestではありません。

## Architecture

### Project Structure
- `Photo2drive/` - メインアプリケーションのソースコード
  - `Photo2driveApp.swift` - アプリケーションのエントリーポイント(@main)
  - `ContentView.swift` - ルートビュー
  - `Assets.xcassets/` - アセットカタログ(画像、色など)
- `Photo2driveTests/` - ユニットテスト(Swift Testing使用)
- `Photo2driveUITests/` - UIテスト

### Development Notes
- SwiftUIベースのアプリケーション
- Swift Testingフレームワークを使用(@Testingマクロ)
- iOS 26.1+をターゲット
- Team ID: 4J89GAYXW2で署名設定済み
