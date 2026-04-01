# Fringe Ingredient Decoder

Fringe Ingredient Decoder is a scan-first SwiftUI iPhone app for quickly understanding food and cosmetic ingredient lists.

## What It Does

- scans barcodes with Open Food Facts and Open Beauty Facts lookups
- parses pasted ingredient text on-device
- classifies ingredients locally with bundled public reference data
- silently resolves long-tail unknowns in the background and caches them for later
- stores recent products, manual entries, and favorites locally

## Product Direction

The app is built around a few constraints:

- immediate, low-friction scanning
- recognition before explanation
- compact result summaries
- tap-through detail only when needed
- no accounts, no backend, no required sync

## Data Sources

- Open Food Facts
- Open Beauty Facts
- FDA inactive ingredient data

Scoring and ingredient interpretation are heuristic and on-device. The app does not make medical or safety claims.

## Site

Project pages are published from [`docs/`](/Users/alperea/ios-apps/fringe-ingredient-decoder/docs):

- `https://armper.github.io/fringe-ingredient-decoder/`
- `https://armper.github.io/fringe-ingredient-decoder/privacy.html`
- `https://armper.github.io/fringe-ingredient-decoder/support.html`
