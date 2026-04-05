# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Just Three — a Flutter todolist app. Currently at initial scaffold stage (SDK ^3.11.4).

## Commands

- **Run app:** `flutter run` (add `-d chrome` for web, `-d macos` for macOS, etc.)
- **Get dependencies:** `flutter pub get`
- **Analyze/lint:** `flutter analyze` (uses `package:flutter_lints/flutter.yaml`)
- **Run all tests:** `flutter test`
- **Run single test:** `flutter test test/<file>_test.dart`
- **Build:** `flutter build <platform>` (apk, ios, web, macos, linux, windows)

## Architecture

Single-file app (`lib/main.dart`) with no additional packages beyond Flutter core. Platform targets: Android, iOS, web, macOS, Linux, Windows.

Lint rules come from `package:flutter_lints` via `analysis_options.yaml`. No test directory exists yet.
