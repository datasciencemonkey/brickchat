# Aladdin Autonomy Levels Vision

## Overview

**Aladdin** (formerly BrickChat) implements a progressive autonomy model where users can interact with AI capabilities at increasing levels of sophistication. Named "Aladdin" because it rhymes with "all-add-in" — a single interface to control the chaos.

Each level builds upon the previous, with Level 3 representing full orchestration through Claude Agent SDK.

---

## Autonomy Levels

> **Note:** There is no "Level 0" in Aladdin. Every thread operates at Level 1, 2, or 3. Users choose the level when creating a thread.

### Level 1: Document-Augmented Interaction
**Description**: LLM interaction enhanced with user-provided artifacts.

- User uploads documents (PDF, etc.)
- "Talk to my PDF" functionality
- Document-grounded responses with citations
- Context retrieved from user's artifacts

**Status**: ✅ Implemented (document chat mode)

---

### Level 2: Direct Agent Interaction
**Description**: Direct chat with a specific Databricks Agent Brick — no orchestration.

- User selects a specific agent to chat with
- Messages go directly to that agent
- No routing logic, no Claude orchestration
- Simple request → agent → response flow

**Status**: ✅ Implemented (agent chat)

---

### Level 3: Autonomous Mode (Claude Orchestration)
**Description**: Full autonomy through Claude as orchestrator with intelligent routing, skills, and tools.

**Current Capabilities** (implemented as "autonomous mode"):
- Claude orchestrates and intelligently routes to Databricks Agent Bricks
- Admin discovers and configures agents
- Intelligent routing based on user query and agent descriptions
- Streaming responses with agent attribution

**Future Capabilities** (planned enhancements):
1. **Skill System** - Users can:
   - Upload their own skills to personal volume directory
   - Use admin-configured skills
   - Download/share skills outside Aladdin

2. **Extended Tool Access**:
   - File read/write on user's volume directory
   - External API calls (web search, HTTP requests)

3. **Subsumes Lower Levels** - Level 3 can:
   - Do everything Level 1 can do (document-augmented chat)
   - Do everything Level 2 can do (chat with agents)
   - Execute user skills
   - Access files and external APIs
   - Combine multiple capabilities in one conversation

**Status**: ✅ Partially implemented (agent routing), 🔲 Skills & extended tools planned

**Key Difference from Level 2:** In Level 2, user picks *one* agent and talks directly to it. In Level 3, Claude decides which agent(s) to use based on the conversation.

---

## Level 3 Architecture Considerations

### Skill Storage: Dual-Source Design

Two potential sources for skills:

| Source | Purpose | Sharing Model |
|--------|---------|---------------|
| **PostgreSQL Database** | Admin-configured skills, system defaults | Global (all users) |
| **User Volume Directory** | User-uploaded skills, personal customizations | Per-user, shareable via volume |

**Rationale for Volume Storage**:
- Users can share skills by granting volume access to others
- Familiar file-based workflow for skill authoring
- Easy import/export of skill bundles
- Filesystem-based version control possible

**Rationale for Database Storage**:
- Admin-curated, quality-controlled skills
- Centralized management and updates
- Audit trail and usage analytics
- No file permission complexity

### Open Questions

1. **Skill Format**: What schema/format should skills follow?
   - Claude Code skill format (markdown with frontmatter)?
   - Custom JSON schema?
   - Python/code-based skills?

2. **Skill Discovery**: How does the agent discover available skills?
   - Scan volume directory on each request?
   - Cache skill registry with refresh?
   - Index skills in database with volume path reference?

3. **Skill Execution**: How does Claude Agent SDK execute skills?
   - Skills as system prompts/instructions?
   - Skills as tool definitions?
   - Skills as sub-agent configurations?

4. **Conflict Resolution**: What happens when database and volume have same skill?
   - User volume takes precedence?
   - Database (admin) takes precedence?
   - Present both with disambiguation?

5. **Security**: How to validate user-uploaded skills?
   - Sandboxed execution?
   - Skill review process?
   - Capability restrictions?

---

## Implementation Roadmap

### Phase 1: Foundation
- [ ] Define skill schema/format
- [ ] Implement skill storage layer (database + volume)
- [ ] Create skill discovery service
- [ ] Add skill management UI

### Phase 2: Claude Agent SDK Integration
- [ ] Deploy Claude Agent SDK backend service
- [ ] Implement skill loading from dual sources
- [ ] Build orchestration logic for level selection
- [ ] Add conditional agent/skill routing

