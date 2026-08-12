# DeepTutor research and Memury boundary

This note records a read-only review of DeepTutor and the independent Memury
implementation. The reference checkout was cloned from
`https://github.com/HKUDS/DeepTutor` at commit
`456f9c24226e008f1ff07a7e3455d7b4d39f6221` (`v1.5.11`). Its repository states
Apache License 2.0 in `LICENSE`; no DeepTutor source was copied into Canvas.

The paper reviewed was *DeepTutor: Towards Agentic Personalized Tutoring*,
arXiv `2604.26962` (v3). Its central claims are citation-grounded tutoring,
difficulty-calibrated question generation, dynamic learner memory, and an
agent loop that can expose traces and pause for structured user input.

| DeepTutor 学习点 | 实际代码位置 | Memury 对应模块 | 采用方式 | 不采用内容 | Memury 原创增量 |
| --- | --- | --- | --- | --- | --- |
| Hard mastery gates and deterministic progress | `deeptutor/learning/policy.py`, `learning/mastery.py` | `Memury::LearnerStateUpdater`, `RiskEngine` | Adopt the principle that advancement is decided by deterministic evidence, not an LLM claim | DeepTutor book/module state machine and its file-backed store | Cross-course DDL and risk-aware plan reordering remain Memury-owned |
| Persisted pending questions with server-side answer keys | `deeptutor/learning/models.py`, `learning/pending.py` | `Memury::PracticeCandidate`, `Memury::ValidatorContext` | Keep answer material server-side and expose only a public projection | DeepTutor question bank and chat-specific option recovery | Canvas Study Block association and assignment-level next action |
| Provider-neutral capability hooks | `deeptutor/capabilities/protocol.py`, `capabilities/mastery/loop.py` | `Memury::Teaching::Provider` and `ProviderRegistry` | Use a small Ruby protocol for diagnose/guide/generate/validate/transfer/summarize | DeepTutor's full agent loop, tools, partners, RAG engines, and capabilities registry | Canvas-native orchestration across courses and official deadlines |
| Structured output and role separation | `deeptutor/capabilities/protocol.py`, `core/context.py` | `Memury::Ai::StructuredResponseClient`, `TeachingCapabilitySchemas`, role-specific provider methods | One shared Responses transport with strict per-capability schemas and local validation | DeepTutor-specific model/tool wiring and private reasoning traces | OpenAI is optional; deterministic fallback and validation-basis gates remain available without a key |
| Inspectable trace metadata | `deeptutor/core/context.py`, `core/trace.py` | `Memury::Session`, `Memury::Step`, `Memury::Evidence` | Persist a three-level learning trace with structured payloads and evidence fingerprints | Raw model reasoning traces, broad chat history, or hidden vector memory | Every evidence row links to a Canvas task/study block and can explain plan changes |
| Independent grading/validation | `deeptutor/learning/grading.py`, `learning/service.py` | `DeterministicProvider#validate_practice` and `#assess_transfer` | Separate candidate validation from learner-answer assessment; fail closed | DeepTutor's full Mastery Path UX and question bank integration | A validated transfer event is the only positive trigger for risk and Study Block replanning |
| Three-layer memory (L1/L2/L3) | README memory section; the paper's dynamic memory framing | Session/Step/Evidence plus existing LearnerProfile state | Use the auditability lesson, with evidence provenance and before/after decisions | L1/L2/L3 files, memory graph UI, consolidator budgets | Memury's `LearnerProfile` remains Canvas-scoped and deterministic |

The implementation is method research with an independent implementation, not
a DeepTutor adapter and not a code copy. DeepTutor is a teaching-capability
reference; it is not a runtime dependency of Memury.
