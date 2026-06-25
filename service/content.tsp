import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Content;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/**
 * Content type discriminant
 */
enum ContentType {
  TEXT: "TEXT",
  MEDIA: "MEDIA",
}

/**
 * A text content item
 */
model TextContent {
  @doc("Content ID")
  id: uuid;

  @doc("Content type — always TEXT")
  type: "TEXT";

  @doc("Text body")
  content: string;
}

/**
 * A media content item (references a stored file)
 */
model MediaContent {
  @doc("Content ID")
  id: uuid;

  @doc("Content type — always MEDIA")
  type: "MEDIA";

  @doc("Stored file path")
  content: string;
}

/**
 * Paginated list of text contents
 */
model PaginatedTextResponse {
  items: TextContent[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

/**
 * Paginated list of media contents
 */
model PaginatedMediaResponse {
  items: MediaContent[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

/**
 * Request body for batch-fetching text contents by ID
 */
model BatchTextRequest {
  @doc("List of text content IDs to fetch")
  @minItems(1)
  @maxItems(100) // Prevent DB overload
  ids: uuid[];
}

/**
 * Request body for creating a text content
 */
model CreateTextRequest {
  @doc("Text body")
  @minLength(1)
  content: string;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Content")
@route("/content")
interface Content {
  // ── Text ──────────────────────────────────────────────────────────────────

  @doc("List text contents (paginated).")
  @get
  @route("/text")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listText(
    @query page?: int32 = 1,

    @doc("Number of items per page. Maximum value is 100.")
    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,
  ): {
    @statusCode statusCode: 200;
    @body body: PaginatedTextResponse;
  } | {
    @statusCode statusCode: 401;
    @body error: SciEdu.Unauthorized;
  } | ProblemDetail;

  @doc("Get a single text content by ID")
  @get
  @route("/text/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  getText(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: TextContent;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | NotFound
    | ProblemDetail;

  @doc("Batch-fetch text contents by a list of IDs. Returns an array of TextContent.")
  @post
  @route("/text/batch")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  batchGetText(@body body: BatchTextRequest): {
    @statusCode statusCode: 200;
    @body body: TextContent[];
  } | {
    @statusCode statusCode: 401;
    @body error: SciEdu.Unauthorized;
  } | ProblemDetail;

  @doc("Create a new text content")
  @post
  @route("/text")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  createText(@body body: CreateTextRequest):
    | {
        @statusCode statusCode: 201;
        @body body: TextContent;
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

  // ── Media ─────────────────────────────────────────────────────────────────

  @doc("""
      Stream a media file. The response body is the raw binary file stream.
      The handler is responsible for closing the stream after the response is sent.
      Do NOT buffer the entire file into memory; use io.Copy to pipe the stream
      directly to the response writer.
    """)
  @get
  @route("/media/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  streamMedia(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @header("Content-Type") contentType: string;
        @header("Content-Length") contentLength: int64;
        @header("Content-Disposition") contentDisposition: string;
        @body body: bytes;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | NotFound
    | ProblemDetail;

  @doc("""
        Upload a new media file (multipart/form-data).
        The `content` part carries the raw file bytes.
        Returns the created MediaContent record with the stored file path.
    """)
  @post
  @route("/media")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  createMedia(
    @multipartBody body: {
      @doc("Raw file bytes to upload")
      content: HttpPart<bytes>;
    },
  ):
    | {
        @statusCode statusCode: 201;
        @body body: MediaContent;
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

  // ── Shared ────────────────────────────────────────────────────────────────

  @doc("Delete a content item (text or media) by ID")
  @delete
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  delete(@path id: uuid):
    | {
        @statusCode statusCode: 204;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | NotFound
    | ProblemDetail;
}