### Phase 3: User Experience
- [ ] Skill upload UI
- [ ] Skill sharing mechanism
- [ ] Skill marketplace/discovery
- [ ] Usage analytics and recommendations

---

## Gaps in Thinking & Unresolved Design Questions

### 1. ~~What IS a Skill at Level 3?~~ ✅ RESOLVED

**Decision**: Skills are **Claude Code Skills** — markdown files with YAML frontmatter.

**Skill Structure:**
```
my-skill/
├── SKILL.md          # Required: skill definition
├── scripts/          # Optional: helper scripts
├── references/       # Optional: reference docs
└── assets/           # Optional: other resources
```

**SKILL.md Format:**
```markdown
---
name: My Skill Name
description: When to use this skill (triggers auto-activation)
version: 1.0.0
user-invocable: true        # Optional: shows in slash menu
allowed-tools: [Read, Write] # Optional: restrict tools
---

# Skill Instructions
Instructions Claude follows when skill is activated.
```

**Key Characteristics:**
- **Prompt-based** — instructions for Claude, not executable code
- **Declarative** — `description` field determines when Claude auto-activates
- **Portable** — users can author skills externally and upload them
- **Progressive loading** — metadata always in context, body loaded on trigger

---

### 2. ~~Dual-Source Complexity vs. Unified Model~~ ✅ RESOLVED

**Decision**: **Volume is the source of truth** for user skills. Database indexes for discovery.

**User Workflow:**
1. User authors skill externally (any text editor, IDE, etc.)
2. User uploads skill via Aladdin UI → stored in their volume directory
3. User can download their skills anytime for editing/sharing outside Aladdin
4. Sharing happens outside Aladdin (email, git, Slack, etc.)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                     User's Workflow                          │
│  Author skill locally → Upload → Use in Aladdin → Download  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Aladdin Backend                           │
│                                                              │
│  Volume (per-user)              Database (index/cache)       │
│  ┌──────────────────┐          ┌────────────────────────┐   │
│  │ /users/{id}/     │  sync    │ skills table           │   │
│  │   skills/        │ ───────► │   skill_id, user_id    │   │
│  │     my-skill/    │          │   name, description    │   │
│  │       SKILL.md   │          │   volume_path          │   │
│  └──────────────────┘          │   last_synced          │   │
│         ↑                      └────────────────────────┘   │
│         │ upload/download                                    │
│  ┌──────┴───────┐                                           │
│  │  Aladdin UI  │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

**Why Volume as Source of Truth:**
- Users own their skills as files
- Download anytime for external editing
- Share via any mechanism (git, email, etc.)
- No lock-in to Aladdin's database format

**Database Role:**
- Index skills for fast discovery/search
- Cache metadata for routing decisions
- Track usage analytics
- NOT the authoritative source

**Admin Skills:**
- Admin-configured skills also live in a volume (system volume)
- Same format, same discovery mechanism
- Differentiated by `owner: system` vs `owner: {user_id}`

---

### 3. ~~How Does Claude Agent SDK Fit In?~~ ✅ RESOLVED

**Decision**: **Stateless backend, stateful thread** — same pattern as existing Levels 0-2.

