import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Pages;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

enum PageBlockType {
  TEXT: "TEXT",
  MEDIA: "MEDIA",
  QUESTION: "QUESTION",
}

model Page {
  id: uuid;
  courseId: uuid;

  @minLength(1)
  @maxLength(200)
  title: string;

  @minValue(0)
  displayOrder: int32;

  createdAt: utcDateTime;
  updatedAt: utcDateTime;
}

model PageBlock {
  id: uuid;
  pageId: uuid;
  type: PageBlockType;
  resourceId: uuid;

  @minValue(0)
  displayOrder: int32;

  required: boolean;
  createdAt: utcDateTime;
  updatedAt: utcDateTime;
}

model PageDetail extends Page {
  @doc("Blocks ordered by displayOrder.")
  blocks: PageBlock[];
}

model CreatePageRequest {
  @minLength(1)
  @maxLength(200)
  title: string;

  @minValue(0)
  displayOrder: int32;
}

/** Fully replaces a page's editable metadata. */
model UpdatePageRequest {
  @minLength(1)
  @maxLength(200)
  title: string;

  @minValue(0)
  displayOrder: int32;
}

model ReorderPagesRequest {
  @doc("Every page in the course exactly once, in the desired order.")
  @minItems(1)
  @maxItems(500)
  pageIds: uuid[];
}

model CreateUpdatePageBlockRequest {
  @doc("Block resource type.")
  type: PageBlockType;

  @doc("ID of the referenced resource. TEXT and MEDIA map to content_id and must match contents.type; QUESTION maps to question_id.")
  resourceId: uuid;

  @minValue(0)
  displayOrder: int32;

  required: boolean;
}

model ReorderPageBlocksRequest {
  @doc("Every block in the page exactly once, in the desired order.")
  @minItems(1)
  @maxItems(1000)
  blockIds: uuid[];
}

model PageNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: NotFound;
}

model PageConflictResponse {
  @statusCode statusCode: 409;
  @body error: Conflict;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Pages")
@route("/courses/{courseId}/pages")
interface CoursePages {
  @doc("List pages in display order. Students may only access a PUBLISHED course assigned to their current experiment.")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  list(@path courseId: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: Page[];
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | PageNotFoundResponse
    | ProblemDetail;

  @doc("Create a page in a course. Requires EXPERIMENTER or ADMIN.")
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  create(@path courseId: uuid, @body body: CreatePageRequest):
    | {
        @statusCode statusCode: 201;
        @body body: PageDetail;
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
    | PageNotFoundResponse
    | PageConflictResponse
    | ProblemDetail;

  @doc("Atomically reorder every page in a course. Requires EXPERIMENTER or ADMIN.")
  @put
  @route("/order")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  reorder(@path courseId: uuid, @body body: ReorderPagesRequest):
    | {
        @statusCode statusCode: 200;
        @body body: Page[];
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
    | PageNotFoundResponse
    | PageConflictResponse
    | ProblemDetail;
}

@tag("Pages")
@route("/pages")
interface Pages {
  @doc("Get a page with its blocks in display order. Students may only access pages from a PUBLISHED course assigned to their current experiment.")
  @get
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  get(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: PageDetail;
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | PageNotFoundResponse
    | ProblemDetail;

  @doc("Fully update page metadata. Requires EXPERIMENTER or ADMIN. Changes are immediately visible to assigned experiments.")
  @put
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  update(@path id: uuid, @body body: UpdatePageRequest):
    | {
        @statusCode statusCode: 200;
        @body body: PageDetail;
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
    | PageNotFoundResponse
    | PageConflictResponse
    | ProblemDetail;

  @doc("Delete a page and cascade deletion to its blocks. Requires EXPERIMENTER or ADMIN.")
  @delete
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  delete(@path id: uuid):
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
    | PageNotFoundResponse
    | ProblemDetail;

  @doc("List a page's blocks in display order. Students may only access blocks through an authorized page.")
  @get
  @route("/{id}/blocks")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listBlocks(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: PageBlock[];
      }
    | {
        @statusCode statusCode: 401;
        @body error: Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: Forbidden;
      }
    | PageNotFoundResponse
    | ProblemDetail;

  @doc("Create a block. resourceId must exist and match type. Requires EXPERIMENTER or ADMIN.")
  @post
  @route("/{id}/blocks")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  createBlock(@path id: uuid, @body body: CreateUpdatePageBlockRequest):
    | {
        @statusCode statusCode: 201;
        @body body: PageBlock;
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
    | PageNotFoundResponse
    | PageConflictResponse
    | ProblemDetail;

  @doc("Fully update a block. resourceId must exist and match type. Requires EXPERIMENTER or ADMIN.")
  @put
  @route("/{id}/blocks/{blockId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  updateBlock(
    @path id: uuid,
    @path blockId: uuid,
    @body body: CreateUpdatePageBlockRequest,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PageBlock;
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
    | PageNotFoundResponse
    | PageConflictResponse
    | ProblemDetail;

  @doc("Delete a block. Requires EXPERIMENTER or ADMIN.")
  @delete
  @route("/{id}/blocks/{blockId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  deleteBlock(@path id: uuid, @path blockId: uuid):
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
    | PageNotFoundResponse
    | ProblemDetail;

  @doc("Atomically reorder every block in a page. Requires EXPERIMENTER or ADMIN.")
  @put
  @route("/{id}/blocks/order")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  reorderBlocks(@path id: uuid, @body body: ReorderPageBlocksRequest):
    | {
        @statusCode statusCode: 200;
        @body body: PageBlock[];
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
    | PageNotFoundResponse
    | PageConflictResponse
    | ProblemDetail;
}
