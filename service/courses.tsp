import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Courses;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

enum CourseStatus {
  DRAFT: "DRAFT",
  PUBLISHED: "PUBLISHED",
  ARCHIVED: "ARCHIVED",
}

model Course {
  id: uuid;

  @minLength(1)
  @maxLength(100)
  code: string;

  @minLength(1)
  @maxLength(200)
  title: string;

  @maxLength(4000)
  description?: string;

  @doc("The single Course document revision. Legacy responses may omit it. New courses and migrated legacy rows start at 1; successful document mutations advance the revision.")
  revision?: SciEdu.Materials.Revision;

  @doc("Present only after the course has actually been persisted as v2. Omit for legacy data; reading the editor projection must not migrate it.")
  presentation?: SciEdu.Materials.CoursePresentation;

  @doc("Returned only to ADMIN or EXPERIMENTER, including the persisted selection and current availability. Students cannot choose a course-chat preset through a request.")
  preset?: SciEdu.Materials.PresetState;

  status: CourseStatus;
  createdAt: utcDateTime;
  updatedAt: utcDateTime;
}

model PaginatedCoursesResponse {
  items: Course[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

model CreateCourseRequest {
  @minLength(1)
  @maxLength(100)
  code: string;

  @minLength(1)
  @maxLength(200)
  title: string;

  @maxLength(4000)
  description?: string;
}

/** Fully replaces a course's editable metadata. */
model UpdateCourseRequest {
  @minLength(1)
  @maxLength(100)
  code: string;

  @minLength(1)
  @maxLength(200)
  title: string;

  @maxLength(4000)
  description?: string;
}

model UpdateCourseStatusRequest {
  status: CourseStatus;

  @doc("Required for v2 status writes; optional for legacy requests. A stale revision returns 409.")
  expectedRevision?: SciEdu.Materials.Revision;
}

model CourseNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: NotFound;
}

model CourseConflictResponse {
  @statusCode statusCode: 409;
  @body error: Conflict;
}

model CourseWriteResult extends Course {
  revision: SciEdu.Materials.Revision;
  warnings?: SciEdu.Materials.Warning[];
}

@tag("Courses")
@route("/courses")
@useAuth(SciEdu.Auth.SessionCookieAuth)
interface Courses {
  @doc("List courses for management.\n\nRequires ADMIN or EXPERIMENTER. Returns 200 with standard pagination. Migrated courses expose revision; only persisted v2 courses expose presentation. Preset information is management-only. Errors: 400 invalid pagination or filters, 401/403, 500; application/problem+json.")
  @get
  list(
    @query @minValue(1) page?: int32 = 1,

    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,

    @query status?: CourseStatus,

    @query
    @minLength(1)
    @maxLength(200)
    search?: string,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedCoursesResponse;
      }
    | SciEdu.Materials.BadRequest
    | SciEdu.Materials.Unauthenticated
    | SciEdu.Materials.Denied
    | SciEdu.Materials.InternalError;

  @doc("Create a course draft.\n\nPermissions: ADMIN or EXPERIMENTER.\nRequest: required Idempotency-Key and a unique, user-supplied code; do not derive it from the title. Use editor PUT to save the complete v2 document or preset selection.\nResponse: 201 CourseWriteResult with DRAFT status and revision=1. Same-key, same-payload retries return the original resource and 201; retain successful results for at least 24 hours.\nErrors: 400, 401/403, 409 code or key conflict/in-flight request, 500. Authorization and replay ordering follow Materials.IdempotencyHeader.")
  @post
  create(
    ...SciEdu.Materials.IdempotencyHeader,
    @body body: CreateCourseRequest,
  ):
    | {
        @statusCode statusCode: 201;
        @body body: CourseWriteResult;
      }
    | SciEdu.Materials.BadRequest
    | SciEdu.Materials.Unauthenticated
    | SciEdu.Materials.Denied
    | SciEdu.Materials.ConflictError
    | SciEdu.Materials.InternalError;

  @doc("Get a course and its v2 presentation.\n\nPermissions: management roles may read any course status, including original courses and presets referenced by completed or archived experiments. Students still need a PUBLISHED course assigned to their current valid experiment; this does not grant historical material access.\nResponse: 200 Course. Return presentation only for persisted v2; omit it for legacy data. Return preset only to management roles. Existing access rules and query parameters are preserved.\nErrors: 400 invalid UUID, 401/403/404, 500. GET never migrates or writes data.")
  @get
  @route("/{id}")
  get(@path id: uuid): {
    @statusCode statusCode: 200;
    @body body: Course;
  } | SciEdu.Materials.ReadErrors;

  @doc("Update legacy course metadata.\n\nRequires ADMIN or EXPERIMENTER and an editable legacy course. Persisted v2 returns 409 EDITOR_DOCUMENT_REQUIRED and must use editor PUT. Formally used courses or unconfirmed usage history return 409 COURSE_NOT_EDITABLE. Coordinate locks with experiment activation. Returns 200 CourseWriteResult with revision+1. Errors: 400/401/403/404/409/500.")
  @put
  @route("/{id}")
  update(@path id: uuid, @body body: UpdateCourseRequest): {
    @statusCode statusCode: 200;
    @body body: CourseWriteResult;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("Validate and update course publication status.\n\nPermissions: ADMIN or EXPERIMENTER. This endpoint is an explicit exception to the v2 legacy-mutation restriction. Preserve existing status rules; returning to DRAFT never removes the permanent content/preset lock.\nRequest: v2 requires Idempotency-Key and expectedRevision; legacy retains its existing body and optional header. Status remains DRAFT, PUBLISHED or ARCHIVED.\nPublication: under the same Course lock and transaction, require at least one page, visible content on each page, complete nodes/questions/references, accessible resources and supported profiles/simulations. TEXT questions may lack correct answers; that does not establish automatic grading readiness.\nPreset: any chatEnabled=true page requires a SELECTED preset; all-chat-disabled courses may publish without one. Removed or temporarily unverifiable selected presets produce warnings, preserving their identifiers and allowing publication and later experiment activation.\nResponse: 200 CourseWriteResult with revision+1; do not create experiments or assign students. Authorize before successful-key replay, even if the revision is now stale.\nErrors: 400 missing conditional fields or malformed input, 401/403/404, 409 revision/protection/key conflict, 422 incomplete document or missing preset for chat pages, 500.")
  @put
  @route("/{id}/status")
  updateStatus(
    @path id: uuid,
    @header("Idempotency-Key") key?: uuid,
    @body body: UpdateCourseStatusRequest,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: CourseWriteResult;
      }
    | SciEdu.Materials.ReadErrors
    | SciEdu.Materials.ConflictError
    | SciEdu.Materials.InvalidDocument;
}