**Request Flow:**
```
┌─────────────────────────────────────────────────────────────────┐
│  Flutter Client                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Thread State (accumulated messages)                        │  │
│  │ [user msg 1] [assistant msg 1] [user msg 2] [assistant...] │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼ send full history                 │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  FastAPI Backend (stateless per-request)                         │
│                                                                  │
│  1. Receive request + conversation history                       │
│  2. Instantiate Claude Agent SDK agent                           │
│  3. Load user's skills from volume (inject as context)           │
│  4. Agent executes:                                              │
│     - May use skills                                             │
│     - May call Databricks Agent Bricks as tools                  │
│     - May do direct LLM response                                 │
│  5. Stream response back to client                               │
│  6. Agent instance disposed                                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Flutter Client                                                  │
│  - Append assistant response to thread                           │
│  - Thread now has one more message pair                          │
└─────────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Thread accumulates messages client-side (same as now)
- Backend instantiates SDK agent fresh per request
- Conversation history passed as context to agent
- No server-side agent persistence needed
- Consistent with existing Level 0-2 architecture

---

### 4. ~~Level Selection Logic~~ ✅ RESOLVED

**Decision**: **Thread is locked to a single level at creation time.**

**Thread Types (mutually exclusive):**
| Level | Thread Type | How User Creates |
|-------|-------------|------------------|
| Level 1 | Document Thread | Upload a PDF → thread bound to that document |
| Level 2 | Agent Thread | Select a specific agent → thread bound to that agent |
| Level 3 | Autonomous Thread | Enable autonomous mode → Claude orchestrates |

**Key Insight:** There is no "Level 0" in Aladdin. Every thread operates at Level 1, 2, or 3.

**UI Flow:**
```
┌─────────────────────────────────────────────────────────────┐
│  New Thread Creation                                         │
│                                                              │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────────┐  │
│  │  Upload PDF   │  │ Select Agent  │  │ Autonomous Mode │  │
│  │  (Level 1)    │  │ (Level 2)     │  │ (Level 3)       │  │
│  └───────────────┘  └───────────────┘  └─────────────────┘  │
│                                                              │
│  Thread level is fixed for the lifetime of the thread        │
└─────────────────────────────────────────────────────────────┘
```

**Implications:**
- No level switching mid-thread
- Thread metadata stores which level it operates at
- Backend knows how to route based on thread type
- Simpler state management (no mid-conversation transitions)

---

### 5. ~~State Management Across Levels~~ ✅ RESOLVED

**Decision**: **No cross-level transitions** — thread level is fixed at creation.

Since a thread is locked to one level:
- Level 1 thread: Always has document context, entire conversation is about that document
- Level 2 thread: Always routes to the selected agent directly
- Level 3 thread: Claude orchestrates for the entire conversation (agents, skills, tools)

**State is simple:**
- Thread stores: `level`, `document_id` (if Level 1), `agent_id` (if Level 2)
- Each message in thread inherits the thread's level
- No need to handle "what if user switches modes" — they can't

**If user wants a different mode:** Start a new thread.

---

### 6. ~~What Can Skills Actually DO?~~ ✅ RESOLVED

**Decision**: Skills are instructions; the **agent has tools**. Skills guide how the agent uses those tools.

**Available Tools for Level 3 Agent:**

| Tool Category | Examples | Purpose |
|---------------|----------|---------|
| **Databricks Agents** | Configured Agent Bricks | Route to specialized agents for domain tasks |
| **File Access** | Read/write user's volume | Access user's documents, skills, data |
| **External APIs** | Web search, HTTP calls | Fetch external information, integrate services |

**How Skills Interact with Tools:**
```
┌─────────────────────────────────────────────────────────────┐
│  Skill (SKILL.md)                                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ "When user asks about sales data:                       ││
│  │  1. First query the Sales Agent for current metrics     ││
│  │  2. Read the user's /reports/templates/sales.md         ││
│  │  3. Format response using the template"                 ││
│  └─────────────────────────────────────────────────────────┘│
│                              │                               │
│                              ▼ instructs                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Claude Agent SDK Agent                                   ││
│  │                                                          ││
│  │ Tools available:                                         ││
│  │ - call_databricks_agent(agent_id, message)              ││
│  │ - read_file(path)                                       ││
│  │ - write_file(path, content)                             ││
│  │ - web_search(query)                                     ││
│  │ - http_request(url, method, body)                       ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**Security Model:**
- File access scoped to user's directory in the volume only (no cross-user access)
- External API calls logged for audit
- Skills can optionally restrict their own tool access via `allowed-tools` frontmatter
- Admin can configure global tool restrictions per deployment

---

### 7. ~~Databricks Agent Bricks vs. Claude Agent SDK~~ ✅ RESOLVED

**Decision**: **Different levels, different architectures.**

| Level | Architecture | Orchestration |
|-------|--------------|---------------|
| Level 2 | User → Agent Brick → Response | None (direct) |
| Level 3 | User → Claude → Agent Brick(s) → Response | Claude orchestrates |

**Level 2 (Direct Agent Chat):**
```
User Message → Databricks Agent Brick → Response
```
- No Claude involvement
- Simple, direct communication with selected agent

**Level 3 (Autonomous Mode):**
```
User Message
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│  Claude Agent (Orchestrator)                                 │
│                                                              │
│  Current tools:                    Future additions:         │
│  ┌────────────────────────┐       ┌────────────────────────┐│
│  │ • Databricks Agents    │       │ • User skills          ││
│  │   (Agent Bricks)       │   +   │ • File read/write      ││
│  │                        │       │ • External APIs        ││
│  └────────────────────────┘       └────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
     │
     ▼
Response (streamed)
```
- Claude decides which agent(s) to call
- Can combine multiple agents in one response
- Future: can also use skills and tools

