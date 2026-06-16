import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

@tag("Auth")
namespace SciEdu.Auth;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

@doc("""
  Authenticated session metadata. Session tokens are issued and refreshed through
  HttpOnly cookies and are intentionally not exposed in response bodies.
  """)
model SessionResponse {
  @doc("Authenticated user's display username.")
  username: string;

  @doc("Authenticated user's email address.")
  email: string;

  @doc("Timestamp when the current access token expires.")
  accessTokenExpiresAt: utcDateTime;

  @doc("Timestamp when the current refresh token family expires.")
  refreshTokenExpiresAt: utcDateTime;
}

model UnauthorizedResponse {
  @statusCode statusCode: 401;
  @body error: SciEdu.Unauthorized;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@route("/auth")
interface Auth {
  @doc("Return metadata for the authenticated session using session cookies.")
  @get
  @route("/session")
  session(
    @doc("Access token session cookie.")
    @cookie
    access_token: string,

    @doc("Refresh token session cookie.")
    @cookie
    refresh_token: string,
  ): {
    @statusCode statusCode: 200;
    @body body: SessionResponse;
  } | UnauthorizedResponse;

  @doc("""
    Rotate the refresh token, set new session cookies, and return updated
    session expiry metadata.
    """)
  @post
  @route("/refresh")
  refresh(
    @doc("Refresh token session cookie to rotate.")
    @cookie
    refresh_token: string,
  ): {
    @statusCode statusCode: 200;
    @header("Set-Cookie") setCookie: string[];
    @body body: SessionResponse;
  } | UnauthorizedResponse | ProblemDetail;

  @doc("Revoke the entire refresh token family, clear session cookies, and end the session.")
  @post
  @route("/logout")
  logout(
    @doc("Refresh token session cookie to revoke. Missing cookies still result in a cleared session.")
    @cookie
    refresh_token?: string,
  ): {
    @statusCode statusCode: 200;
    @header("Set-Cookie") setCookie: string[];
  } | ProblemDetail;
}

@route("/login/oauth")
interface OAuthLogin {
  @doc("""
    Start the Google OAuth login flow and redirect the browser to the OAuth
    authorization server. The redirect URL is stored server-side with the OAuth
    state and used after callback completion.
    """)
  @get
  @route("/google")
  loginGoogle(@doc("Post-login redirect URL.") @query r: string): {
    @statusCode statusCode: 302;
    @header("Location") location: string;
  } | ProblemDetail;
}

@route("/auth")
interface OAuthCallback {
  @doc("""
    Complete the Google OAuth login flow, set session cookies on success, and
    redirect the client to the originally requested URL.
    """)
  @get
  @route("/callback")
  callback(
    @doc("OAuth authorization code returned by Google.")
    @query
    code?: string,

    @doc("OAuth state value used to validate the login attempt.")
    @query
    state?: string,
  ): {
    @statusCode statusCode: 302;
    @header("Location") location: string;
    @header("Set-Cookie") setCookie: string[];
  } | UnauthorizedResponse | ProblemDetail;
}
