# Vector Chess
It's Polygon Pandemonium

A cross-platform hexagonal chess game built with **Godot 4** (GDScript) featuring procedural vector polygon graphics.

## Overview
- **Ruleset:** Gliński's Hexagonal Chess (91 flat-top hex cells, 3 tile shades, 3 Bishops and 9 Pawns per side)
- **Visuals:** 100% procedural 2D vector & polygon rendering (`CanvasItem._draw`) with live displacement vector telemetry
- **Platforms:** Windows, Linux, macOS, Web, Android, and iOS

## Running the Project
Open the repository folder in **Godot 4.7+** and press **F5**, or run from the command line:
```bash
godot --path .
```

## Building & Store Releases
Automated GitHub Actions pipelines build and package releases for **Steam (Windows, Linux, macOS)**, **Google Play (`.aab`)**, and **iOS App Store (`.ipa`)**. See [docs/RELEASING.md](docs/RELEASING.md) for runner setup and signing configuration.
