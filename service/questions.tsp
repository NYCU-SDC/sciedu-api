import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu; // Reference to namespace in main.tsp

namespace SciEdu.Questions;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/**
 * Question types
 */
enum QuestionType {
  CHOICE: "CHOICE",
  TEXT: "TEXT",
}

/**
 * Lifecycle state of an answer's grading result.
 */
enum GradingStatus {
  PENDING: "PENDING",
  GRADED: "GRADED",
  FAILED: "FAILED",
}

/**
 * Mechanism used to grade an answer. LLM is reserved for future text grading.
 */
enum GradingMethod {
  DETERMINISTIC: "DETERMINISTIC",
  MANUAL: "MANUAL",
  LLM: "LLM",
}

/**
 * Whether every automatically gradable stored submission has an answer result
 * evaluated against the current correct-answer version.
 */
enum AnswerResultSyncStatus {
  @doc("At least one eligible submission has no result for the current correct-answer version.")
  PENDING: "PENDING",

  @doc("Every eligible submission has a result for the current correct-answer version. This also applies when no eligible submissions exist.")
  SYNCED: "SYNCED",

  @doc("Synchronization retries were exhausted while at least one eligible result remains unsynchronized.")
  FAILED: "FAILED",
}

/**
 * Option model (maps to options table)
 */
model Option {
  @doc("Option ID")
  id: uuid;

  @doc("Option label, e.g., A, B, C")
  @minLength(1)
  @maxLength(5)
  label: string;

  @doc("Option content")
  @minLength(1)
  @maxLength(1024)
  content: string;
}

/**
 * Question model (maps to questions table)
 */
model Question {
  @doc("Question ID")
  id: uuid;

  @doc("Question type")
  type: QuestionType;

  @doc("Question content/description")
  @minLength(1)
  @maxLength(2000)
  content: string;

  @doc("List of options (only populated when type is CHOICE)")
  options?: Option[];
}

/**
 * Payload for creating or updating a question
 */
model CreateUpdateQuestionRequest {
  @doc("Question type")
  type: QuestionType;

  @doc("Question content")
  @minLength(1)
  @maxLength(2000)
  content: string;

  @doc("List of options. For CHOICE type, this field is required and cannot be empty.")
  options?: {
    @doc("Option label, e.g., A, B, C")
    @minLength(1)
    @maxLength(5)
    label: string;

    @doc("Option content")
    @minLength(1)
    @maxLength(1024)
    content: string;
  }[];
}

/**
 * Payload for storing the correct option of a CHOICE question.
 */
model ChoiceCorrectAnswerRequest {
  type: "CHOICE";
  selectedOptionId: uuid;
}

/**
 * Payload for storing a reference answer for future TEXT grading.
 */
model TextCorrectAnswerRequest {
  type: "TEXT";

  @minLength(1)
  @maxLength(2000)
  referenceAnswer: string;
}

/**
 * Correct-answer payload. The discriminator must match the question type.
 */
