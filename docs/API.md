# Material Editing API v2

TypeSpec in `service/*.tsp` is the source of truth for routes and schemas. This document explains cross-endpoint behavior, compatibility and integration boundaries. API contracts do not establish backend implementation completion.

The contract extends current `origin/main` (`7563d6d`) and retains its student progress, student grade and agentic Chat contracts. API navigation uses `/api/...` resource paths, matching the existing reference. Operation purposes and detailed rules remain in English descriptions rather than overriding navigation labels with summaries. Educational content in examples may be localized.

Sources: [SciEdu material editing requirements](https://app.notion.com/p/4137dadd804080b68ca1cd463a95513a) and the [existing frontend presentation registry](https://github.com/NYCU-SDC/sciedu-frontend/blob/3fbd5a0cdf047111a33c1b4efff311daa4bc28a6/src/features/courses/player/presentation.ts). The stage and simulation whitelists come from that registry.

## New operations

All paths below have the `/api` prefix and use the `access_token` session cookie.

| Method and path | Permissions | Success |
| --- | --- | --- |
| GET `/courses/{id}/editor` | ADMIN / EXPERIMENTER | 200 EditorDocument, consistent read-only snapshot |
| PUT `/courses/{id}/editor` | ADMIN / EXPERIMENTER | 200 EditorDocument, atomic save and revision+1 |
| POST `/courses/{id}/copies` | ADMIN / EXPERIMENTER | 201 EditorDocument, new DRAFT at revision=1 |
| GET `/chat/presets` | ADMIN / EXPERIMENTER | 200 PresetCatalog, all built-in and custom presets |
| PUT `/experiments/{experimentId}/courses/{courseId}/replacement` | ADMIN / EXPERIMENTER | 200 ManagementExperimentCourseAssignment |
| GET `/chat/course?experimentId=…&courseId=…&pageId=…` | STUDENT and owned scope | 200 `{chatId: UUID \| null}`, lookup only |

Editor preview uses a local frontend controller without real Chat, submission or page-visit side effects. No page-scoped editor, preview API or upstream preset-management write API is added.

## Documents and references

`Materials.DocumentInput` is the writable document. `EditorDocument` adds hydrated resources and server-computed fields; it cannot be sent back unchanged as a write request. Writes reject Course id, revision, status, resources, editable, warnings, displayOrder and timestamps. Put the expected revision in the outer expectedRevision field. Omitting a persisted Page or Block removes its reference, not its Content or Question.

- Course schemaVersion and Course/Page presentation.version are 2. Existing legacy version=1 configuration remains supported by the legacy adapter.
- PageBlock still contains only TEXT, MEDIA or QUESTION references. Simulation, reading-group and answer-reference are presentation nodes, not artificial resources.
- Clients generate Page/Block/node UUIDs and the server preserves them. Reject duplicates across the document, IDs taken from another course/page and reuse after persisted deletion. Cross-page copies and restoration after persisted deletion need new IDs.
- Each resource Block has exactly one same-page node of the matching resource type. TEXT/MEDIA required is false; question input matches Question.type. Question Block order matches depth-first question-node order.
- Answer references target a preceding page in the same course using pageId plus questionBlockId, not a display number or questionId. Reordering/deletion must repair references in the same snapshot or return 422.
- Reading groups cannot nest. Image/text cards require at least one text and one image; CCM also supports text plus simulation. Children reject layout; free-grid top-level nodes require it; fixed-template nodes reject dimensions.
- contextTextIds contains authorized, FK-protected context-only TEXT resources, without a visible body node or a special order=200 convention.
- Preserve preview/previewLabel for static teaching pages. preview=true pages cannot contain simulations. This is distinct from local editor preview.
- Lengths count Unicode code points. Limits: 500 pages; 1,000 Blocks, 1,000 total nodes including children and 100 contextTextIds per page; 5 MiB request JSON and 20 MiB hydrated resource text. Return 413 without truncation.

Runnable examples: [empty/general/SciArg/CCM requests](examples/material-editor.json) and [a complete response](examples/material-editor-response.json). These are contract examples, not the complete production-course migration fixtures.

## Changes to existing operations

| Operation | Change |
| --- | --- |
| POST `/courses`, `/content/text`, `/content/media`, `/questions` | Require Idempotency-Key and replay the original resource. Course creation returns revision=1. Coordinate the new header requirement with existing clients |
| GET `/courses/{id}`, `/courses/{courseId}/pages`, `/pages/{id}` | Add optional revision/presentation. Only persisted v2 returns presentation; editor GET never switches the student format. Page.revision is the containing Course revision |
| PUT `/courses/{id}/status` | v2 requires expectedRevision and Idempotency-Key. Legacy bodies and absent headers remain accepted. Backend enforces conditional requirements |
| Legacy Course metadata, Page/Block CRUD and ordering | Valid legacy mutations advance Course revision. V2 returns 409 EDITOR_DOCUMENT_REQUIRED and uses the complete editor document. All writes enforce permanent usage protection |
| Content/Question reads and mutations | Enforce student resource reachability and shared-resource protection. Use copy-on-write for v2/protected references. Formal answer/grading contracts are unchanged |
| GET `/experiments/{id}/courses` | Management may read the original course.preset after completion/archival; unreliable history is LEGACY_UNCONFIRMED. Preserve existing student access and omit management-only preset data |
| Experiment status and course assignment mutations | First ACTIVE permanently freezes course content/preset and associations, including later status rollback/completion/archival |
| POST `/chat` | Optional body. General chats retain 201 `{chatID}`; courseContext returns 201 `{chatId}` for new bindings or 200 `{chatId}` for existing bindings |
| POST `/chat/{chatId}` | Retain general-chat client preset behavior. Bound course chats resolve their course preset, ignore client overrides and enforce the acceptance-time read-only boundary |
| Chat history/SSE | Add optional Message.errorCode. Preserve origin/main Message.parts/characters/agentRuns, typed StreamEvent, required delta.index and part_end.part. The existing eight event types and unnamed frames are unchanged |

Course reads do not gain an experimentId query. Students still require a PUBLISHED course assigned to their current valid experiment. Owned course-chat history uses the original binding after completion; that does not grant broader historical teaching-material access.

## Transactions, revisions and retries

Use experiment locks when involved, followed by Course locks in UUID order and then Page/Block locks. Document writes, legacy mutations, publication, experiment associations and first ACTIVE must coordinate a consistent protocol, preventing activation between eligibility checks and writes.

Authorize first, then look up successful actor+method+resource-path+Idempotency-Key results, then validate state, revision and references. Hash the complete semantic request, including multipart file digest. Commit successful results and the operation together and retain them for at least 24 hours. Successful replay survives later revision/state changes. Different payloads under the same key and in-flight requests return 409. After retention expires, reconcile unknown outcomes before retrying; do not blindly recreate resources.

A course used by any formally started experiment permanently retains its content and preset. Published courses can be edited in place only if every referencing experiment has never started; enforce publication completeness and retain PUBLISHED. Unconfirmed legacy usage is protected and can be copied instead. Do not expose internal activation/usage timestamps, fabricate historical times or treat NULL as proof of no prior use.

Copies may use protected sources. Remap Page/Block/node/Question/option IDs and internal references, preserve profile/appearance/preset, and share immutable TEXT/MEDIA where appropriate. Do not copy student data, experiment associations or chats. Return a warning when correct answers are not copied.

## Presets and publication

Writes accept only document.presetId; selection and availability are computed read fields. Omission preserves the selection and null explicitly clears it to UNSELECTED. Copies can retain LEGACY_UNCONFIRMED. First or changed non-null IDs require catalog verification: a missing new ID returns 422, unavailable verification 503, and neither writes the document.

An unchanged selected ID may be saved with warnings if removed or temporarily unverifiable. Any chatEnabled=true page requires SELECTED before publication; all-chat-disabled courses may publish without a selection. Removed/unverifiable existing selections may still publish with warnings and the experiment may activate. Never infer or replace identifiers from profile, current frontend defaults or availability.

The first release batch validates editing, image/text cards, preview and all-chat-disabled publication. Enable v2 student courses with chat only after second-batch preset/chat/replacement acceptance. This is a release gate, not another API.

## Images and resource storage

Media multipart retains content and adds optional purpose=material-image; omission retains generic-media behavior. Material images allow JPEG/PNG/WebP, at most 10 MiB and 40 decoded megapixels, checked using actual decoding. Reject SVG/HTML. Material-image creation returns MaterialImageResource with controlled url, MIME, dimensions and sizeBytes; generic uploads retain MediaContent.

Reads retain session/CORS checks. Images return inline disposition, correct MIME/Length and nosniff. Editor resources exclude storage paths, bytes, correct answers and student submissions. Coordinate staged media storage with operation records so retries return the same resource ID; backend cleanup handles failures. Wait at least seven days before collecting orphans and scan PageBlock/context/unfinished-operation references. Course deletion must not immediately cascade into resource deletion.

## Bound course chats

A binding is unique by user+experiment+course+page. GET lookup never writes. Chat and binding creation commit together; racing creators receive the same ID without orphan chats. Look up on page entry and create only before the first message. Do not move old unbound conversations into new bound chats.

Every course-chat send/retry/regeneration resolves the bound course preset and rechecks write access. After completion/archival, lookup and owned history remain readable, while creation/message acceptance returns COURSE_CHAT_READ_ONLY. Previously accepted generation may finish and persist after releasing DB locks; never hold locks while waiting for SciLLM.

Failures known before 201 use HTTP 409/503. Failures discovered afterward use SSE error.code and persist the same Message.errorCode. Only an agreed structured upstream signal identifies preset removal; do not interpret arbitrary 400/detail text. Per-turn prompt/preset versioning and multiple formal attempts in the same experiment are outside this scope.

## Errors and upstream integration

Errors use application/problem+json and existing summer ProblemDetail fields. Generic 400/401/403/404/500 keep summer types; new business failures use `type=urn:sciedu:problem:<kind>`. Clients branch on HTTP status/type, not detail. Error detail starts lowercase without trailing punctuation.

Current summer v1.0.0-test has no code/currentRevision/issues extensions; this contract does not require them. On a revision conflict, GET editor for comparison without automatically overwriting local changes. SSE code and warnings.code are separate declared data fields, not ProblemDetail extensions.

Remaining Backend/SciLLM integration points:

- Catalog access credentials, complete built-in/custom listing and consistency with the execution environment; prefer existing SciLLM GET /admin/presets.
- A reliable unknown-preset response, with HTTP 400 plus PRESET_NOT_FOUND as a candidate only. Do not implement detail-string matching as a reliable substitute.
- Evidence for historical course usage and preset backfill, applying the confirmed conservative policy instead of current defaults.

## Verification

```sh
pnpm run check:materials
pnpm run yaak
pnpm exec prism mock tsp-output/schema/openapi.1.0.0.yaml --port 4018 --host 127.0.0.1
# In another terminal:
node scripts/verify-material-editor-contract.mjs http://127.0.0.1:4018
```

Checks cover six new and 38 affected existing successes/auth/idempotency/error media types, English API entry points, privacy, origin/main compatibility and positive/negative JSON Schema cases. Prism selects declared 422 for schema failures on operations that provide it; backend malformed requests or missing headers still follow the documented 400 contract. Backend integration tests must verify reference graphs, actual authorization, atomic transactions, permanent locks, image limits and real SciLLM behavior.
