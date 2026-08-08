# Memury

**An LMS-native, goal-aware adaptive learning agent built on Canvas LMS.**

Memury turns fragmented academic information—courses, assignments, deadlines, schedules, submissions, and learning evidence—into an actionable study plan. It then uses active diagnosis to identify likely misconceptions, provide targeted interventions, update the learner state, and dynamically adjust the plan.

> Memury is an independent project built on the open-source Instructure Canvas LMS. It is not an official Instructure product.

## Why Memury?

Traditional learning platforms mainly tell students what content exists and when work is due. They rarely answer the more useful question:

> What should I do next, and why?

Memury adds an agentic learning layer to Canvas. It combines official course data with an evolving learner state to prioritize tasks, schedule study actions, diagnose learning difficulties, and replan when new evidence appears.

## Core workflow

```text
Canvas student data
→ normalized academic timeline
→ deterministic risk and priority scoring
→ next best learning action
→ executable study blocks
→ active misconception diagnosis
→ learner-state update
→ plan adjustment
```

Memury currently supports two connected loops:

1. **Academic Planning Loop**

   Course and deadline synchronization → risk scoring → study blocks → completion, skipping, or rescheduling.

2. **Adaptive Learning Loop**

   Candidate misconception → minimal verification → graduated hints → transfer question → evidence-based learner-state update.

## Current MVP capabilities

- Canvas global navigation entry controlled by a RootAccount Feature Flag.
- Student-scoped synchronization of active courses, assignments, and the current user’s submission summaries.
- Explicitly labeled demo SIS schedule and exam data.
- Deterministic task-risk scoring with human-readable explanations.
- Three-stage study blocks that can be completed, skipped, or deferred.
- Active diagnostic flow with candidate causes, verification, hints, and transfer questions.
- Server-side AI diagnosis with strict schema validation and deterministic fallback.
- Persistent learner profiles, evidence, decision logs, and study plans.
- Demo mode that does not require an external AI API key.
- Read-only handling of Canvas grades and submissions.
- Provenance fields for official, inferred, and simulated data.

## Architecture

```text
Current Canvas user
→ CanvasNativeConnector / DemoSisConnector
→ normalized provenance-aware data
→ PriorityScorer
→ Study Blocks
→ diagnostic workflow
→ LearnerStateUpdater
→ Evidence / DecisionLog
→ persistent learner state and replanning
```

The agent logic, connectors, controllers, and interface are separated so that future integrations can support LTI, Blackboard, OneRoster, PeopleSoft, or other LMS/SIS platforms.

See [Architecture](docs/memury/ARCHITECTURE.md) for details.

## Repository map

```text
app/controllers/memury_controller.rb
app/services/memury/
ui/features/memury/
docs/memury/
README_MEMURY.md
README_CANVAS_UPSTREAM.md
```

Important documentation:

- [Detailed Memury setup and development guide](README_MEMURY.md)
- [Architecture](docs/memury/ARCHITECTURE.md)
- [Demo script](docs/memury/DEMO_SCRIPT.md)
- [Decision log](docs/memury/DECISION_LOG.md)
- [Original Canvas README](README_CANVAS_UPSTREAM.md)

## Demo data and real data

The current MVP uses real Canvas data for the signed-in student’s accessible courses, assignments, and submission summaries.

The following elements are currently simulated and must remain clearly labeled in the interface:

- SIS class schedule;
- demo exam event;
- predefined diagnostic questions;
- selected demo learning evidence.

Official Canvas deadlines must remain distinguishable from Memury-generated plans and user overrides.

## Local setup

Canvas LMS has a substantial development environment. Review the official Canvas setup documentation before starting:

- [Canvas LMS repository](https://github.com/instructure/canvas-lms)
- [Canvas Quick Start](https://github.com/instructure/canvas-lms/wiki/Quick-Start)

After preparing a compatible Canvas development environment:

```bash
cp .env.memury.example .env.memury
docker compose up -d
docker compose run --rm web bundle exec rails db:migrate
docker compose run --rm -e LOGIN=memury.student@example.test web bundle exec rake memury:demo_seed
docker compose run --rm web yarn build:watch
```

Create or configure the demo student account described in [README_MEMURY.md](README_MEMURY.md), enable the Memury feature for the relevant root account, sign in as that student, and open **Memury** from the Canvas global navigation.

For the complete walkthrough, see [Demo script](docs/memury/DEMO_SCRIPT.md).

## Verification status

Completed static checks:

- `git diff --check`;
- review for accidentally committed credentials and local environment files;
- review for unintended grade writes;
- review for random learner-state updates;
- presence checks for Memury routes, navigation, services, migration, tests, and documentation.

The following verification still needs to be completed in a fully configured Canvas environment:

- database migration execution;
- targeted RSpec test execution;
- TypeScript type checking and frontend build;
- browser-based end-to-end demo;
- accessibility testing.

This repository should therefore be treated as an early Canvas-first MVP implementation, not yet as a production deployment.

## Safety and data boundaries

- Connectors are scoped to the current authenticated student.
- Memury does not accept arbitrary student IDs from the client.
- Canvas grades, submissions, and instructor data are treated as read-only.
- LMS or SIS passwords are not stored.
- External, inferred, and simulated information retains provenance metadata.
- Memury-generated plans are not presented as official instructor deadlines.
- The interface must identify Memury as an independent prototype.

## Roadmap

- Run and validate the complete MVP in the official Canvas development environment.
- Map Canvas Modules, Pages, Calendar, Planner, feedback, and assessment scope.
- Add conflict detection and editable study-block controls.
- Expand the server-side AI provider with richer curriculum-specific prompt packs.
- Replace demo SIS data with authorized institutional connectors.
- Add browser E2E, accessibility, security, and privacy tests.

## Upstream and license

Memury is built on [Instructure Canvas LMS](https://github.com/instructure/canvas-lms).

The upstream Canvas source, copyright notices, and license terms remain applicable. Canvas LMS is distributed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE) and the preserved [Canvas upstream README](README_CANVAS_UPSTREAM.md).

“Canvas” and “Instructure” belong to their respective owners. Memury is not affiliated with or endorsed by Instructure.
