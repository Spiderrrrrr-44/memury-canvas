# Memury public site

The public Memury product site explains the Canvas-native workflow: open a document with Q Graph, keep follow-up questions grounded in the source, summarize the whole conversation, and carry verified evidence into an explainable learning plan.

## Run locally

```bash
npm install
npm run dev
```

The development server starts on <http://localhost:3000> by default.

## Validate

```bash
npm test
npm run lint
```

`npm test` creates the production Vinext build and verifies the rendered product page, live Canvas link, GitHub link, and removal of starter placeholders.

The site itself does not store student data and does not contain the public Canvas demo password. Account details remain in the repository root README so they have one authoritative location.