@discriminated(#{ envelope: "none", discriminatorPropertyName: "type" })
union UpsertCorrectAnswerRequest {
  CHOICE: ChoiceCorrectAnswerRequest,
  TEXT: TextCorrectAnswerRequest,
}

model CorrectAnswerBase {
  questionId: uuid;

  @minValue(1)
  version: int64;

  @doc("Whether all automatically gradable stored submissions have results evaluated against this version.")
  answerResultSyncStatus: AnswerResultSyncStatus;

  updatedAt: utcDateTime;
}

model ChoiceCorrectAnswer extends CorrectAnswerBase {
  type: "CHOICE";
  selectedOptionId: uuid;
}

model TextCorrectAnswer extends CorrectAnswerBase {
  type: "TEXT";

  @minLength(1)
  @maxLength(2000)
  referenceAnswer: string;
}

/**
 * Question-global stored correct answer. This model is only exposed to
 * EXPERIMENTER and ADMIN.
 */
@discriminated(#{ envelope: "none", discriminatorPropertyName: "type" })
union CorrectAnswer {
  CHOICE: ChoiceCorrectAnswer,
  TEXT: TextCorrectAnswer,
}

/**
 * Answer submitted by a student (maps to questions_users_answers table). Each
 * answer belongs to exactly one question, user, and experiment. A user may
 * submit another answer to the same question in a different experiment.
 */
model Answer {
  @doc("Answer ID")
  id: uuid;

  @doc("ID of corresponding question")
  questionId: uuid;

  @doc("ID of the active experiment in which the answer was submitted")
  experimentId: uuid;

  @doc("Opaque ID of the user who submitted the answer")
  userId: uuid;

  @doc("The ID of the option which the user chose")
  selectedOptionId?: uuid;

  @doc("Textual answer (for TEXT type only)")
  textAnswer?: string;

  @doc("Answer creation time")
  createdAt: utcDateTime;
}

/**
 * Persisted grading result for an answer. isCorrect is omitted while grading is
 * pending or failed, and when the caller is not allowed to see scores.
 */
model AnswerResult {
  answerId: uuid;
  questionId: uuid;
  status: GradingStatus;
  method?: GradingMethod;

  @doc("Whether the current caller may see the correctness result")
  resultVisible: boolean;

  isCorrect?: boolean;
  gradedAt?: utcDateTime;
}

/**
 * Management view of a submitted answer and its grading result.
 */
model AnswerWithResult {
  ...Answer;
  gradingStatus: GradingStatus;
  gradingMethod?: GradingMethod;

  @doc("Whether the submitted answer is correct. Omitted while grading is pending or failed, or when an automatically graded result uses an outdated correct-answer version. MANUAL results are not invalidated by correct-answer updates.")
  isCorrect?: boolean;

  gradedAt?: utcDateTime;
}

model PaginatedAnswersResponse {
  items: AnswerWithResult[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

model QuestionNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: NotFound;
}

model AnswerConflictResponse {
  @statusCode statusCode: 409;
  @body error: Conflict;
}

/**
 * The experiment does not exist, or the question is not reachable through a
 * course assigned to the experiment.
 */
model AnswerScopeNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: NotFound;
}

/**
 * Payload for submitting an answer
 */
model SubmitAnswerRequest {
  @doc("Selected option ID (if it is a choice question)")
  selectedOptionId?: uuid;

  @doc("Textual answer (if it is a text-based question)")
  @minLength(1)
  @maxLength(2000)
  textAnswer?: string;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Questions")
@route("/questions")
interface Questions {
  @doc("List all questions")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  list(): Question[] | ProblemDetail | {
    @statusCode statusCode: 401;
    @body error: SciEdu.Unauthorized;
  };

  @doc("Get details of a single question (including options)")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  get(@path id: uuid):
    | Question
    | QuestionNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      };

  @doc("Create a new question (including options)")
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  create(@body body: CreateUpdateQuestionRequest):
    | {
        @statusCode statusCode: 201;
        @body body: Question;
      }
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  @doc("Update a question (Full update; replaces existing options)")
  @put
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  update(@path id: uuid, @body body: CreateUpdateQuestionRequest):
    | Question
    | QuestionNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  @doc("Delete a question")
  @delete
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  delete(@path id: uuid):
    | {
        @statusCode statusCode: 204;
      }
    | QuestionNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  // -----------------------
  // Correct Answer Sub-resource
  // -----------------------

  @doc("Get the question-global stored correct answer. Requires EXPERIMENTER or ADMIN. This endpoint never releases correct answers to students.")
  @route("/{id}/correct-answer")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  getCorrectAnswer(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: CorrectAnswer;
      }
    | QuestionNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  @doc("""
    Create or fully replace the question-global correct answer. Requires EXPERIMENTER or ADMIN.
    The first correct answer uses version 1. A changed answer increments the version and synchronizes every automatically gradable stored submission across experiments. The status is SYNCED immediately when no eligible submissions exist; otherwise it is PENDING until every eligible result uses the current version.
    An identical update does not increment the version or enqueue duplicate work. If the current status is FAILED, an identical update retries only the missing synchronization work and changes the status to PENDING. Completion of work for an older version must not overwrite the status of a newer version.
    Currently, eligible submissions are CHOICE answers from AUTOMATIC experiments. MANUAL results are not invalidated by a correct-answer update. Future automatically graded methods, including LLM grading, are also eligible.
    """)
  @route("/{id}/correct-answer")
  @put
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  upsertCorrectAnswer(@path id: uuid, @body body: UpsertCorrectAnswerRequest):
    | {
        @statusCode statusCode: 200;
        @body body: CorrectAnswer;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | QuestionNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  // -----------------------
  // Answers Sub-resources
  // -----------------------

  @doc("List answers for a specific question within one experiment. Requires EXPERIMENTER or ADMIN. The question must be reachable through a course assigned to the experiment. Results include grading status and are ordered by creation time descending.")
  @route("/{id}/answers")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listAnswers(
    @path id: uuid,

    @doc("Experiment whose submissions are listed.")
    @query
    experimentId: uuid,

    @query @minValue(1) page?: int32 = 1,

    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedAnswersResponse;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | AnswerScopeNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  @doc("Submit an answer in the student's active experiment. The question must be reachable through an assigned published course. AUTOMATIC CHOICE answers are graded and persisted in the same transaction, but correctness is not included in this response. The same user may answer the question again in a different experiment; duplicate submissions within one experiment return 409.")
  @route("/{id}/answers")
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  submitAnswer(@path id: uuid, @body body: SubmitAnswerRequest):
    | {
        @statusCode statusCode: 201;
        @body answer: Answer;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | AnswerConflictResponse
    | QuestionNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  @doc("Get a persisted grading result without recalculating it. Students may only access their own result. For students, isCorrect is omitted when showScore is false. An automatically graded result evaluated against an older correct-answer version is returned as PENDING; MANUAL results are not invalidated by correct-answer updates.")
  @route("/{questionId}/answers/{answerId}/result")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  getAnswerResult(@path questionId: uuid, @path answerId: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: AnswerResult;
      }
    | QuestionNotFoundResponse
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };
}
