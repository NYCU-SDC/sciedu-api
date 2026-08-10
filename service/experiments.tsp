import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Experiments;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

enum ExperimentStatus {
  DRAFT: "DRAFT",
  SCHEDULED: "SCHEDULED",
  ACTIVE: "ACTIVE",
  COMPLETED: "COMPLETED",
  ARCHIVED: "ARCHIVED",
}

@doc("How answers in the experiment are graded.")
enum GradingMode {
  @doc("Grade supported answers automatically using deterministic rules.")
  AUTOMATIC: "AUTOMATIC",

  @doc("Require an experimenter to grade submitted answers.")
  MANUAL: "MANUAL",
}

@doc("When students may see correct answers.")
enum CorrectAnswerReleaseMode {
  @doc("Release correct answers after the containing page is submitted.")
  AFTER_PAGE_SUBMISSION: "AFTER_PAGE_SUBMISSION",

  @doc("Release correct answers after the entire course is completed.")
  AFTER_COURSE_COMPLETION: "AFTER_COURSE_COMPLETION",

  @doc("Never release correct answers to students.")
  NEVER: "NEVER",
}

@doc("Experiment-specific retry, grading, score, explanation, and correct-answer release settings. Every field is required.")
model ExperimentConfiguration {
  @doc("Maximum total attempts. Must be 1 when allowRetry is false and at least 2 when allowRetry is true.")
  @minValue(1)
  maxAttempts: int32;

  @doc("Whether a participant may start another attempt.")
  allowRetry: boolean;

  @doc("Whether scores are visible to participants. Independent of correctAnswerReleaseMode.")
  showScore: boolean;

  @doc("Whether grading explanations are visible to participants. Independent of correctAnswerReleaseMode.")
  showExplanations: boolean;

  @doc("How submitted answers are graded.")
  gradingMode: GradingMode;

  @doc("Controls when correct answers are released. This does not control score or explanation visibility.")
  correctAnswerReleaseMode: CorrectAnswerReleaseMode;
}

model Experiment {
  id: uuid;

  @minLength(1)
  @maxLength(200)
  name: string;

  @maxLength(4000)
  description?: string;

  scheduledStartAt: utcDateTime;
  scheduledEndAt: utcDateTime;
  status: ExperimentStatus;
  configuration: ExperimentConfiguration;
  createdBy: uuid;
  createdAt: utcDateTime;
  updatedAt: utcDateTime;
}

model ExperimentDetail extends Experiment {
  participantCount: int32;
  courseCount: int32;
}

