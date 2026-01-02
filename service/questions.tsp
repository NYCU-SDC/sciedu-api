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
  id: integer;

  @doc("Option label, e.g., A, B, C")
  @minLength(1)
  @maxLength(5)
  label: string;

  @doc("Option content")
  content: string;
}

/**
 * Question model (maps to questions table)
 */
model Question {
  @doc("Question ID")
  id: integer;

  @doc("Question type")
  type: QuestionType;

  @doc("Question content/description")
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
  content: string;

  @doc("List of options. For CHOICE type, this field is required and cannot be empty.")
  options?: {
    label: string;
    content: string;
  }[];
}

/**
 * Answer submitted by a student (maps to questions_users_answers table)
 */
model Answer {
  @doc("Answer ID")
  id: integer;

  @doc("User ID of the respondent")
  userId: integer; // Kept as it's defined in the schema, though viewing requirements may vary

  @doc("Question ID")
  questionId: integer;

  @doc("Selected option ID (for CHOICE type only)")
  selectedOptionId?: integer;

  @doc("Textual answer (for TEXT type only)")
  textAnswer?: string;
}

/**
 * Payload for submitting an answer
 */
model SubmitAnswerRequest {
  @doc("Selected option ID (if it is a choice question)")
  selectedOptionId?: integer;

  @doc("Textual answer (if it is a text-based question)")
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
  list(): Question[] | ProblemDetail;

  @doc("Get details of a single question (including options)")
  @get
  get(@path id: integer): Question | NotFound | ProblemDetail;

  @doc("Create a new question (including options)")
  @post
  create(@body body: CreateUpdateQuestionRequest): {
    @statusCode statusCode: 201;
    @body body: Question;
  } | ProblemDetail;

  @doc("Update a question (Full update; replaces existing options)")
  @put
  update(
    @path id: integer,
    @body body: CreateUpdateQuestionRequest,
  ): Question | NotFound | ProblemDetail;

  @doc("Delete a question")
  @delete
  delete(@path id: integer): {
    @statusCode statusCode: 204;
  } | NotFound | ProblemDetail;

  // -----------------------
  // Answers Sub-resources
  // -----------------------

  @doc("Get all answers for a specific question (for Experimenter view)")
  @route("/{id}/answers")
  @get
  listAnswers(@path id: integer): Answer[] | NotFound | ProblemDetail;

  @doc("Submit an answer for a specific question")
  @route("/{id}/answers")
  @post
  submitAnswer(@path id: integer, @body body: SubmitAnswerRequest): {
    @statusCode statusCode: 201;
    @body body: Answer;
  } | NotFound | ProblemDetail;
}