**Enhancement path:** Expand Level 3's tool set without changing Level 2.

---

### 8. ~~Sharing Semantics~~ ✅ RESOLVED

**Decision**: **Sharing happens outside Aladdin** — copy semantics via download/upload.

**Workflow:**
1. User downloads their skill from Aladdin (as files)
2. User shares via external mechanisms (email, git, Slack, etc.)
3. Recipient uploads the skill to their own Aladdin volume

**Semantics:**
- **Copy**: Recipient gets an independent copy
- No live linking between users
- No in-app sharing mechanism needed
- Simple, decentralized, no permission complexity

**Why this works:**
- Skills are just files (markdown + assets)
- Standard file sharing tools already exist
- No Aladdin infrastructure needed for sharing
- Users have full control over what they share

---

### 9. ~~Skill Versioning~~ ✅ RESOLVED

**Decision**: **Admin skills are versioned; users can choose which version to use.**

**User Skills:**
- User controls their own skills
- Version field is informational (user decides what it means)
- No system-enforced versioning

**Admin Skills:**
- Admin skills are versioned (semver in frontmatter)
- Multiple versions can coexist in system volume
- Users can pin to a specific version or use "latest"

**Implementation:**
```
/system/skills/
├── sales-report/
│   ├── 1.0.0/
│   │   └── SKILL.md
│   ├── 1.1.0/
│   │   └── SKILL.md
│   └── 2.0.0/
│       └── SKILL.md
```

**User Preference:**
- Default: use latest version of admin skills
- Optional: pin to specific version in user settings
- If pinned version is deprecated, warn user but don't break

**Why this works:**
- Admins can iterate on skills without breaking users
- Users who need stability can pin versions
- Simple folder-based versioning (no complex version control)

---

### 10. ~~Cost & Rate Limiting~~ ✅ RESOLVED

**Decision**: **Organization pays; no per-user limits.**

**Cost Model:**
- Organization/admin pays for all API calls (Anthropic + Databricks)
- Same model as other enterprise software (org pays for infrastructure)
- No per-user quotas or billing

**Runaway Loop Protection:**
- Built into Claude Agent SDK (max iterations configurable)
- Admin can set global max tool calls per request
- Timeout limits on individual requests

**Why this works:**
- Simplifies UX (users don't worry about costs)
- Aligns with enterprise deployment model
- Admins can monitor usage via analytics
- If abuse occurs, handle via admin action (not automated limits)

---

## Summary of Decisions

All architectural questions have been resolved:

| # | Question | Decision |
|---|----------|----------|
| 1 | What is a Skill? | Claude Code Skills (markdown + YAML frontmatter) |
| 2 | Skill storage? | Volume is source of truth; DB indexes for discovery |
| 3 | SDK deployment model? | Stateless backend, stateful thread (per-request agent) |
| 4 | Level selection? | Thread locked to level at creation (Level 1, 2, or 3) |
| 5 | State management? | No cross-level transitions; simple thread metadata |
| 6 | Skill capabilities? | Skills are instructions; agent has tools |
| 7 | Agent Bricks vs SDK? | Level 2 = direct; Level 3 = Claude orchestrates |
| 8 | Sharing? | External (download, share via git/email, upload) |
| 9 | Versioning? | Admin skills versioned; users can pin versions |
| 10 | Cost control? | Org pays; no per-user limits |

---

## Next Steps for Implementation

1. **Skill infrastructure**
   - Create skill upload/download endpoints
   - Implement volume directory structure per user
   - Build skill indexing service (volume → database sync)

2. **Extend Level 3 tools**
   - Add file read/write tools (scoped to user's volume)
   - Add external API tools (web search, HTTP)
   - Integrate skills as agent context

3. **Admin skill management**
   - Versioned skill deployment to system volume
   - Admin UI for skill management
   - User settings for version pinning

---

## References

- [Claude Agent SDK Documentation](https://docs.anthropic.com/en/docs/agents-and-tools/claude-agent-sdk)
- DeepWiki MCP for SDK details
- Existing autonomous mode: [deployment/routers/autonomous.py](../deployment/routers/autonomous.py)
