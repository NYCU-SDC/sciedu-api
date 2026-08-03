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
}

model CourseNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: NotFound;
}

model CourseConflictResponse {
  @statusCode statusCode: 409;
  @body error: Conflict;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Courses")
@route("/courses")
interface Courses {
  @doc("List courses. Requires EXPERIMENTER or ADMIN.")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
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
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | ProblemDetail;

  @doc("Create a DRAFT course. Requires EXPERIMENTER or ADMIN. Course codes must be unique.")
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  create(@body body: CreateCourseRequest):
    | {
        @statusCode statusCode: 201;
        @body body: Course;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | CourseConflictResponse
    | ProblemDetail;

  @doc("Get a course. Students may only access a PUBLISHED course assigned to their current experiment.")
  @get
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  get(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: Course;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | CourseNotFoundResponse
    | ProblemDetail;

  @doc("Fully update course metadata. Requires EXPERIMENTER or ADMIN. Changes are immediately visible to assigned experiments.")
  @put
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  update(@path id: uuid, @body body: UpdateCourseRequest):
    | {
        @statusCode statusCode: 200;
        @body body: Course;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | CourseNotFoundResponse
    | CourseConflictResponse
    | ProblemDetail;

  @doc("Update a course lifecycle status. Requires EXPERIMENTER or ADMIN.")
  @put
  @route("/{id}/status")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  updateStatus(@path id: uuid, @body body: UpdateCourseStatusRequest):
    | {
        @statusCode statusCode: 200;
        @body body: Course;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | CourseNotFoundResponse
    | CourseConflictResponse
    | ProblemDetail;
}
