import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.PageVisits;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/**
 * Whether a page visit is still open or has a recorded leave time.
 */
enum PageVisitStatus {
  OPEN: "OPEN",
  CLOSED: "CLOSED",
}

/**
 * A period during which a student visited a course page.
 */
model PageVisit {
  @doc("Page visit ID")
  id: uuid;

  @doc("Authenticated student ID")
  studentId: uuid;

  @doc("Course ID")
  courseId: uuid;

  @doc("Course page ID")
  pageId: uuid;

  @doc("Client-generated ID that identifies one browser tab's course navigation flow")
  clientSessionId: uuid;

  @doc("Server timestamp recorded when the student entered the page")
  enteredAt: utcDateTime;

  @doc("Server timestamp recorded when the student left the page; omitted while the visit is open")
  leftAt?: utcDateTime;
}

/**
 * Request body for recording entry into a course page.
 */
model CreatePageVisitRequest {
  @doc("Course ID")
  courseId: uuid;

  @doc("Course page ID")
  pageId: uuid;

  @doc("Client-generated ID that remains stable for one browser tab's course navigation flow")
  clientSessionId: uuid;
}

/**
 * Paginated page visit records.
 */
model PaginatedPageVisitResponse {
  items: PageVisit[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Page Visits")
@route("/page-visits")
interface PageVisits {
  @doc("""
    Record that the authenticated student entered a course page. The server
    records `enteredAt`; clients cannot provide timestamps.
    
    Before creating the visit, the server closes any open visit belonging to
    the same student and `clientSessionId`, using the new visit's `enteredAt`
    as the old visit's `leftAt`. The close and create operations are atomic.
    
    `Idempotency-Key` is scoped to the authenticated student. Replaying the
    same key with the same request returns the originally created visit and
    must not close or create another visit. Reusing it with a different request
    returns a conflict.
    """)
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  enter(
    @doc("Client-generated UUID used to make retries safe")
    @header("Idempotency-Key")
    idempotencyKey: uuid,

    @body body: CreatePageVisitRequest,
  ):
    | {
        @statusCode statusCode: 201;
        @body body: PageVisit;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 404;
        @body error: SciEdu.NotFound;
      }
    | {
        @statusCode statusCode: 409;
        @body error: SciEdu.Conflict;
      }
    | ProblemDetail;

  @doc("""
    Record that the authenticated student left one of their page visits. The
    server records `leftAt`; clients cannot provide timestamps. This operation
    is idempotent: if the visit was already closed explicitly or by a later
    enter request, its original `leftAt` is preserved and returned.
    """)
  @post
  @route("/{id}/leave")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  leave(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: PageVisit;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 404;
        @body error: SciEdu.NotFound;
      }
    | ProblemDetail;

  @doc("""
    List page visit records for research and administration. Only users with
    the EXPERIMENTER or ADMIN role may call this operation. Results are ordered
    by `enteredAt` descending.
    """)
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  list(
    @query studentId?: uuid,
    @query courseId?: uuid,
    @query pageId?: uuid,
    @query clientSessionId?: uuid,
    @query status?: PageVisitStatus,

    @doc("Include visits entered at or after this timestamp")
    @query
    enteredFrom?: utcDateTime,

    @doc("Include visits entered before this timestamp")
    @query
    enteredBefore?: utcDateTime,

    @query
    @minValue(1)
    page?: int32 = 1,

    @doc("Number of items per page. Maximum value is 100.")
    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedPageVisitResponse;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | ProblemDetail;
}
