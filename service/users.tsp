import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Users;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

enum UserRole {
  STUDENT: "STUDENT",
  EXPERIMENTER: "EXPERIMENTER",
  ADMIN: "ADMIN",
}

model User {
  @doc("The user's unique identifier.")
  id: uuid;

  @doc("Email address")
  email: string;

  @doc("Display name")
  name: string;

  @doc("User avatar URL")
  avatarUrl?: string;

  @doc("Global roles of the user.")
  roles: UserRole[];
}

// [Added in Phase 1] Payload for creating a user
model CreateUserRequest {
  @doc("Email address")
  @format("email")
  email: string;

  @doc("Display name")
  name: string;

  @doc("System roles")
  roles: UserRole[];

  // Phase 1 does not require a password as we simulate Google Login (Trust Email)
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Users")
@route("/users")
interface Users {
  @doc("Get information of the currently authenticated user")
  @get
  @route("/me")
  getMe():
    | {
        @statusCode statusCode: 200;
        @body user: User;
      }
    | Unauthorized
    | NotFound
    | ProblemDetail;

  // [Added in Phase 1] Allows for quick user seeding
  @doc("Create a user (for Development/Seeding purposes)")
  @post
  create(@body body: CreateUserRequest): {
    @statusCode statusCode: 201;
    @body user: User;
  } | Conflict | ProblemDetail;
}
