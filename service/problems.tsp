import "@typespec/http";

using Http;

namespace SciEdu;

@error
@doc("Problem represents a problem detail as defined in RFC 9457. Backend implementation should use the `summer` package (github.com/NYCU-SDC/summer) for constructing and returning these errors.")
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

@error
model Unauthorized extends ProblemDetail {
  title: "Unauthorized";
  status: 401;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/401";
}

@error
model Forbidden extends ProblemDetail {
  title: "Forbidden";
  status: 403;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/403";
  detail: string;
}

@error
model NotFound extends ProblemDetail {
  title: "Not Found";
  status: 404;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/404";
  detail: string;
}

@error
model Conflict extends ProblemDetail {
  title: "Conflict";
  status: 409;
  type: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/409";
  detail: string;
}
