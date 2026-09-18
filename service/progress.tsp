import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Progress;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

@doc("The student's progress state for a course in one experiment.")
enum CourseProgressStatus {
  @doc("The student has not reached any current page in the course.")
  NOT_STARTED: "NOT_STARTED",

  @doc("The student has reached the course but has not completed every current page.")
  IN_PROGRESS: "IN_PROGRESS",

  @doc("The student has completed every current page in the non-empty course.")
  COMPLETED: "COMPLETED",
}

@doc("A compact reference to a page's current position in its course.")
model ProgressPageReference {
  pageId: uuid;

  @doc("Current one-based position after ordering course pages by displayOrder.")
  @minValue(1)
  pageNumber: int32;

  title: string;
}

@doc("The student's progress state for one current course page.")
model PageProgress {
  pageId: uuid;

  @doc("Current one-based position after ordering course pages by displayOrder.")
  @minValue(1)
  pageNumber: int32;

  title: string;

  @doc("Whether the student explicitly marked this page as reached. Completion always implies reached.")
  reached: boolean;

  @doc("Server timestamp when this page was first marked as reached.")
  reachedAt?: utcDateTime;

  @doc("Whether the student explicitly marked this page as completed.")
  completed: boolean;

  @doc("Server timestamp when this page was first marked as completed.")
  completedAt?: utcDateTime;
}

@doc("""
  Summary of one student's progress through one course in one experiment.
  Counts, percentage, status, and highestReachedPage are calculated from the
  course's current pages. Deleted pages are excluded; adding or reordering pages
  may therefore change the derived summary without changing stored progress.
  """)
model CourseProgressSummary {
  studentId: uuid;
  experimentId: uuid;
  courseId: uuid;
  status: CourseProgressStatus;

  @doc("Reached current page with the greatest displayOrder; omitted when no current page has been reached.")
  highestReachedPage?: ProgressPageReference;

  @minValue(0)
  reachedPageCount: int32;

  @minValue(0)
  completedPageCount: int32;

  @minValue(0)
  totalPageCount: int32;

  @doc("Floor of completedPageCount * 100 / totalPageCount, or zero for an empty course.")
  @minValue(0)
  @maxValue(100)
  completionPercentage: int32;
}

@doc("Course progress with every current page listed in display order.")
model CourseProgressDetail extends CourseProgressSummary {
  pages: PageProgress[];
}

@doc("Management view of a participant's course progress.")
model StudentCourseProgress {
  student: SciEdu.Users.User;

  @doc("Timestamp when the student was assigned to the experiment.")
  assignedAt: utcDateTime;

  progress: CourseProgressSummary;
}

@doc("Paginated participant progress for one course in one experiment.")
model PaginatedStudentCourseProgressResponse {
  items: StudentCourseProgress[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

model ProgressNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: SciEdu.NotFound;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Progress")
@route("/progress")
interface Progress {
  @doc("""
    Return the authenticated student's progress for one course in their current
    ACTIVE experiment. The course must be PUBLISHED and assigned to that
    experiment. Pages are returned in current displayOrder. Returns 404 when no
    current experiment or course exists, and 403 when the course is not published
    or assigned to the current experiment.
    """)
  @get
  @route("/me")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  me(@query courseId: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: CourseProgressDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | ProgressNotFoundResponse
    | ProblemDetail;

  @doc("""
    Idempotently mark one page as reached by the authenticated student in their
    current ACTIVE experiment. The page determines the course. Only the target
    page is marked; earlier pages are not changed. Replays preserve the original
    reachedAt timestamp and return the current complete course progress. Returns
    404 when no current experiment or page exists, and 403 when the page is not
    accessible through an assigned, published course.
    """)
  @put
  @route("/me/pages/{pageId}/reach")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  reachPage(@path pageId: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: CourseProgressDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | ProgressNotFoundResponse
    | ProblemDetail;

  @doc("""
    Idempotently and irreversibly mark one page as completed by the authenticated
    student in their current ACTIVE experiment. The page determines the course.
    If the page has not been reached, it is marked reached at the same server
    timestamp. This operation does not validate page blocks or answers. Replays
    preserve the original timestamps and return the current complete course
    progress. Returns 404 when no current experiment or page exists, and 403 when
    the page is not accessible through an assigned, published course.
    """)
  @put
  @route("/me/pages/{pageId}/completion")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  completePage(@path pageId: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: CourseProgressDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | ProgressNotFoundResponse
    | ProblemDetail;

  @doc("""
    List every participant's progress for one course assigned to an experiment.
    Requires EXPERIMENTER or ADMIN. Participants without progress are included.
    Results are ordered by participant assignment time, then student ID. Returns
    404 when the experiment or course does not exist, or the course is not
    assigned to the experiment.
    """)
  @get
  @route("/students")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listStudents(
    @query experimentId: uuid,
    @query courseId: uuid,

    @query
    @minValue(1)
    page?: int32 = 1,

    @doc("Number of participants per page. Maximum value is 100.")
    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedStudentCourseProgressResponse;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | ProgressNotFoundResponse
    | ProblemDetail;

  @doc("""
    Return one participant's page-level progress for one course assigned to an
    experiment. Requires EXPERIMENTER or ADMIN. Returns 404 when the experiment,
    course, or student does not exist, when the course is not assigned to the
    experiment, or when the student is not a participant in the experiment.
    """)
  @get
  @route("/students/{studentId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  student(
    @path studentId: uuid,
    @query experimentId: uuid,
    @query courseId: uuid,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: CourseProgressDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | ProgressNotFoundResponse
    | ProblemDetail;
}
