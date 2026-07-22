import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Users;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/** Roles that can be assigned to a SciEdu user. */
enum UserRole {
  STUDENT: "STUDENT",
  EXPERIMENTER: "EXPERIMENTER",
  ADMIN: "ADMIN",
}

/** A SciEdu user profile. */
model User {
  id: uuid;
  email: string;
  name: string;
  avatarUrl?: string;
  roles: UserRole[];
  createdAt: utcDateTime;
  updatedAt: utcDateTime;
}

/** Paginated user directory response. */
model PaginatedUsersResponse {
  items: User[];
  totalPages: int32;
  totalItems: int32;
  currentPage: int32;
  pageSize: int32;
  hasNextPage: boolean;
}

/** Fully replaces a user's roles. Roles must be unique. */
model UpdateUserRolesRequest {
  @minItems(1)
  @maxItems(3)
  roles: UserRole[];
}

model UserNotFoundResponse {
  @statusCode statusCode: 404;
  @body error: SciEdu.NotFound;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Users")
@route("/users")
interface Users {
  @doc("Return the currently authenticated user's profile and latest roles.")
  @get
  @route("/me")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  me(): {
    @statusCode statusCode: 200;
    @body body: User;
  } | {
    @statusCode statusCode: 401;
    @body error: SciEdu.Unauthorized;
  } | ProblemDetail;

  @doc("List users. Requires ADMIN or EXPERIMENTER. Results are ordered by name, then ID.")
  @get
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  list(
    @query
    @minValue(1)
    page?: int32 = 1,

    @doc("Number of users per page. Maximum value is 100.")
    @query
    @minValue(1)
    @maxValue(100)
    pageSize?: int32 = 20,

    @doc("Case-insensitive substring search over name and email.")
    @query
    @minLength(1)
    @maxLength(200)
    search?: string,

    @doc("Only return users that have this role.")
    @query
    role?: UserRole,
  ):
    | {
        @statusCode statusCode: 200;
        @body body: PaginatedUsersResponse;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | ProblemDetail;

  @doc("Get a user by ID. Requires ADMIN or EXPERIMENTER.")
  @get
  @route("/{id}")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  get(@path id: uuid):
    | {
        @statusCode statusCode: 200;
        @body body: User;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | UserNotFoundResponse
    | ProblemDetail;

  @doc("Soft-delete a user, revoke their sessions, and prevent future OAuth login. Requires ADMIN and cannot target the caller.")
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
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | UserNotFoundResponse
    | ProblemDetail;

  @doc("Fully replace a user's roles. Requires ADMIN and cannot target the caller.")
  @put
  @route("/{id}/roles")
  @useAuth(SciEdu.Auth.SessionCookieAuth)
  updateRoles(@path id: uuid, @body body: UpdateUserRolesRequest):
    | {
        @statusCode statusCode: 200;
        @body body: User;
      }
    | {
        @statusCode statusCode: 401;
        @body error: SciEdu.Unauthorized;
      }
    | {
        @statusCode statusCode: 403;
        @body error: SciEdu.Forbidden;
      }
    | {
        @statusCode statusCode: 400;
        @body error: ProblemDetail;
      }
    | UserNotFoundResponse
    | ProblemDetail;
}
