const canvasUrl = "https://canvas.memury.net/login";
const githubUrl = "https://github.com/Spiderrrrrr-44/memury-canvas";

export default function Home() {
  return (
    <main>
      <nav className="site-nav" aria-label="Primary navigation">
        <a className="wordmark" href="#top" aria-label="Memury home">
          <span>M</span>
          Memury
        </a>
        <div className="nav-links">
          <a href="#q-graph">Q Graph</a>
          <a href="#memory">Learning Memory</a>
          <a href="#submission">Materials</a>
          <a href={githubUrl}>GitHub</a>
        </div>
        <a className="nav-cta" href={canvasUrl}>
          Open Canvas
        </a>
      </nav>

      <section className="hero" id="top">
        <div className="hero-copy">
          <div className="live-pill">
            <i /> Live on Canvas
          </div>
          <p className="eyebrow">MEMURY · LEARNING IN CONTEXT</p>
          <h1>
            Learning shouldn&apos;t
            <br /> lose its context.
          </h1>
          <p className="hero-lead">
            Open a course document with Q Graph. Ask freely, branch from any
            idea, and leave with the whole conversation summarized—without
            breaking away from Canvas.
          </p>
          <div className="hero-actions">
            <a className="button primary" href={canvasUrl}>
              Try the live Canvas <span aria-hidden="true">↗</span>
            </a>
            <a className="button secondary" href="#q-graph">
              See how it works <span aria-hidden="true">↓</span>
            </a>
          </div>
          <p className="hero-note">
            Open source · Canvas-native · Official grades stay read-only
          </p>
        </div>

        <div className="product-scene" aria-label="Q Graph product preview">
          <div className="ambient ambient-one" />
          <div className="ambient ambient-two" />
          <article className="document-card">
            <header>
              <span className="file-icon">F</span>
              <div>
                <strong>Force analysis</strong>
                <small>Assignment document · Canvas</small>
              </div>
              <span className="verified">Official</span>
            </header>
            <p>
              A force does work only when displacement has a component along
              the force.
            </p>
            <button type="button" tabIndex={-1}>
              <b>Q</b> Open with Q Graph
            </button>
          </article>

          <article className="conversation-card">
            <header>
              <span>Q</span>
              <div>
                <strong>Q Graph</strong>
                <small>Grounded in this document</small>
              </div>
            </header>
            <div className="chat assistant">
              The key condition is the component of displacement along the
              force—not displacement alone.
            </div>
            <div className="chat user">
              What if displacement is perpendicular?
            </div>
            <div className="summary-chip">✓ Whole conversation summarized</div>
          </article>

          <div className="graph-path" aria-hidden="true">
            <span />
            <i />
            <span />
            <i />
            <span className="current" />
          </div>
        </div>
      </section>

      <section className="signal-strip" aria-label="Memury product principles">
        <span>Document-grounded</span>
        <i />
        <span>Persistent branches</span>
        <i />
        <span>Explainable planning</span>
        <i />
        <span>Verified learning memory</span>
      </section>

      <section className="opening" id="q-graph">
        <p className="eyebrow">ONE DOCUMENT · MANY PATHS</p>
        <h2>A conversation you can come back to.</h2>
        <p>
          Q Graph keeps each question beside the source that sparked it. Follow
          an idea, open a branch, then return without losing the document or the
          path you took through it.
        </p>
      </section>

      <section className="workflow-shell" aria-label="Q Graph workflow">
        <div className="workflow-bar">
          <div className="traffic-lights" aria-hidden="true">
            <i />
            <i />
            <i />
          </div>
          <span>PHYS 101 · Week 3</span>
          <span className="workflow-status">Saved to learning memory</span>
        </div>
        <div className="workflow-grid">
          <aside className="source-pane">
            <p className="panel-label">SOURCE</p>
            <h3>Work and energy</h3>
            <p>
              When force and displacement are perpendicular, their dot product
              is zero. The force does no work on the object.
            </p>
            <mark>force and displacement are perpendicular</mark>
            <div className="source-anchor">
              <span>§ 3.2</span>
              Return to this passage
            </div>
          </aside>
          <div className="dialogue-pane">
            <p className="panel-label">Q GRAPH CONVERSATION</p>
            <div className="dialogue-row question">
              <span>You</span>
              <p>What if the displacement is perpendicular to the force?</p>
            </div>
            <div className="dialogue-row answer">
              <span>Q</span>
              <div>
                <p>
                  Then the force contributes no work: <strong>W = Fd cos 90° = 0</strong>.
                  It can still change direction, just not kinetic energy.
                </p>
                <small>Grounded in § 3.2 · View source</small>
              </div>
            </div>
            <div className="branch-line" aria-hidden="true">
              <i />
              <span />
              <b />
            </div>
            <div className="branch-options">
              <span>Why can direction still change?</span>
              <span>Show a circular-motion example</span>
            </div>
            <div className="conversation-summary">
              <span>Conversation summary</span>
              <p>
                Work depends on the component of displacement along a force;
                perpendicular forces can redirect motion without changing speed.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="modes-section">
        <div className="section-heading">
          <p className="eyebrow">MEET THE LEARNER WHERE THEY ARE</p>
          <h2>One product. Three ways forward.</h2>
          <p>
            The interface changes with the moment—not the underlying learning
            memory.
          </p>
        </div>
        <div className="mode-grid">
          <article className="mode-card direct">
            <div className="mode-icon">↗</div>
            <p className="mode-number">01 · DIRECT</p>
            <h3>Start from the question.</h3>
            <p>
              Upload a document or open a Canvas assignment. Get a grounded
              explanation, key concepts, and the next useful question.
            </p>
            <span>Question → source → understanding</span>
          </article>
          <article className="mode-card review">
            <div className="mode-icon">◎</div>
            <p className="mode-number">02 · REVIEW</p>
            <h3>Return to what is fading.</h3>
            <p>
              Review from the original passage and conversation, prioritized by
              evidence instead of a generic flashcard queue.
            </p>
            <span>Memory → evidence → reinforcement</span>
          </article>
          <article className="mode-card continuous">
            <div className="mode-icon">∞</div>
            <p className="mode-number">03 · CONTINUOUS</p>
            <h3>Let the plan evolve.</h3>
            <p>
              Turn verified Canvas activity and your own reflections into an
              explainable plan that updates as you learn.
            </p>
            <span>Progress → reflection → next step</span>
          </article>
        </div>
      </section>

      <section className="memory-section" id="memory">
        <div className="memory-copy">
          <p className="eyebrow">VERIFIED LEARNING MEMORY</p>
          <h2>Your learning history, with receipts.</h2>
          <p>
            Memury separates official Canvas records from AI inferences. Every
            recommendation can show where it came from, what changed, and why it
            belongs in your plan.
          </p>
          <ul>
            <li><span>✓</span> Official grades and submissions stay read-only</li>
            <li><span>✓</span> Inferences retain their evidence and confidence</li>
            <li><span>✓</span> Plans explain the reason behind every next step</li>
          </ul>
        </div>
        <div className="memory-board">
          <article className="memory-card official-record">
            <header>
              <span>Verified record</span>
              <b>Canvas</b>
            </header>
            <h3>Force analysis assignment</h3>
            <div className="record-line">
              <span>Submitted</span>
              <strong>Aug 15 · 20:42</strong>
            </div>
            <div className="record-line">
              <span>Score</span>
              <strong>8 / 10</strong>
            </div>
          </article>
          <article className="memory-card inference-record">
            <header>
              <span>Learning inference</span>
              <b>86% confidence</b>
            </header>
            <h3>Vector components need reinforcement</h3>
            <p>Based on 2 Q Graph branches and the latest assignment.</p>
            <a href={canvasUrl}>Review the evidence <span>→</span></a>
          </article>
          <article className="next-step-card">
            <span>NEXT STEP · 18 MIN</span>
            <h3>Compare work in linear and circular motion</h3>
            <p>Recommended because it connects today&apos;s open question to § 3.2.</p>
          </article>
        </div>
      </section>

      <section className="trust-section">
        <div id="submission" className="submission-panel">
          <p className="eyebrow">COMPETITION MATERIALS · READY</p>
          <h2>Review the complete Memury submission.</h2>
          <p>Project brief, proposal PDF, product video, source code, and the executable Canvas deployment kit.</p>
          <div className="trust-links">
            <a className="button primary" href="/downloads/Memury_Submission_Pack_2026-08-16.zip">Download the full pack ↓</a>
            <a className="button secondary" href="/downloads/Memury_Demo_2m16s.mp4">Watch the demo ↓</a>
          </div>
        </div>
        <p className="eyebrow">BUILT IN THE OPEN</p>
        <h2>Canvas-native by design.</h2>
        <p>
          Memury is an open-source layer for learning conversations, planning,
          and memory. It preserves Canvas as the system of record and makes the
          AI layer inspectable.
        </p>
        <div className="trust-links">
          <a className="button primary" href={canvasUrl}>Open the live product ↗</a>
          <a className="button secondary" href={githubUrl}>View source on GitHub ↗</a>
        </div>
      </section>

      <footer>
        <a className="wordmark" href="#top">
          <span>M</span>
          Memury
        </a>
        <p>Learning in context.</p>
        <div>
          <a href="#q-graph">Q Graph</a>
          <a href="#memory">Learning Memory</a>
          <a href="#submission">Materials</a>
          <a href={githubUrl}>GitHub</a>
        </div>
      </footer>
    </main>
  );
}
