import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

@doc("Shared v2 material-editing contracts. String lengths count Unicode code points. The server must enforce cross-field, reference and authorization rules inside the transaction.")
namespace SciEdu.Materials;

@minValue(1)
@doc("Course document revision. New and migrated legacy courses start at 1; each successful document write advances it once. Clients must preserve JSON int64 values without precision loss.")
scalar Revision extends int64;

@doc("Retain successful results for at least 24 hours. Scope: actor + HTTP method + resource path + key. The same key and semantic request replays the original result; another request returns 409. Authorize before replay, then check revision and state.")
model IdempotencyHeader {
  @header("Idempotency-Key") key: uuid;
}

@doc("Uses the existing summer ProblemDetail fields. Stable business types are urn:sciedu:problem:<kind>; do not parse detail. The current summer version does not support code/currentRevision/issues, so this contract does not require those extensions.")
@error
model MaterialProblem<Status extends integer, Kind extends string> {
  ...OmitProperties<ProblemDetail, "status" | "type">;
  status: Status;
  type: Kind;
}

model ErrorResponse<Status extends integer, Kind extends string> {
  @statusCode statusCode: Status;
  @header("Content-Type") contentType: "application/problem+json";
  @body body: MaterialProblem<Status, Kind>;
}

model StandardErrorResponse<Status, Body> {
  @statusCode statusCode: Status;
  @header("Content-Type") contentType: "application/problem+json";
  @body body: Body;
}
model InvalidRequestProblem {
  ...OmitProperties<ProblemDetail, "status" | "type">;
  status: 400;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/400";
}
model ServerProblem {
  ...OmitProperties<ProblemDetail, "status" | "type">;
  status: 500;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/500";
}
alias BadRequest = StandardErrorResponse<400, InvalidRequestProblem>;
alias Unauthenticated = StandardErrorResponse<401, Unauthorized>;
alias Denied = StandardErrorResponse<403, Forbidden>;
alias Missing = StandardErrorResponse<404, NotFound>;
alias ConflictError = ErrorResponse<
  409,

    | "urn:sciedu:problem:REVISION_CONFLICT"
    | "urn:sciedu:problem:COURSE_NOT_EDITABLE"
    | "urn:sciedu:problem:EDITOR_DOCUMENT_REQUIRED"
    | "urn:sciedu:problem:IDEMPOTENCY_KEY_REUSED"
    | "urn:sciedu:problem:REQUEST_IN_PROGRESS"
    | "urn:sciedu:problem:ASSIGNMENT_CONFLICT"
>;
alias TooLarge = ErrorResponse<
  413,
  "urn:sciedu:problem:DOCUMENT_TOO_LARGE" | "urn:sciedu:problem:MEDIA_TOO_LARGE"
>;
alias UnsupportedMedia = ErrorResponse<
  415,
  "urn:sciedu:problem:UNSUPPORTED_MEDIA"
>;
alias InvalidDocument = ErrorResponse<
  422,

    | "urn:sciedu:problem:INVALID_PRESENTATION"
    | "urn:sciedu:problem:INVALID_REFERENCE"
    | "urn:sciedu:problem:UNSUPPORTED_VERSION"
    | "urn:sciedu:problem:INVALID_TEMPLATE"
    | "urn:sciedu:problem:INVALID_INPUT_TYPE"
    | "urn:sciedu:problem:PRESET_NOT_AVAILABLE"
>;
alias CatalogUnavailable = ErrorResponse<
  503,
  "urn:sciedu:problem:PRESET_CATALOG_UNAVAILABLE"
>;
alias InternalError = StandardErrorResponse<500, ServerProblem>;
alias ReadErrors =
  | BadRequest
  | Unauthenticated
  | Denied
  | Missing
  | InternalError;
alias WriteErrors =
  | ReadErrors
  | ConflictError
  | TooLarge
  | InvalidDocument
  | CatalogUnavailable;

model Warning {
  @doc("Examples: PRESET_REMOVED, PRESET_AVAILABILITY_UNKNOWN, CORRECT_ANSWER_NOT_COPIED. Warnings do not mean the operation failed.")
  code: string;

  message: string;
}

@minLength(1)
@doc("SciLLM preset identifier, persisted verbatim. Never infer it from profile or select a fallback automatically.")
scalar PresetId extends string;

