# Memury

**A Canvas-native learning agent for document-grounded conversation, explainable planning, and verified learning memory.**

Memury keeps learning inside its original context. A student can open a Canvas document with Q Graph, ask follow-up questions, branch from an idea, and finish with the whole conversation summarized. Verified Canvas activity and learning evidence can then inform an explainable next-step plan.

> Memury is an independent open-source project built on Canvas LMS. It is not an official Instructure product.

## Live demo

The current release is deployed on the 4-core / 4 GB Memury server:

- Canvas login: <https://canvas.memury.net/login>
- Memury product: <https://canvas.memury.net/memury>
- Account: `memury.student@example.test`
- Password: `M3mury!cV8#qL2@pR7z`

These credentials are intentionally public and belong only to the isolated demo student. Do not reuse this password for a real Canvas, email, LMS, or administrator account. Demo data may be reset at any time.

## Competition submission

The direct-upload initial-round materials are in [`submission/2026-08-16`](submission/2026-08-16), with a complete ZIP at [`submission/Memury_初赛提交材料_2026-08-16.zip`](submission/Memury_初赛提交材料_2026-08-16.zip). The pack includes the under-500-character project brief, proposal PDF, Demo video, prototype instructions, and executable Canvas deployment kit.

## What is available now

- Canvas-native `/memury` workspace with the Canvas shell preserved.
- Q Graph as the primary learning surface rather than a standalone feature demo.
- Open a document with Q Graph and keep the response grounded in that source.
- Persistent multi-turn conversation with a whole-chat summary.
- Interface copy follows the signed-in user's Canvas language preference.
- Cross-course overview, explainable risk ordering, and constrained study blocks.
- Verified Canvas records separated from inferred and simulated learning data.
- Read-only treatment of official grades and submissions.
- Apple-inspired light design system shared by Memury and Q Graph.

## Product workflow

```text
Canvas course or document
→ open with Q Graph
→ source-grounded question
→ follow-up conversation and branches
→ whole-conversation summary
→ verified learning memory
→ explainable next action
→ constrained study plan
```

Memury supports three connected modes:

1. **Direct** — start from a document or question and get a grounded explanation.
2. **Review** — return to fading knowledge through the original source and conversation.
3. **Continuous** — let verified activity and reflections update the learning plan over time.

## Direct server upgrade

The repository includes a self-contained upgrade kit for an existing Docker Compose Canvas installation compatible with `canvas.memury.net`:

```text
deploy/memury-canvas-upgrade-20260816.tar.gz
deploy/memury-canvas-upgrade-20260816.tar.gz.sha256
deploy/memury-canvas-20260816/
```

The kit expects the existing Canvas Compose root at `/opt/canvas-lms`, a running container named `canvas-lms`, and at least 2.5 GB combined available memory and swap. Override the root with `CANVAS_ROOT` when necessary.

```bash
cd deploy
shasum -a 256 -c memury-canvas-upgrade-20260816.tar.gz.sha256
sudo mkdir -p /opt/memury-releases
sudo tar -xzf memury-canvas-upgrade-20260816.tar.gz -C /opt/memury-releases
cd /opt/memury-releases/memury-canvas-20260816
sha256sum -c SHA256SUMS
chmod +x scripts/*.sh
sudo ./scripts/deploy.sh
sudo ./scripts/set-demo-password.sh
```

When the password script prompts, enter the public demo password shown above. The deploy script performs a zero-fuzz patch check, creates rollback metadata and a PostgreSQL volume backup, builds the release image, runs additive migrations, seeds the demo student, switches the Canvas service, and executes health verification.

Rollback is available from the extracted kit:

```bash
sudo ./scripts/rollback.sh
```

See [the upgrade-kit guide](deploy/memury-canvas-20260816/README.md) and [release metadata](deploy/memury-canvas-20260816/RELEASE.md) for the exact assumptions and safety boundary.

## Repository map

```text
app/controllers/memury_controller.rb
app/services/memury/
ui/features/memury/
deploy/memury-canvas-20260816/
site/                         # Memury public site
slides/                       # synchronized HTML deck and PDF
docs/memury/
README_MEMURY.md
```

Further documentation:

- [Memury development guide](README_MEMURY.md)
- [Architecture](docs/memury/ARCHITECTURE.md)
- [Demo script](docs/memury/DEMO_SCRIPT.md)
- [Decision log](docs/memury/DECISION_LOG.md)
- [Preserved Canvas upstream README](README_CANVAS_UPSTREAM.md)

## Development

Canvas LMS has a substantial development environment. Use the Compose-based workflow documented in [README_MEMURY.md](README_MEMURY.md):

```bash
cp .env.memury.example .env.memury
docker compose up -d
docker compose run --rm web bundle exec rails db:migrate
docker compose run --rm -e LOGIN=memury.student@example.test web bundle exec rake memury:demo_seed
docker compose run --rm web yarn build:watch
```

The standalone public site can be developed independently:

```bash
cd site
npm install
npm run dev
npm run build
```

## Verification status

For the `2026-08-16-qgraph-apple-r3` release:

- 13 focused Memury frontend tests passed.
- Ruby syntax checks passed for the changed backend services and controller.
- The upgrade kit passed shell syntax, overlay consistency, and checksum verification.
- The deployed server passed authenticated login and health verification.
- A two-turn Q Graph conversation preserved context and produced a whole-chat summary.
- The synchronized 19-page presentation passed fixed-stage checks at desktop and phone viewports; the PDF is 16:9.

These checks establish a deployable product baseline, not evidence of learning efficacy. Long-term transfer, accessibility, security, privacy, and real-user outcomes still require dedicated evaluation.

## Safety and data boundaries

- Connectors are scoped to the currently authenticated student.
- Memury does not accept arbitrary student IDs from the browser client.
- Official grades, submissions, and instructor records remain read-only.
- Inferred and simulated information retains provenance metadata.
- Unverified Q Graph exploration cannot directly drive academic risk or mastery.
- Memury-generated plans are not presented as official instructor deadlines.

## Upstream and license

Memury is built on [Instructure Canvas LMS](https://github.com/instructure/canvas-lms). The upstream Canvas source, copyright notices, and GNU AGPL v3 terms remain applicable. See [LICENSE](LICENSE) and [README_CANVAS_UPSTREAM.md](README_CANVAS_UPSTREAM.md).

“Canvas” and “Instructure” belong to their respective owners. Memury is not affiliated with or endorsed by Instructure.