model PaginatedExperimentsResponse {
  items: Experiment[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

model ExperimentParticipantAssignment {
  participant: SciEdu.Users.User;
  assignedAt: utcDateTime;
}

model ExperimentCourseAssignment {
  course: SciEdu.Courses.Course;
  linkedAt: utcDateTime;
}

model PaginatedExperimentParticipantsResponse {
  items: ExperimentParticipantAssignment[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

model PaginatedExperimentCoursesResponse {
  items: ExperimentCourseAssignment[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

model CreateExperimentRequest {
  @minLength(1)
  @maxLength(200)
  name: string;

  @maxLength(4000)
  description?: string;

  @doc("Must be earlier than scheduledEndAt.")
  scheduledStartAt: utcDateTime;

  scheduledEndAt: utcDateTime;
  configuration: ExperimentConfiguration;
}

/** Fully replaces an experiment's editable metadata, schedule, and configuration. */
model UpdateExperimentRequest {
  @minLength(1)
  @maxLength(200)
  name: string;

  @maxLength(4000)
  description?: string;

  @doc("Must be earlier than scheduledEndAt.")
  scheduledStartAt: utcDateTime;

  scheduledEndAt: utcDateTime;
  configuration: ExperimentConfiguration;
}

model UpdateExperimentStatusRequest {
  status: ExperimentStatus;
}

model AddExperimentParticipantsRequest {
  @minItems(1)
  @maxItems(100)
  userIds: uuid[];
}

model AddExperimentCoursesRequest {
  @minItems(1)
  @maxItems(100)
  courseIds: uuid[];
}

model CurrentExperimentResponse {
  experiment: Experiment;
  courses: SciEdu.Courses.Course[];
}

model ExperimentNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: NotFound;
}

model ExperimentConflictResponse {
  @statusCode statusCode: 409;
  @body error: Conflict;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Experiments")
@route("/experiments")
interface Experiments {
  @doc("List experiments. Requires EXPERIMENTER or ADMIN.")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  list(
    @query @minValue(1) page?: int32 = 1,

    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,

    @query status?: ExperimentStatus,

    @doc("Only include experiments ending at or after this timestamp.")
    @query
    scheduledFrom?: utcDateTime,

    @doc("Only include experiments starting at or before this timestamp.")
    @query
    scheduledTo?: utcDateTime,

    @query
    @minLength(1)
    @maxLength(200)
    search?: string,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedExperimentsResponse;
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

  @doc("Create a DRAFT experiment. Requires EXPERIMENTER or ADMIN.")
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  create(@body body: CreateExperimentRequest):
    | {
        @statusCode statusCode: 201;
        @body body: ExperimentDetail;
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

  @doc("Return the authenticated student's ACTIVE experiment whose schedule contains the current time, together with its PUBLISHED courses.")
  @get
  @route("/current")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  current():
    | {
        @statusCode statusCode: 200;
        @body body: CurrentExperimentResponse;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | ExperimentNotFoundResponse
    | ProblemDetail;

  @doc("Get an experiment summary. Requires EXPERIMENTER or ADMIN.")
  @get
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  get(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: ExperimentDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | ExperimentNotFoundResponse
    | ProblemDetail;

  @doc("Fully update experiment metadata, schedule, and configuration without changing its status. Requires EXPERIMENTER or ADMIN.")
  @put
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  update(@path id: uuid, @body body: UpdateExperimentRequest):
    | {
        @statusCode statusCode: 200;
        @body body: ExperimentDetail;
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
    | ExperimentNotFoundResponse
    | ExperimentConflictResponse
    | ProblemDetail;

  @doc("Update an experiment lifecycle status. Requires EXPERIMENTER or ADMIN.")
  @put
  @route("/{id}/status")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  updateStatus(@path id: uuid, @body body: UpdateExperimentStatusRequest):
    | {
        @statusCode statusCode: 200;
        @body body: ExperimentDetail;
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
    | ExperimentNotFoundResponse
    | ExperimentConflictResponse
    | ProblemDetail;

  @doc("List experiment participants. Requires EXPERIMENTER or ADMIN.")
  @get
  @route("/{id}/participants")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listParticipants(
    @path id: uuid,
    @query @minValue(1) page?: int32 = 1,

    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedExperimentParticipantsResponse;
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
    | ExperimentNotFoundResponse
    | ProblemDetail;

  @doc("Add participants. The batch is atomic and fails with 409 without creating any assignments if a participant has an overlapping experiment or any assignment conflicts. Requires EXPERIMENTER or ADMIN.")
  @post
  @route("/{id}/participants")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  addParticipants(
    @path id: uuid,
    @body body: AddExperimentParticipantsRequest,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: ExperimentParticipantAssignment[];
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
    | ExperimentNotFoundResponse
    | ExperimentConflictResponse
    | ProblemDetail;

  @doc("Remove a participant from an experiment. Requires EXPERIMENTER or ADMIN.")
  @delete
  @route("/{id}/participants/{userId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  removeParticipant(@path id: uuid, @path userId: uuid):
    | {
        @statusCode statusCode: 204;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | ExperimentNotFoundResponse
    | ProblemDetail;

  @doc("List courses assigned to an experiment. Students may only access their current experiment; management roles may access any experiment.")
  @get
  @route("/{id}/courses")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listCourses(
    @path id: uuid,
    @query @minValue(1) page?: int32 = 1,

    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedExperimentCoursesResponse;
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
    | ExperimentNotFoundResponse
    | ProblemDetail;

  @doc("Assign courses to an experiment. The batch is atomic and fails with 409 without creating any assignments if any assignment conflicts. Requires EXPERIMENTER or ADMIN.")
  @post
  @route("/{id}/courses")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  addCourses(@path id: uuid, @body body: AddExperimentCoursesRequest):
    | {
        @statusCode statusCode: 200;
        @body body: ExperimentCourseAssignment[];
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
    | ExperimentNotFoundResponse
    | ExperimentConflictResponse
    | ProblemDetail;

  @doc("Remove a course assignment from an experiment. Requires EXPERIMENTER or ADMIN.")
  @delete
  @route("/{id}/courses/{courseId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  removeCourse(@path id: uuid, @path courseId: uuid):
    | {
        @statusCode statusCode: 204;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | ExperimentNotFoundResponse
    | ProblemDetail;
}
