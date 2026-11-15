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

  @doc("The containing Course document revision, not an independent Page version. Legacy responses may omit it.")
  revision?: SciEdu.Materials.Revision;

  @doc("Present only for persisted v2 courses. Legacy responses omit it. Students render nodes instead of inferring layout from special displayOrder values.")
  presentation?: SciEdu.Materials.PagePresentation;

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
  @doc("List course pages and v2 presentation settings.\n\nReturns 200 Page[] ordered by displayOrder. Students need a PUBLISHED course assigned to their current valid experiment. GET never migrates or writes data. V2 Page objects include presentation and the Course revision; blocks remain TEXT, MEDIA or QUESTION and exclude correct answers. Errors: 400/401/403/404/500.")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  list(@path courseId: uuid): {
    @statusCode statusCode: 200;
    @body body: Page[];
  } | SciEdu.Materials.ReadErrors;

  @doc("Create a legacy course page.\n\nReturns 201 PageDetail from title and displayOrder. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; use editor PUT. Formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Share activation locks and advance Course revision on success. Historical FK conflicts return 409; other errors: 400/401/403/404/500.")
  @post
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  create(@path courseId: uuid, @body body: CreatePageRequest): {
    @statusCode statusCode: 201;
    @body body: PageDetail;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("Reorder all pages in a legacy course.\n\nReturns 200 Page[]. pageIds must contain every course page exactly once; reorder atomically. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Share activation locks and advance Course revision. Other errors: 400/401/403/404/500.")
  @put
  @route("/order")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  reorder(@path courseId: uuid, @body body: ReorderPagesRequest): {
    @statusCode statusCode: 200;
    @body body: Page[];
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;
}

@tag("Pages")
@route("/pages")
interface Pages {
  @doc("Get a page and its blocks.\n\nReturns 200 PageDetail with blocks ordered by displayOrder. Preserve PUBLISHED/current-valid-experiment student access. GET never migrates or writes data. V2 Page includes presentation and Course revision; blocks remain the three resource types without correct answers. Errors: 400/401/403/404/500.")
  @get
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  get(@path id: uuid): {
    @statusCode statusCode: 200;
    @body body: PageDetail;
  } | SciEdu.Materials.ReadErrors;

  @doc("Update legacy page metadata.\n\nReturns 200 PageDetail after replacing title and displayOrder. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Coordinate activation locks and advance Course revision. Errors: 400/401/403/404/409/500.")
  @put
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  update(@path id: uuid, @body body: UpdatePageRequest): {
    @statusCode statusCode: 200;
    @body body: PageDetail;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("Delete a legacy page and its block references.\n\nReturns 204 without deleting shared resources. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Coordinate activation locks and advance Course revision. Preserve historical references with 409 on FK conflicts. Other errors: 400/401/403/404/500.")
  @delete
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  delete(@path id: uuid): {
    @statusCode statusCode: 204;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("List page resource blocks.\n\nReturns 200 PageBlock[] ordered by displayOrder, retaining only TEXT, MEDIA and QUESTION. Enforce the existing PUBLISHED/current-valid-experiment student access. GET never migrates or writes data. Read Page.presentation separately for v2 layout; this response excludes correct answers. Errors: 400/401/403/404/500.")
  @get
  @route("/{id}/blocks")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  listBlocks(@path id: uuid): {
    @statusCode statusCode: 200;
    @body body: PageBlock[];
  } | SciEdu.Materials.ReadErrors;

  @doc("Create a legacy page resource reference.\n\nReturns 201 PageBlock. resourceId must exist, be usable by the caller and match type. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Coordinate activation locks and advance Course revision. Errors: 400/401/403/404/409/500.")
  @post
  @route("/{id}/blocks")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  createBlock(@path id: uuid, @body body: CreateUpdatePageBlockRequest): {
    @statusCode statusCode: 201;
    @body body: PageBlock;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("Update a legacy page resource reference.\n\nReturns 200 PageBlock after validating page/block ownership and resource type/access. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Coordinate activation locks and advance Course revision. Errors: 400/401/403/404/409/500.")
  @put
  @route("/{id}/blocks/{blockId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  updateBlock(
    @path id: uuid,
    @path blockId: uuid,
    @body body: CreateUpdatePageBlockRequest,
  ): {
    @statusCode statusCode: 200;
    @body body: PageBlock;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("Delete a legacy page resource reference.\n\nReturns 204 without deleting the referenced Content or Question. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Coordinate activation locks and advance Course revision. Historical FK conflicts return 409. Other errors: 400/401/403/404/500.")
  @delete
  @route("/{id}/blocks/{blockId}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  deleteBlock(@path id: uuid, @path blockId: uuid): {
    @statusCode statusCode: 204;
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;

  @doc("Reorder all blocks in a legacy page.\n\nReturns 200 PageBlock[]. blockIds must contain every page block exactly once; reorder atomically. Requires ADMIN or EXPERIMENTER and an editable legacy course. V2 returns 409 EDITOR_DOCUMENT_REQUIRED; formally used or usage-unconfirmed courses return 409 COURSE_NOT_EDITABLE. Coordinate activation locks and advance Course revision. Errors: 400/401/403/404/409/500.")
  @put
  @route("/{id}/blocks/order")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  reorderBlocks(@path id: uuid, @body body: ReorderPageBlocksRequest): {
    @statusCode statusCode: 200;
    @body body: PageBlock[];
  } | SciEdu.Materials.ReadErrors | SciEdu.Materials.ConflictError;
}
