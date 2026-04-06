# Popcorn XP Demo

Static mission-control style demo for active Popcorn XP subagent streams.

## Run locally

From the repository root:

```bash
cd docs/demo
python3 -m http.server 8000
```

Then open `http://127.0.0.1:8000/` in a browser.

## Notes

- The interface uses mocked sample data only.
- The wording matches the Popcorn XP session model: driver, navigator, advisor, `LOG.md`, `ADVICE.md`, and typed advice.
- The filter buttons let you focus the live view on one lane at a time.
