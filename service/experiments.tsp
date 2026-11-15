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

model ManagementCourse extends SciEdu.Courses.Course {
  @doc("Persisted preset selection. Unreliable history is LEGACY_UNCONFIRMED. Preserve it after completion or archival; never backfill from current frontend defaults.")
  preset: SciEdu.Materials.PresetState;
}

model ExperimentCourseAssignment {
  course: SciEdu.Courses.Course;
  linkedAt: utcDateTime;
}

model ManagementExperimentCourseAssignment extends ExperimentCourseAssignment {
  course: ManagementCourse;
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

  @doc("Update experiment status and freeze course usage.\n\nRequires ADMIN or EXPERIMENTER. On the first transition to ACTIVE, persist irreversible activation evidence and permanently freeze the referenced course content and preset in the same transaction, before any student visit. Completion, archival or status rollback never unlocks them. Coordinate activation, document writes and replacement using experiment locks followed by Course locks in ID order. Preset removal or catalog downtime must not block activation or trigger fallback. Existing schedule checks, request body and 200 ExperimentDetail remain unchanged; internal lock timestamps are not public.")
  @put
  @route("/{id}/status")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  updateStatus(@path id: uuid, @body body: UpdateExperimentStatusRequest): {
    @statusCode statusCode: 200;
    @body body: ExperimentDetail;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

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

  @doc("List experiment courses and historical preset selections.\n\nReturns 200 with standard pagination. Preserve the existing student restriction to the current experiment and omit course.preset for students. ADMIN or EXPERIMENTER may query all states, including COMPLETED and ARCHIVED; management responses must include the original course.preset selection and availability such as UNKNOWN or REMOVED. Missing reliable history is LEGACY_UNCONFIRMED, never a current frontend default. Read original associations without granting students broader historical material access.")
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
  ): {
    @statusCode statusCode: 200;
    @body body: PaginatedExperimentCoursesResponse;
  } | SciEdu.Materials.ReadErrors;

  @doc("Assign courses to an experiment.\n\nRequires ADMIN or EXPERIMENTER. Preserve batch atomicity and the 200 assignment-array response. Permanently reject additions after the first ACTIVE transition, including subsequent completion, archival or status rollback. Protect unconfirmed legacy activation history conservatively. Share activation locks; any association conflict returns 409 and rolls back the entire batch.")
  @post
  @route("/{id}/courses")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  addCourses(@path id: uuid, @body body: AddExperimentCoursesRequest): {
    @statusCode statusCode: 200;
    @body body: ManagementExperimentCourseAssignment[];
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("Remove a course from an experiment that has not started.\n\nRequires ADMIN or EXPERIMENTER. Returns 204. After the first ACTIVE transition, reject removal in every later state with 409 and preserve historical associations. Protect unconfirmed history conservatively. Share activation/replacement transaction locks. Other errors: 400/401/403/404/500.")
  @delete
  @route("/{id}/courses/{courseId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  removeCourse(@path id: uuid, @path courseId: uuid): {
    @statusCode statusCode: 204;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;
}

model ReplaceCourseRequest {
  replacementCourseId: uuid;
  ...Record<never>;
}

@tag("Experiments")
@route("/experiments/{experimentId}/courses/{courseId}/replacement")
@useAuth(SciEdu.Auth.SessionCookieAuth)
interface CourseReplacement {
  @doc("Atomically replace a course in a scheduled experiment.\n\nPermissions: ADMIN or EXPERIMENTER. The experiment must be SCHEDULED and must never have entered ACTIVE; unconfirmed history is not proof that it never started.\nRequest: courseId identifies the current association; replacementCourseId selects the replacement. Idempotency-Key is required.\nResponse: 200 ManagementExperimentCourseAssignment with the new course and linkedAt. The replacement must be published, the original must still be linked and the replacement must not already be assigned. A duplicate or same-course target returns 409 with the original list intact. Copying or publishing never automatically replaces an association.\nTransaction/retries: share experiment and ID-ordered Course locks with activation. Commit replacement and successful-key result together. After authorization, replay the original 200 for a successful same-key, same-request retry even if the old association is gone or the experiment has started; otherwise check the current state. Reusing a key with another request returns 409.\nErrors: 400 invalid UUID/body, 401/403, 404 experiment/course/original association, 409 state/target/key conflict, 500; summer application/problem+json. Never parse detail for a failure kind.")
  @put
  replace(
    @path experimentId: uuid,
    @path courseId: uuid,
    ...SciEdu.Materials.IdempotencyHeader,
    @body body: ReplaceCourseRequest,
  ): {
    @statusCode statusCode: 200;
    @body body: ManagementExperimentCourseAssignment;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;
}