model UnselectedPreset {
  selection: "UNSELECTED";
  presetId: null;
  availability: null;
}
model LegacyUnconfirmedPreset {
  selection: "LEGACY_UNCONFIRMED";
  presetId: null;
  availability: null;
}
model SelectedPreset {
  selection: "SELECTED";
  presetId: PresetId;

  @doc("AVAILABLE when a successful catalog lookup contains the identifier, REMOVED when it does not, UNKNOWN when lookup fails. Availability never rewrites the persisted selection.")
  availability: "AVAILABLE" | "REMOVED" | "UNKNOWN";
}
@discriminated(#{ envelope: "none", discriminatorPropertyName: "selection" })
union PresetState {
  UNSELECTED: UnselectedPreset,
  LEGACY_UNCONFIRMED: LegacyUnconfirmedPreset,
  SELECTED: SelectedPreset,
}

model ChatOverride {
  @maxLength(2000) greeting: string;
  @maxItems(3) suggestions: Suggestion[];
  ...Record<never>;
}
@minLength(1)
@maxLength(200)
@doc("Validate after trimming; entries in the same list must be unique.")
scalar Suggestion extends string;

model ChatAppearance {
  ...ChatOverride;
  @minValue(25) @maxValue(40) ratioPercent: int32;
  @minLength(1) @maxLength(80) name: string;
}

model CoursePresentation {
  version: 2;
  profile: "general" | "sciarg" | "ccm";
  navigation: "stepper";

  @doc("null preserves legacy name, greeting and width ratio. A newly created appearance may use ratioPercent=30. Supply the entire object instead of inferring omitted fields.")
  chatAppearance: ChatAppearance | null;

  ...Record<never>;
}

@doc("Matches sciedu-frontend@3fbd5a0 player/presentation.ts. Never infer a stage from a page index or title.")
union Stage {
  initial: "initial",
  argumentation: "argumentation",
  simulation: "simulation",
  final: "final",
  `ccm-initial`: "ccm-initial",
  `ccm-observation`: "ccm-observation",
  `ccm-discussion`: "ccm-discussion",
  `ccm-final`: "ccm-final",
}

@doc("Matches the existing SIMULATIONS registry. URLs and scripts are not accepted; unknown identifiers return 422.")
union SimulationId {
  `dark-room-v1`: "dark-room-v1",
  `ccm-heart-v1`: "ccm-heart-v1",
  `ccm-marrow-v1`: "ccm-marrow-v1",
}

model GridLayout {
  colSpan: 4 | 6 | 8 | 12;
  rowSpan: 1 | 2 | 3;
  ...Record<never>;
}
model NodeBase {
  @doc("Client UUID unique across the document and distinct from blockId. Do not reuse deleted IDs; copying between pages requires a new UUID.")
  id: uuid;
}
model TextNode extends NodeBase {
  kind: "text";
  blockId: uuid;
  format: "markdown";
  ...Record<never>;
}
model ImageNode extends NodeBase {
  kind: "image";
  blockId: uuid;
  @maxLength(500) alt: string;
  @maxLength(2000) caption: string;
  ...Record<never>;
}
model TextInput {
  kind: "text";
  ...Record<never>;
}
model ChoiceInput {
  kind: "choice";
  ...Record<never>;
}
model TextChoiceInput {
  kind: "text-choice";
  @minItems(2) @maxItems(10) options: TextChoiceOption[];
  ...Record<never>;
}
@minLength(1)
@maxLength(100)
scalar TextChoiceOption extends string;
@discriminated(#{ envelope: "none", discriminatorPropertyName: "kind" })
union QuestionInput {
  text: TextInput,
  choice: ChoiceInput,
  `text-choice`: TextChoiceInput,
}
model QuestionNode extends NodeBase {
  kind: "question";
  blockId: uuid;
  @maxLength(200) label: string;

  @doc("text/text-choice require a TEXT Question; choice requires CHOICE. text-choice options must be unique and submissions still use textAnswer.")
  input: QuestionInput;

  ...Record<never>;
}
model SimulationNode extends NodeBase {
  kind: "simulation";
  simulationId: SimulationId;
  ...Record<never>;
}
model AnswerReference {
  @doc("A preceding page in the same course. Reordering must preserve this ordering constraint.")
  pageId: uuid;

  @doc("The target page's QUESTION block, not a questionId or display index.")
  questionBlockId: uuid;

  @maxLength(200) label: string;
  ...Record<never>;
}
model SingleAnswerReferenceNode extends NodeBase {
  kind: "answer-reference";
  @maxLength(200) title: string;
  display: "single";
  @minItems(1) @maxItems(1) references: AnswerReference[];
  ...Record<never>;
}
model TableAnswerReferenceNode extends NodeBase {
  kind: "answer-reference";
  @maxLength(200) title: string;
  display: "table";
  @minItems(1) @maxItems(12) references: AnswerReference[];
  ...Record<never>;
}
@discriminated(#{ envelope: "none", discriminatorPropertyName: "display" })
union AnswerReferenceNode {
  single: SingleAnswerReferenceNode,
  table: TableAnswerReferenceNode,
}

@discriminated(#{ envelope: "none", discriminatorPropertyName: "kind" })
union ReadingChild {
  text: TextNode,
  image: ImageNode,
  simulation: SimulationNode,
}
@doc("Preserves child order and forbids nested groups or child layout. An image/text card needs at least one text and one image; CCM also supports text plus simulation. The per-page limit of 1,000 nodes includes children.")
model ReadingGroupNode extends NodeBase {
  kind: "reading-group";
  @minItems(2) @maxItems(999) children: ReadingChild[];
  ...Record<never>;
}

// Answer-reference uses a second discriminator (display) within its kind.
@doc("Identify nodes by kind; answer-reference additionally discriminates on display, preserving each branch's reference cardinality.")
union TemplateNode {
  text: TextNode,
  image: ImageNode,
  question: QuestionNode,
  simulation: SimulationNode,
  `answer-reference`: AnswerReferenceNode,
  `reading-group`: ReadingGroupNode,
}
model GridTextNode {
  ...TextNode;
  layout: GridLayout;
}
model GridImageNode {
  ...ImageNode;
  layout: GridLayout;
}
model GridQuestionNode {
  ...QuestionNode;
  layout: GridLayout;
}
model GridSimulationNode {
  ...SimulationNode;
  layout: GridLayout;
}
model GridSingleAnswerReferenceNode {
  ...SingleAnswerReferenceNode;
  layout: GridLayout;
}
model GridTableAnswerReferenceNode {
  ...TableAnswerReferenceNode;
  layout: GridLayout;
}
model GridReadingGroupNode {
  ...ReadingGroupNode;
  layout: GridLayout;
}
union GridNode {
  GridTextNode,
  GridImageNode,
  GridQuestionNode,
  GridSimulationNode,
  GridSingleAnswerReferenceNode,
  GridTableAnswerReferenceNode,
  GridReadingGroupNode,
}

model PagePresentationBase {
  version: 2;

  @doc("May be null for general material; other profiles retain the existing stage identifiers.")
  stage: Stage | null;

  mentalSet: 1 | 2 | null;
  notice: "ccm-linear-test" | null;

  @doc("Preserves legacy static-preview teaching semantics, distinct from side-effect-free editor preview. A preview=true page must not contain simulation nodes.")
  preview?: boolean;

  @maxLength(200) previewLabel?: string;
  chatEnabled: boolean;

  @doc("null inherits the course defaults. An object completely overrides greeting/suggestions; an empty suggestions array disables suggestions instead of falling back.")
  chatOverride: ChatOverride | null;

  @doc("Deduplicated TEXT resource IDs used only as context, not visible body content. Authorization and FK checks still apply.")
  @maxItems(100)
  contextTextIds: uuid[];
}
model SciArgPresentation extends PagePresentationBase {
  layout: "sciarg-split";

  @doc("The first two nodes are body text/image/simulation, followed by answer-reference/question. Template nodes reject layout dimensions. An empty DRAFT may temporarily have no nodes.")
  @maxItems(1000)
  nodes: TemplateNode[];

  ...Record<never>;
}
model CCMPresentation extends PagePresentationBase {
  layout: "ccm-stacked";

  @doc("The first node is a reading-group, followed by answer-reference/question. Template nodes reject layout dimensions. An empty DRAFT may temporarily have no nodes.")
  @maxItems(1000)
  nodes: TemplateNode[];

  ...Record<never>;
}
model FreeGridPresentation extends PagePresentationBase {
  layout: "free-grid";

  @doc("Every top-level node requires layout; children reject it. Array order is authoritative; do not persist x/y or pixel coordinates.")
  @maxItems(1000)
  nodes: GridNode[];

  ...Record<never>;
}
@discriminated(#{ envelope: "none", discriminatorPropertyName: "layout" })
union PagePresentation {
  `sciarg-split`: SciArgPresentation,
  `ccm-stacked`: CCMPresentation,
  `free-grid`: FreeGridPresentation,
}

model BlockInputBase {
  id: uuid;
  resourceId: uuid;
}
model TextBlockInput extends BlockInputBase {
  type: "TEXT";
  required: false;
  ...Record<never>;
}
model MediaBlockInput extends BlockInputBase {
  type: "MEDIA";
  required: false;
  ...Record<never>;
}
model QuestionBlockInput extends BlockInputBase {
  type: "QUESTION";
  required: boolean;
  ...Record<never>;
}
@discriminated(#{ envelope: "none", discriminatorPropertyName: "type" })
union BlockInput {
  TEXT: TextBlockInput,
  MEDIA: MediaBlockInput,
  QUESTION: QuestionBlockInput,
}
model PageInput {
  id: uuid;
  @minLength(1) @maxLength(200) title: string;

  @doc("Array order is the only displayOrder source. Every resource block has exactly one matching node on the same page; question-block order matches depth-first question-node order.")
  @maxItems(1000)
  blocks: BlockInput[];

  presentation: PagePresentation;
  ...Record<never>;
}
model DocumentInput {
  schemaVersion: 2;
  @minLength(1) @maxLength(100) code: string;
  @minLength(1) @maxLength(200) title: string;
  @maxLength(4000) description?: string;
  presentation: CoursePresentation;

  @doc("Omission preserves the selection; new courses start unselected. null explicitly clears it to UNSELECTED. Clients cannot declare LEGACY_UNCONFIRMED. First selection or a different non-null ID requires SciLLM verification.")
  presetId?: PresetId | null;

  @doc("Array order is the only page-order source. Empty DRAFT documents are valid. Omitting an old page/block removes its reference, not the resource.")
  @maxItems(500)
  pages: PageInput[];

  ...Record<never>;
}
@example(#{
  expectedRevision: 1,
  document: #{
    schemaVersion: 2,
    code: "example-general",
    title: "教材編輯範例：general",
    presentation: #{
      version: 2,
      profile: "general",
      navigation: "stepper",
      chatAppearance: null,
    },
    pages: #[],
  },
})
@example(#{
  expectedRevision: 1,
  document: #{
    schemaVersion: 2,
    code: "example-general",
    title: "教材編輯範例：general",
    presentation: #{
      version: 2,
      profile: "general",
      navigation: "stepper",
      chatAppearance: null,
    },
    pages: #[
      #{
        id: "00000000-0000-4000-8000-000000000010",
        title: "觀察與作答",
        blocks: #[
          #{
            id: "00000000-0000-4000-8000-000000000020",
            type: "TEXT",
            resourceId: "00000000-0000-4000-8000-000000000100",
            required: false,
          },
          #{
            id: "00000000-0000-4000-8000-000000000021",
            type: "MEDIA",
            resourceId: "00000000-0000-4000-8000-000000000101",
            required: false,
          },
          #{
            id: "00000000-0000-4000-8000-000000000022",
            type: "QUESTION",
            resourceId: "00000000-0000-4000-8000-000000000102",
            required: true,
          }
        ],
        presentation: #{
          version: 2,
          layout: "free-grid",
          stage: null,
          mentalSet: null,
          notice: null,
          chatEnabled: false,
          chatOverride: null,
          contextTextIds: #[],
          nodes: #[
            #{
              kind: "reading-group",
              id: "00000000-0000-4000-8000-000000000030",
              children: #[
                #{
                  kind: "text",
                  id: "00000000-0000-4000-8000-000000000031",
                  blockId: "00000000-0000-4000-8000-000000000020",
                  format: "markdown",
                },
                #{
                  kind: "image",
                  id: "00000000-0000-4000-8000-000000000032",
                  blockId: "00000000-0000-4000-8000-000000000021",
                  alt: "觀察圖",
                  caption: "教材圖說",
                }
              ],
              layout: #{ colSpan: 12, rowSpan: 1 },
            },
            #{
              kind: "question",
              id: "00000000-0000-4000-8000-000000000033",
              blockId: "00000000-0000-4000-8000-000000000022",
              label: "你的觀察",
              input: #{ kind: "text-choice", options: #["相同", "不相同"] },
              layout: #{ colSpan: 12, rowSpan: 2 },
            }
          ],
        },
      },
      #{
        id: "00000000-0000-4000-8000-000000000011",
        title: "回看先前回答",
        blocks: #[],
        presentation: #{
          version: 2,
          layout: "free-grid",
          stage: null,
          mentalSet: null,
          notice: null,
          chatEnabled: false,
          chatOverride: null,
          contextTextIds: #[],
          nodes: #[
            #{
              kind: "answer-reference",
              id: "00000000-0000-4000-8000-000000000034",
              title: "先前回答",
              display: "single",
              references: #[
                #{
                  pageId: "00000000-0000-4000-8000-000000000010",
                  questionBlockId: "00000000-0000-4000-8000-000000000022",
                  label: "觀察結果",
                }
              ],
              layout: #{ colSpan: 12, rowSpan: 1 },
            }
          ],
        },
      }
    ],
  },
})
@example(#{
  expectedRevision: 1,
  document: #{
    schemaVersion: 2,
    code: "example-sciarg",
    title: "教材編輯範例：sciarg",
    presentation: #{
      version: 2,
      profile: "sciarg",
      navigation: "stepper",
      chatAppearance: null,
    },
    pages: #[
      #{
        id: "00000000-0000-4000-8000-000000000040",
        title: "初始回答",
        blocks: #[
          #{
            id: "00000000-0000-4000-8000-000000000041",
            type: "TEXT",
            resourceId: "00000000-0000-4000-8000-000000000100",
            required: false,
          },
          #{
            id: "00000000-0000-4000-8000-000000000042",
            type: "MEDIA",
            resourceId: "00000000-0000-4000-8000-000000000101",
            required: false,
          },
          #{
            id: "00000000-0000-4000-8000-000000000043",
            type: "QUESTION",
            resourceId: "00000000-0000-4000-8000-000000000102",
            required: true,
          }
        ],
        presentation: #{
          version: 2,
          layout: "sciarg-split",
          stage: "initial",
          mentalSet: null,
          notice: null,
          chatEnabled: false,
          chatOverride: null,
          contextTextIds: #[],
          preview: true,
          previewLabel: "靜態示意圖",
          nodes: #[
            #{
              kind: "text",
              id: "00000000-0000-4000-8000-000000000044",
              blockId: "00000000-0000-4000-8000-000000000041",
              format: "markdown",
            },
            #{
              kind: "image",
              id: "00000000-0000-4000-8000-000000000045",
              blockId: "00000000-0000-4000-8000-000000000042",
              alt: "示意圖",
              caption: "",
            },
            #{
              kind: "question",
              id: "00000000-0000-4000-8000-000000000046",
              blockId: "00000000-0000-4000-8000-000000000043",
              label: "初始回答",
              input: #{ kind: "text" },
            }
          ],
        },
      }
    ],
  },
})
@example(#{
  expectedRevision: 1,
  document: #{
    schemaVersion: 2,
    code: "example-ccm",
    title: "教材編輯範例：ccm",
    presentation: #{
      version: 2,
      profile: "ccm",
      navigation: "stepper",
      chatAppearance: null,
    },
    pages: #[
      #{
        id: "00000000-0000-4000-8000-000000000050",
        title: "心臟觀察",
        blocks: #[
          #{
            id: "00000000-0000-4000-8000-000000000051",
            type: "TEXT",
            resourceId: "00000000-0000-4000-8000-000000000100",
            required: false,
          },
          #{
            id: "00000000-0000-4000-8000-000000000052",
            type: "QUESTION",
            resourceId: "00000000-0000-4000-8000-000000000102",
            required: true,
          }
        ],
        presentation: #{
          version: 2,
          layout: "ccm-stacked",
          stage: "ccm-observation",
          mentalSet: 1,
          notice: null,
          chatEnabled: false,
          chatOverride: null,
          contextTextIds: #[],
          nodes: #[
            #{
              kind: "reading-group",
              id: "00000000-0000-4000-8000-000000000053",
              children: #[
                #{
                  kind: "text",
                  id: "00000000-0000-4000-8000-000000000054",
                  blockId: "00000000-0000-4000-8000-000000000051",
                  format: "markdown",
                },
                #{
                  kind: "simulation",
                  id: "00000000-0000-4000-8000-000000000055",
                  simulationId: "ccm-heart-v1",
                }
              ],
            },
            #{
              kind: "question",
              id: "00000000-0000-4000-8000-000000000056",
              blockId: "00000000-0000-4000-8000-000000000052",
              label: "觀察結果",
              input: #{ kind: "text-choice", options: #["相同", "不相同"] },
            }
          ],
        },
      }
    ],
  },
})
model SaveDocumentRequest {
  expectedRevision: Revision;
  document: DocumentInput;
  ...Record<never>;
}
model CopyCourseRequest {
  expectedSourceRevision: Revision;
  @minLength(1) @maxLength(100) code: string;
  @minLength(1) @maxLength(200) title: string;
  ...Record<never>;
}
model EditorPage {
  id: uuid;
  title: string;
  displayOrder: int32;
  blocks: SciEdu.Pages.PageBlock[];
  presentation: PagePresentation;
  createdAt: utcDateTime;
  updatedAt: utcDateTime;
}
@doc("Controlled read URLs and metadata only. Excludes bytes, filesystem paths, permanent signed URLs and private uploader information.")
model MediaResource {
  id: uuid;
  type: "MEDIA";
  url: string;
  mimeType: string;
  @minValue(0) sizeBytes: int64;
  @minValue(1) width?: int32;
  @minValue(1) height?: int32;

  @doc("Optional lowercase hexadecimal SHA-256 digest; legacy resources may not have it backfilled yet.")
  @example("0000000000000000000000000000000000000000000000000000000000000000")
  @pattern("^[0-9a-f]{64}$")
  sha256?: string;
}
model MaterialImageResource extends MediaResource {
  mimeType: "image/jpeg" | "image/png" | "image/webp";
  @minValue(1) width: int32;
  @minValue(1) height: int32;
}
model Resources {
  texts: SciEdu.Content.TextContent[];
  questions: SciEdu.Questions.Question[];
  media: MediaResource[];
}
@example(#{
  schemaVersion: 2,
  code: "example-general",
  title: "教材編輯範例：general",
  presentation: #{
    version: 2,
    profile: "general",
    navigation: "stepper",
    chatAppearance: null,
  },
  pages: #[
    #{
      id: "00000000-0000-4000-8000-000000000010",
      title: "觀察與作答",
      blocks: #[
        #{
          id: "00000000-0000-4000-8000-000000000020",
          type: SciEdu.Pages.PageBlockType.TEXT,
          resourceId: "00000000-0000-4000-8000-000000000100",
          required: false,
          pageId: "00000000-0000-4000-8000-000000000010",
          displayOrder: 0,
          createdAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
          updatedAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
        },
        #{
          id: "00000000-0000-4000-8000-000000000021",
          type: SciEdu.Pages.PageBlockType.MEDIA,
          resourceId: "00000000-0000-4000-8000-000000000101",
          required: false,
          pageId: "00000000-0000-4000-8000-000000000010",
          displayOrder: 1,
          createdAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
          updatedAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
        },
        #{
          id: "00000000-0000-4000-8000-000000000022",
          type: SciEdu.Pages.PageBlockType.QUESTION,
          resourceId: "00000000-0000-4000-8000-000000000102",
          required: true,
          pageId: "00000000-0000-4000-8000-000000000010",
          displayOrder: 2,
          createdAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
          updatedAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
        }
      ],
      presentation: #{
        version: 2,
        layout: "free-grid",
        stage: null,
        mentalSet: null,
        notice: null,
        chatEnabled: false,
        chatOverride: null,
        contextTextIds: #[],
        nodes: #[
          #{
            kind: "reading-group",
            id: "00000000-0000-4000-8000-000000000030",
            children: #[
              #{
                kind: "text",
                id: "00000000-0000-4000-8000-000000000031",
                blockId: "00000000-0000-4000-8000-000000000020",
                format: "markdown",
              },
              #{
                kind: "image",
                id: "00000000-0000-4000-8000-000000000032",
                blockId: "00000000-0000-4000-8000-000000000021",
                alt: "觀察圖",
                caption: "教材圖說",
              }
            ],
            layout: #{ colSpan: 12, rowSpan: 1 },
          },
          #{
            kind: "question",
            id: "00000000-0000-4000-8000-000000000033",
            blockId: "00000000-0000-4000-8000-000000000022",
            label: "你的觀察",
            input: #{ kind: "text-choice", options: #["相同", "不相同"] },
            layout: #{ colSpan: 12, rowSpan: 2 },
          }
        ],
      },
      displayOrder: 0,
      createdAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
      updatedAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
    },
    #{
      id: "00000000-0000-4000-8000-000000000011",
      title: "回看先前回答",
      blocks: #[],
      presentation: #{
        version: 2,
        layout: "free-grid",
        stage: null,
        mentalSet: null,
        notice: null,
        chatEnabled: false,
        chatOverride: null,
        contextTextIds: #[],
        nodes: #[
          #{
            kind: "answer-reference",
            id: "00000000-0000-4000-8000-000000000034",
            title: "先前回答",
            display: "single",
            references: #[
              #{
                pageId: "00000000-0000-4000-8000-000000000010",
                questionBlockId: "00000000-0000-4000-8000-000000000022",
                label: "觀察結果",
              }
            ],
            layout: #{ colSpan: 12, rowSpan: 1 },
          }
        ],
      },
      displayOrder: 1,
      createdAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
      updatedAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
    }
  ],
  id: "00000000-0000-4000-8000-000000000001",
  revision: 1,
  status: SciEdu.Courses.CourseStatus.DRAFT,
  preset: #{ selection: "UNSELECTED", presetId: null, availability: null },
  editable: true,
  editBlockedReason: null,
  createdAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
  updatedAt: utcDateTime.fromISO("2026-11-15T00:00:00Z"),
  resources: #{
    texts: #[
      #{
        id: "00000000-0000-4000-8000-000000000100",
        type: "TEXT",
        content: "觀察正文",
      }
    ],
    questions: #[
      #{
        id: "00000000-0000-4000-8000-000000000102",
        type: SciEdu.Questions.QuestionType.TEXT,
        content: "請描述觀察結果",
      }
    ],
    media: #[
      #{
        id: "00000000-0000-4000-8000-000000000101",
        type: "MEDIA",
        url: "/api/content/media/00000000-0000-4000-8000-000000000101",
        mimeType: "image/png",
        sizeBytes: 1024,
        width: 800,
        height: 600,
        sha256: "0000000000000000000000000000000000000000000000000000000000000000",
      }
    ],
  },
})
model EditorDocument {
  schemaVersion: 2;
  id: uuid;
  revision: Revision;
  code: string;
  title: string;
  description?: string;
  status: SciEdu.Courses.CourseStatus;
  presentation: CoursePresentation;
  preset: PresetState;
  pages: EditorPage[];
  resources: Resources;
  editable: boolean;

  @doc("null when editable. Unknown history must not be treated as proof of no prior use.")
  editBlockedReason: "FORMALLY_USED" | "LEGACY_USAGE_UNCONFIRMED" | null;

  warnings?: Warning[];
  createdAt: utcDateTime;
  updatedAt: utcDateTime;
}
model PresetCatalogItem {
  id: PresetId;
  description: string;
}
model PresetCatalog {
  items: PresetCatalogItem[];
}

