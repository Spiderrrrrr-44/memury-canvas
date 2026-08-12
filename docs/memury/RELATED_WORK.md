# Memury related work

## DeepTutor

Memury's teaching-provider boundary was informed by a read-only study of
DeepTutor (`HKUDS/DeepTutor`) at commit
`456f9c24226e008f1ff07a7e3455d7b4d39f6221`, tag `v1.5.11`. DeepTutor is
licensed under Apache-2.0. This repository contains no copied DeepTutor code,
submodule, runtime dependency, or remote adapter. The relationship is method
research and independent implementation.

| DeepTutor 学习点 | 实际代码位置 | Memury 对应模块 | 采用方式 | 不采用内容 | Memury 原创增量 |
| --- | --- | --- | --- | --- | --- |
| Deterministic mastery gates and grading separation | `deeptutor/learning/policy.py`, `learning/grading.py` | `Memury::LearnerStateUpdater`, `Memury::Teaching::OpenAiProvider` | Provider evidence is validated before deterministic state updates | DeepTutor's complete mastery-path product | Cross-course DDL/risk ordering and plan write-back |
| Role-specific learner context | `deeptutor/core/context.py` | `Memury::Teaching::PlannerContext`, `TutorContext`, `ValidatorContext` | Each capability receives an explicit whitelist | Full conversation replay and unrelated course data in tutor/validator prompts | Canvas-native task, course and study-block association |
| Inspectable traces and evidence | `deeptutor/core/trace.py` | `Memury::Session`, `Step`, `Evidence`, `TraceRecorder` | Persist structured, idempotent evidence and before/after decisions | Raw chain-of-thought, broad chat logs, vector-memory infrastructure | Evidence-linked Next Best Action and Study Block replanning |
| Capability protocols and registries | `deeptutor/capabilities/protocol.py` | `Memury::Teaching::Provider`, `ProviderRegistry` | OpenAI, deterministic fallback and future adapters share a small protocol | DeepTutor's full tools/partners/RAG capability catalog | LMS-native orchestration that remains usable without an API key |

Memury's cross-course scheduling, deadline awareness, deterministic risk
decisions, and verified-learning plan write-back are independent product
work, not claims about DeepTutor implementation equivalence.
