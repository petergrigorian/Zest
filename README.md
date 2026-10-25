# Zest

**A native macOS productivity interface for fast access to tools, actions, input sources, and system controls.**

Zest is an experimental native macOS utility built around a compact, configurable interface that stays out of the way until you need it. Summon it with a keyboard shortcut, access frequently used tools in one click, switch input sources quickly, or use the optional menu bar dashboard for at-a-glance controls.

> **Pre-release software** — Zest is currently in active development. Interfaces and behavior may change between builds.

## Highlights

- **Multiple interface form factors** — Orange Slice, Language Turntable / split views, and Triple Tile layouts.
- **Configurable feature placement** — arrange the tools you want directly on Zest.
- **Fast text tools** — font controls, clipboard history, emoji, symbols, and related text actions.
- **Applications & Shortcuts** — launch apps or Apple Shortcuts directly from Zest.
- **Input source switching** — switch keyboard/input languages from Zest or with rapid global shortcuts.
- **Menu bar dashboard** — optional quick-access dashboard with system monitors, pinned actions, Settings, restart, and quit controls.
- **Native macOS design** — SwiftUI/AppKit, Liquid Glass-style surfaces, dark/light appearance support, keyboard shortcuts, and system-level integration.
- **Guided onboarding** — Zest walks through permissions, interface selection, layout setup, and the selected form factor before first use.

## Installation

1. Open the **Releases** section of this repository.
2. Download the latest `Zest-*.pkg` installer.
3. Open the package and follow the macOS Installer steps.
4. Launch **Zest** from `/Applications`.
5. Complete the onboarding flow and grant the requested permissions.

Note! Your Mac computer needs to have at least macOS 27 installed to run this software!

## Permissions

Zest integrates with macOS and therefore needs permission for some system-level features.

- **Accessibility** is used for interface/text interaction and global productivity controls.
- **Automation** may be requested by macOS when a Zest feature needs to communicate with another application.

Zest explains the required permissions during onboarding. They can later be reviewed under **System Settings → Privacy & Security**.

## Input source shortcuts

By default, Zest supports rapid input-source navigation with:

- `Control + Option + →` — next input source
- `Control + Option + ←` — previous input source

The HUD provides visual feedback while switching.

## Development status

The project has reached its **first pre-release milestone**. Current work is focused on real-world testing, performance, UI refinement, and reliability across macOS configurations.

## Built with

- Swift
- SwiftUI
- AppKit
- Xcode

## Releases

Pre-release builds and installers are published in **GitHub Releases**.

---

Created by **Petro Grigoryan**.
