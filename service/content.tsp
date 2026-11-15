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

@tag("Content")
@route("/content")
@useAuth(SciEdu.Auth.SessionCookieAuth)
interface Content {
  @doc("List accessible text resources.\n\nReturns 200 with standard pagination. Management roles share access; students may only read resources reachable from PUBLISHED courses assigned to their current valid experiment. Listing must enforce the same ACL as individual reads. Errors: 400 invalid pagination, 401/403, 500; application/problem+json.")
  @get
  @route("/text")
  listText(
    @query @minValue(1) page?: int32 = 1,

    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedTextResponse;
      }
    | SciEdu.Materials.BadRequest
    | SciEdu.Materials.Unauthenticated
    | SciEdu.Materials.Denied
    | SciEdu.Materials.InternalError;

  @doc("Get an authorized text resource.\n\nReturns 200 TextContent. Students must reach the resource through a PageBlock or contextTextIds in an authorized published course. Management roles may read shared resources or their own staged uploads. Unknown or invisible resources return 404. Other errors: 400, 401/403, 500.")
  @get
  @route("/text/{id}")
  getText(@path id: uuid): {
    @statusCode statusCode: 200;
    @body body: TextContent;
  } | SciEdu.Materials.ReadErrors;

  @doc("Batch-get authorized text resources.\n\nReturns 200 TextContent[]. Enforce the same resource reachability and role checks as individual reads; batch access must not bypass context-resource authorization. Errors: 400 invalid IDs or count, 401/403/404, 500.")
  @post
  @route("/text/batch")
  batchGetText(@body body: BatchTextRequest): {
    @statusCode statusCode: 200;
    @body body: TextContent[];
  } | SciEdu.Materials.ReadErrors;

  @doc("Create immutable text or context content.\n\nPermissions: ADMIN or EXPERIMENTER. Record the creator for staging access and garbage-collection checks.\nRequest: required Idempotency-Key and nonempty content. Text edits create a new resource and replace its reference; no text PUT is introduced.\nResponse: 201 TextContent. Repeating the same key and payload returns the original resource ID and 201; retain successful results for at least 24 hours. Creating a resource does not save a course document.\nErrors: 400, 401/403, 409 key conflict or in-flight request, 500.")
  @post
  @route("/text")
  createText(
    ...SciEdu.Materials.IdempotencyHeader,
    @body body: CreateTextRequest,
  ):
    | {
        @statusCode statusCode: 201;
        @body body: TextContent;
      }
    | SciEdu.Materials.BadRequest
    | SciEdu.Materials.Unauthenticated
    | SciEdu.Materials.Denied
    | SciEdu.Materials.ConflictError
    | SciEdu.Materials.InternalError;

  @doc("Stream an authorized media resource.\n\nPermissions: session authentication and course-resource reachability. Management roles may read shared or their own staged resources; students need a reference from an authorized PUBLISHED course. Knowing a UUID is insufficient.\nResponse: 200 raw bytes. Images use their actual MIME type, Content-Length, inline Content-Disposition and X-Content-Type-Options: nosniff. Other generic media retain their existing purpose and disposition. Existing session and CORS policies apply.\nErrors before headers: 400 invalid UUID, 401/403/404, 500. Stream the file instead of buffering it entirely.")
  @get
  @route("/media/{id}")
  streamMedia(@path id: uuid): {
    @statusCode statusCode: 200;
    @header("Content-Type") contentType: string;
    @header("Content-Length") contentLength: int64;
    @header("Content-Disposition") contentDisposition: string;
    @header("X-Content-Type-Options") nosniff: "nosniff";
    @body body: bytes;
  } | SciEdu.Materials.ReadErrors;

  @doc("Upload a material image or generic media.\n\nPermissions: ADMIN or EXPERIMENTER; persist uploader identity for staging authorization and cleanup.\nRequest: multipart/form-data with the existing content file part and optional purpose=material-image. Idempotency-Key is required; the semantic hash includes the file digest and purpose.\nMaterial images: JPEG, PNG or WebP only, at most 10 MiB and 40 decoded megapixels. Check actual MIME and decoded dimensions; reject SVG and HTML. Omitting purpose preserves the existing generic media policy.\nResponse: 201 MaterialImageResource for material-image, including controlled url, mimeType, dimensions, sizeBytes and optional sha256; otherwise the existing MediaContent. Editor hydration never exposes storage paths or file bytes.\nRetries: coordinate staged storage and the operation record so the same key returns the same resource ID. Backend cleanup handles failed leftovers.\nErrors: 400, 401/403, 409 key conflict, 413 size or pixel limit, 415 unsupported media, 500.")
  @post
  @route("/media")
  createMedia(
    ...SciEdu.Materials.IdempotencyHeader,
    @multipartBody body: {
      content: HttpPart<bytes>;
      purpose?: HttpPart<"material-image">;
    },
  ):
    | {
        @statusCode statusCode: 201;
        @body body: MediaContent | SciEdu.Materials.MaterialImageResource;
      }
    | SciEdu.Materials.BadRequest
    | SciEdu.Materials.Unauthenticated
    | SciEdu.Materials.Denied
    | SciEdu.Materials.ConflictError
    | SciEdu.Materials.TooLarge
    | SciEdu.Materials.UnsupportedMedia
    | SciEdu.Materials.InternalError;

  @doc("Delete an unprotected resource.\n\nRequires ADMIN or EXPERIMENTER. Returns 204 without a body. References from v2 or protected courses cause 409; use copy-on-write or a document update instead of cascading through history. Removing blocks or courses does not immediately delete resources. Mark orphans and wait at least seven days, then scan PageBlock, context and unfinished-operation references before collection. Other errors: 400/401/403/404/500.")
  @delete
  @route("/{id}")
  delete(@path id: uuid): {
    @statusCode statusCode: 204;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;
}
