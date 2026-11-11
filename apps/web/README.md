# Graption meeting dashboard

Run `npm ci`, then `npm run dev` and open the printed local address. Choose or drop JSON exports from the app. Files stay in browser memory until Clear or page close; they are never uploaded. For development run `npm run gen:types` after changing the export schema, `npm run lint`, `npm test`, and `npm run build`.

Search finds captions across all loaded meetings, ignoring case and accents. Select a result to open its transcript and focus the highlighted caption.

The Web dashboard workflow checks generated types, lint, typecheck, tests and the production build. Merges to main deploy to https://gt-big-data.github.io/graption/. A repository admin must select **Settings → Pages → Source → GitHub Actions** before the first deployment. Vite uses `/graption/` for production and local development.
