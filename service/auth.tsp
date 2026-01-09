import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Auth;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/**
 * Request payload for Google Login
 */
model GoogleLoginRequest {
  @doc("Google OAuth2 Authorization Code")
  code: string;

  @doc("The redirect URI used in the initial authorization request")
  redirectUri?: string;
}

/**
 * [Added in Phase 1] Login payload for development purposes
 */
model DevLoginRequest {
  @doc("The email to simulate login (must already exist in the Users table)")
  @format("email")
  email: string;
}

model RefreshTokenRequest {
  @doc("The persistent refresh token used to obtain a new access token")
  refreshToken: string;
}

model AuthToken {
  @doc("The short-lived JWT for accessing resources")
  accessToken: string;

  @doc("The long-lived token for refreshing the access token")
  refreshToken: string;

  @doc("Token expiration time in seconds")
  expiresIn: integer;

  @doc("The type of token issued")
  tokenType: "Bearer";
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Auth")
@route("/auth")
interface Auth {
  //   @doc("Login using Google OAuth Code")
  //   @post
  //   @route("/google")
  //   loginWithGoogle(@body body: GoogleLoginRequest): {
  //     @statusCode statusCode: 200;
  //     @body body: AuthToken;
  //   } | ProblemDetail;

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
  @route("/refresh")
  refresh(@body body: RefreshTokenRequest): {
    @statusCode statusCode: 200;
    @body token: AuthToken;
  } | Unauthorized | ProblemDetail;
}
