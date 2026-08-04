# Memury Development Guide

Memury is an independent Canvas-first adaptive learning agent prototype. It adds student-scoped academic synchronization, deterministic planning, active diagnosis, evidence-based learner-state updates, and persistent study blocks to Canvas LMS. It is not an official Instructure product and never writes official Canvas grades.

This work remains subject to the repository's AGPLv3 license and existing Canvas copyright notices. Canvas and Instructure belong to their respective owners.

## Prerequisites

Use a compatible Canvas development environment. The repository's supported workflow runs Ruby, Rails, Bundler, Yarn, and tests inside the Docker Compose `web` service.

Review the preserved [upstream Canvas README](README_CANVAS_UPSTREAM.md) and the [Canvas Quick Start](https://github.com/instructure/canvas-lms/wiki/Quick-Start) before initializing a new environment.

## Configuration

Create a local environment file from the safe example:

```bash
cp .env.memury.example .env.memury
```

`MEMURY_DEMO_MODE=true` is the safe default. It uses deterministic rules, simulated SIS events, and predefined diagnostic questions without requiring an external AI key. `.env.memury` is intentionally ignored by Git; never commit credentials or real student data.

## Database and frontend setup

```bash
docker compose up -d
docker compose run --rm web bundle exec rails db:migrate
docker compose run --rm web yarn build:watch
```

The migration creates `memury_learner_profiles`, a user-scoped JSONB aggregate for learner state, evidence, decision logs, and study plans.

## Feature Flag and Demo seed

The RootAccount Feature Flag key is `memury`. The included task enables it for `Account.default` and initializes deterministic Memury state for an existing Canvas login:

```bash
docker compose run --rm -e LOGIN=memury.student@example.test web bundle exec rake memury:demo_seed
```

Before running the task, create `memury.student@example.test` through the normal Canvas development setup and enroll that user as a student in the courses you want to synchronize. To use another existing login, set `LOGIN` accordingly.

The task is idempotent for the selected user: rerunning it resets that user's Memury profile instead of creating duplicate Memury records. It does not create a Canvas account, courses, assignments, or enrollments.

## Real and simulated data

After the student selects **立即同步并重新规划** in the interface, `CanvasNativeConnector` reads:

- the signed-in user's active student enrollments;
- published assignments with deadlines in those courses;
- that user's own submission status and score summary.

These Canvas records remain read-only. The connector starts from the authenticated user and does not accept an arbitrary student ID from the client.

Demo mode supplies clearly labeled simulated content for:

- SIS class meetings and locations;
- a demo exam event;
- the five-task fallback timeline;
- predefined diagnostic and transfer questions;
- selected initial learning evidence.

Memury-generated study blocks are inferred data. Rescheduled blocks are labeled as user overrides. Neither is presented as an official Canvas deadline.

## Demo walkthrough

1. Sign in as the configured student.
2. Open **Memury** from Canvas global navigation.
3. Select **立即同步并重新规划**.
4. Review the next action, task-risk timeline, simulated SIS events, and study blocks.
5. Start the diagnostic flow, answer the minimal verification question, optionally request a hint, and complete the transfer question.
6. Review the evidence-backed mastery change and replanned study blocks.
7. Refresh the page to confirm that the profile persists.

See the [three-minute demo script](docs/memury/DEMO_SCRIPT.md) for the exact presentation path.

## Targeted verification commands

Run these after the Canvas Docker environment is fully initialized:

```bash
docker compose run --rm web bin/rspec \
  spec/services/memury/priority_scorer_spec.rb \
  spec/services/memury/learner_state_updater_spec.rb \
  spec/services/memury/connectors/canvas_native_connector_spec.rb

docker compose run --rm web yarn check:ts
docker compose run --rm web yarn webpack-development
```

Also execute the migration, frontend build, browser walkthrough, keyboard/accessibility review, and a manual check that official grades remain unchanged.

These RSpec, frontend build, TypeScript, browser E2E, and accessibility checks have **not yet been executed** in the current Windows workspace because Docker, Ruby, Yarn, and installed dependencies were unavailable. Only static repository, diff, credential, grade-write, randomness, and required-file checks have been completed here.

## Further documentation

- [Architecture and connector boundaries](docs/memury/ARCHITECTURE.md)
- [Demo script](docs/memury/DEMO_SCRIPT.md)
- [Decision log and known limitations](docs/memury/DECISION_LOG.md)
