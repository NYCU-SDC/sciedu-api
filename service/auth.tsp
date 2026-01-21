import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Auth;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/**
 * [Added in Phase 1] Login payload for development purposes
 */
model DevLoginRequest {
  @doc("The email to simulate login (must already exist in the Users table)")
  @format("email")
  email: string;
}

model AuthToken {
  @doc("The short-lived JWT for accessing resources")
  accessToken: string;

  @doc("The long-lived token for refreshing the access token")
  refreshToken: string;

  @doc("Token expiration time")
  expirationTime: utcDateTime;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Auth")
@route("/auth")
interface Auth {
  /**
   * [Added in Phase 1] Backdoor for development
   * Bypasses OAuth and issues tokens directly based on email.
   */
  @doc("Development Login (Bypasses OAuth, issues token via email directly)")
  @post
  @route("/dev/login")
  devLogin(@body body: DevLoginRequest): {
    @statusCode statusCode: 200;
    @body token: AuthToken;
  } | NotFound | ProblemDetail;

  @doc("Refresh the Access Token")
  @post
  @route("/refreshToken/{refreshToken}")
  refresh(@path refreshToken: string): {
    @statusCode statusCode: 200;
    @body token: AuthToken;
  } | Unauthorized | ProblemDetail;
}