@tag("Courses")
@route("/courses/{id}")
@useAuth(SciEdu.Auth.SessionCookieAuth)
interface Editor {
  @doc("Get a complete course editor snapshot.\n\nPermissions: ADMIN or EXPERIMENTER with shared management access; no teacher-owner model is introduced.\nResponse: 200 EditorDocument from one consistent snapshot of pages, blocks, presentation and deduplicated resources. Excludes correct answers, student submissions, Chat data, file bytes and storage paths.\nLegacy: retain Page/Block IDs and derive stable node UUIDs for a read-only v2 projection. GET does not migrate the DB or switch student rendering. Lossless conversion failures return 422.\nLimits/errors: hydrated resource text is limited to 20 MiB; return 413 without truncation. Other errors: 400, 401/403, 404 course, 422 invalid legacy data, 500.")
  @get
  @route("/editor")
  read(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: EditorDocument;
      }
    | ReadErrors
    | TooLarge
    | InvalidDocument;

  @doc("Atomically save a complete course document.\n\nPermissions: ADMIN or EXPERIMENTER. Check durable usage evidence rather than only the current experiment status.\nRequest: required Idempotency-Key and expectedRevision. Replace metadata, pages, blocks, ordering and presentation together. Arrays define order. Reject read-only fields, incomplete nodes and fake resource IDs. Limits: 5 MiB JSON, 500 pages, and per page 1,000 blocks, 1,000 total nodes including children, 100 contextTextIds.\nResponse: 200 EditorDocument with revision advanced once. A published course may be edited in place only while every referencing experiment has never started; enforce publication completeness and retain PUBLISHED. Formally used or history-unconfirmed courses return 409 and must be copied.\nTransaction: authorize, replay successful keys, lock/check revision, validate references/resources/whitelists/preset, then commit document and successful result together. Roll back all writes on failure. Reject duplicate UUIDs, cross-course/page ID reuse and reuse after deletion. Removing/reordering referenced pages or questions must fix references in the same snapshot; targets must be preceding-page QUESTION blocks.\nPreset: omission preserves the selection. First or changed selections require catalog validation. An unchanged removed or unverifiable selection may be saved with warnings; missing new choices return 422, unavailable verification 503, with no document writes.\nErrors: 400, 401/403/404, 409 revision/editability/key conflict, 413, 422 document/reference/template, 503 catalog, 500. Identify business failures by type. Successful-key replay returns the original 200 even after revision/state changes.")
  @put
  @route("/editor")
  save(@path id: uuid, ...IdempotencyHeader, @body body: SaveDocumentRequest): {
    @statusCode statusCode: 200;
    @body body: EditorDocument;
  } | WriteErrors;

