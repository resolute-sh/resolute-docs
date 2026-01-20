# Resolute Documentation

Documentation site for [Resolute](https://github.com/resolute-sh/resolute) — Agent Orchestration as Code for Go.

## Local Development

**Prerequisites**: Node.js >= 20.11.0, Hugo extended

```bash
npm install
npm run dev
```

Site runs at `http://localhost:1313`

## Build

```bash
npm run build
```

Static output in `public/`

## Deployment

**Vercel** (recommended):
- Framework: Hugo
- Build command: `npm run build`
- Output directory: `public`

**Netlify**: Pre-configured via `netlify.toml`

## Structure

```
content/docs/       # Documentation pages
assets/             # SCSS, JS assets
static/             # Static files (images, fonts)
config/             # Hugo configuration
layouts/            # Custom templates
```

## License

MIT
