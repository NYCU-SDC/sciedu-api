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
 * Answer submitted by a student (maps to questions_users_answers table)
 */
model Answer {
  @doc("Answer ID")
  id: uuid;

  @doc("ID of corresponding question")
  questionId: uuid;

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
    | NotFound
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
    | NotFound
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
    | NotFound
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

  @doc("Get all answers for a specific question. Requires EXPERIMENTER or ADMIN. Results are ordered by creation time descending.")
  @route("/{id}/answers")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listAnswers(@path id: uuid):
    | Answer[]
    | NotFound
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      };

  @doc("Submit an answer for a specific question")
  @route("/{id}/answers")
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  submitAnswer(@path id: uuid, @body body: SubmitAnswerRequest):
    | {
        @statusCode statusCode: 201;
        @body answer: Answer;
      }
    | Conflict
    | NotFound
    | ProblemDetail
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      };
}