  @doc("Copy a course into an independent draft.\n\nPermissions: ADMIN or EXPERIMENTER; protected source courses may still be copied.\nRequest: Idempotency-Key, expectedSourceRevision, an unused code and title. Read and copy from a consistent snapshot; a stale source revision returns 409.\nResponse: 201 EditorDocument for a new unlocked DRAFT at revision=1. Preserve preset, captions, profile and appearance. Generate new Page/Block/node/Question/option UUIDs and remap answer references. Immutable TEXT/MEDIA may be shared; edits use copy-on-write.\nIsolation: never copy student answers, progress, experiment associations or chats. Correct answers are outside this copy scope; return CORRECT_ANSWER_NOT_COPIED when relevant. Preserve LEGACY_UNCONFIRMED instead of inventing a preset.\nLegacy: convert only validated SciArg/CCM/general fixtures. Missing resources or lossy conversion return 422 without changing the source. Copying does not replace experiment associations.\nErrors: 400, 401/403/404, 409 revision/code/key conflict, 413 hydration limit, 422 conversion/reference, 500. Key replay returns the original copy without recreating resources.")
  @post
  @route("/copies")
  copy(@path id: uuid, ...IdempotencyHeader, @body body: CopyCourseRequest):
    | {
        @statusCode statusCode: 201;
        @body body: EditorDocument;
      }
    | ReadErrors
    | ConflictError
    | TooLarge
    | InvalidDocument;
}

@tag("Chat")
@route("/chat/presets")
@useAuth(SciEdu.Auth.SessionCookieAuth)
interface Presets {
  @doc("List all presets available for course selection.\n\nPermissions: ADMIN or EXPERIMENTER.\nResponse: 200 {items:[{id,description}]} containing all built-in and custom presets from the same SciLLM environment, without profile filtering or internal prompts/credentials.\nUpstream: Backend reads the catalog used by actual course-chat execution, preferably existing GET /admin/presets. This defines the public SciEdu adapter shape; upstream authorization and field mapping still require integration.\nErrors: 401/403, 503 PRESET_CATALOG_UNAVAILABLE (never turn a failure into an empty catalog), 500. Listing never changes a course selection.")
  @get
  list():
    | {
        @statusCode statusCode: 200;
        @body body: PresetCatalog;
      }
    | Unauthenticated
    | Denied
    | CatalogUnavailable
    | InternalError;
}
