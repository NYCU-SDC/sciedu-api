import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Auth;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

enum OAuthProvider {
  google: "google",
}

/**
 * Login payload for development and test environments.
 *
 * This endpoint must follow the same cookie-setting behavior as OAuth login and
 * must not return access or refresh token strings in the response body.
 */
model DevLoginRequest {
  @doc("The email to simulate login (must already exist in the Users table).")
  @format("email")
  email: string;
}

model Session {
  @doc("The access-token expiration time. The token itself is stored only in the HttpOnly `access_token` cookie.")
  accessTokenExpiresAt: utcDateTime;

  @doc("The refresh-token expiration time. The token itself is stored only in the HttpOnly `refresh_token` cookie.")
  refreshTokenExpiresAt: utcDateTime;

  @doc("The authenticated user, when the endpoint returns user context.")
  user?: Users.User;
}

model CsrfToken {
  @doc("CSRF token that clients must send as `X-CSRF-Token` on cookie-authenticated state-changing requests.")
  csrfToken: string;
}

// -----------------------------------------------------------------------------
// Response models
// -----------------------------------------------------------------------------

model FoundRedirect {
  @statusCode statusCode: 302;

  @doc("Absolute provider URL or validated frontend redirect URL.")
  @header("Location")
  location: string;
}

model AuthFoundRedirect {
  @statusCode statusCode: 302;

  @doc("Validated frontend redirect URL.")
  @header("Location")
  location: string;

  @doc("One or more Set-Cookie headers for HttpOnly auth cookies.")
  @header("Set-Cookie")
  setCookie?: string[];
}

model SessionResponse {
  @statusCode statusCode: 200;
  @body session: Session;
}

model AuthSessionResponse {
  @statusCode statusCode: 200;

  @doc("One or more Set-Cookie headers for HttpOnly auth cookies.")
  @header("Set-Cookie")
  setCookie?: string[];

  @body session: Session;
}

model CsrfTokenResponse {
  @statusCode statusCode: 200;
  @body csrf: CsrfToken;
}

model NoContentResponse {
  @statusCode statusCode: 204;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Auth")
@route("/auth")
interface Auth {
  /**
   * Start a Google OAuth login.
   *
   * The backend validates the optional redirect target, creates a short-lived
   * login attempt with `state` and PKCE metadata, then redirects to the OAuth
   * provider. No token is returned to JavaScript.
   */
  @doc("Start an OAuth login flow.")
  @get
  @route("/login/oauth/{provider}")
  loginOAuth(
    @path provider: OAuthProvider,

    @doc("Optional post-login frontend redirect. Must be a relative path or an allowlisted frontend origin.")
    @query
    redirect?: string,
  ): FoundRedirect | ProblemDetail;

  /**
   * Complete the OAuth login flow.
   *
   * The backend validates `state`, exchanges `code` using the stored PKCE
   * verifier, creates or finds the user, sets HttpOnly auth cookies, and
   * redirects to the validated frontend destination stored in the login attempt.
   */
  @doc("Handle an OAuth provider callback.")
  @get
  @route("/callback")
  callback(
    @doc("Authorization code returned by the OAuth provider.")
    @query
    code?: string,

    @doc("Opaque login-attempt state returned by the OAuth provider.")
    @query
    state?: string,

    @doc("OAuth provider error code, when authorization fails before issuing a code.")
    @query
    error?: string,

    @doc("OAuth provider error description, when available. Implementations must not expose this value directly to users or logs.")
    @query
    errorDescription?: string,
  ): AuthFoundRedirect | Unauthorized | ProblemDetail;

  /**
   * Return session metadata for the current access cookie.
   *
   * This endpoint returns expiry metadata only. It never returns access or
   * refresh token strings.
   */
  @doc("Get the current authenticated session.")
  @get
  @route("/session")
  session(): SessionResponse | Unauthorized | ProblemDetail;

  /**
   * Rotate the refresh token family and issue fresh auth cookies.
   *
   * The refresh token is read only from the HttpOnly `refresh_token` cookie.
   * Clients must include `X-CSRF-Token`; implementations must also validate
   * Origin or Referer according to `docs/AUTH_FLOW.md`.
   */
  @doc("Refresh the current session using the HttpOnly refresh cookie.")
  @post
  @route("/refresh")
  refresh(
    @doc("CSRF token bound to the current session or signed by the backend.")
    @header("X-CSRF-Token")
    csrfToken: string,
  ): AuthSessionResponse | Unauthorized | Forbidden | ProblemDetail;

  /**
   * Revoke the current refresh-token family and clear auth cookies.
   *
   * Logout is idempotent for missing, expired, or already revoked refresh
   * cookies, but CSRF validation failure still returns 403.
   */
  @doc("Log out and clear auth cookies.")
  @post
  @route("/logout")
  logout(
    @doc("CSRF token bound to the current session or signed by the backend.")
    @header("X-CSRF-Token")
    csrfToken: string,
  ): NoContentResponse | Forbidden | ProblemDetail;

  /**
   * Issue or return the CSRF token used by cookie-authenticated state-changing requests.
   *
   * The CSRF token is not an auth credential and may be readable by JavaScript.
   */
  @doc("Get a CSRF token for cookie-authenticated state-changing requests.")
  @get
  @route("/csrf")
  csrf(): CsrfTokenResponse | ProblemDetail;

  /**
   * Development-only email login.
   *
   * This must be disabled in production. When enabled, it sets the same
   * HttpOnly cookies as OAuth login and returns only session metadata.
   */
  @doc("Development login that sets auth cookies without returning token strings.")
  @post
  @route("/dev/login")
  devLogin(
    @doc("CSRF token for the development login request.")
    @header("X-CSRF-Token")
    csrfToken: string,

    @body body: DevLoginRequest,
  ): AuthSessionResponse | NotFound | Forbidden | ProblemDetail;
}
