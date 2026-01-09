import "@typespec/http";
import "@typespec/versioning";
import "./service/healthz.tsp";
import "./service/auth.tsp";
import "./service/users.tsp";
import "./service/questions.tsp";

using Http;
using Versioning;

@service(#{ title: "SciEdu API" })
@server("https://dev.sciedu.sdc.nycu.club", "SciEdu server endpoint")
@versioned(Versions)
@route("/api")
namespace SciEdu;

enum Versions {
  v1: "1.0.0",
}

@format("uuid")
scalar uuid extends string;

// 1. Define the base RFC 9457 ProblemDetail
@error
@doc("Problem represents a problem detail as defined in RFC 9457")
model ProblemDetail {
  @doc("Type indicates the URI that identifies the problem type. Defaults to 'about:blank'.")
  type: string;

  @doc("The problem's title. A short, human-readable summary of the problem type.")
  title: string;

  @doc("The problem's status code.")
  status: integer;

  @doc("The problem's detail. A human-readable explanation specific to this occurrence of the problem.")
  detail: string;

  @doc("A URI reference that identifies the specific occurrence of the problem.")
  instance?: string;
}

// 2. Extend ProblemDetail for Unauthorized errors
@error
model Unauthorized extends ProblemDetail {
  // Override inherited fields with literal types (fixed values)
  title: "Unauthorized";
  status: 401;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/401";
  
  // 'detail' and 'instance' are automatically inherited; 
  // no need to redefine them unless adding specific documentation.
}

// 3. Extend ProblemDetail for NotFound errors
@error
model NotFound extends ProblemDetail {
  // Override inherited fields with fixed values
  title: "Not Found";
  status: 404;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/404";
  detail: string;
}

@error
model Conflict {
  title: "Conflict";
  status: 409;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/409";
  detail: string;
}
